--- sf-nvim log picker module
-- @license MIT

local Const = require("sf.const")
local Log = require("sf.core.log")
local Snacks = require("snacks")

local Picker = {}

--- Create log selection picker using Snacks with fallback compatibility
--- @param logs table Array of log items
--- @param callback function Callback function to handle log selection
function Picker.create_log_selection_picker(logs, callback)
  if not logs or #logs == 0 then
    Log.notify("No debug logs found", vim.log.levels.INFO)
    return
  end

  -- Try the advanced picker format first, with fallback to simple format
  local picker_config = {
    items = logs,
    layout = {
      preset = "telescope",
      width = 0.9,
      height = 0.8,
    },
    format = function(item, _)
      -- Format with exact column specifications:
      -- ID: 18 chars + 1 for |
      -- Username: 13 chars + 2 spaces (start/end) + 1 for |
      -- Date: 19 chars + 2 spaces (start/end) + 1 for |
      -- Duration: 8 chars + 2 spaces (start/end) + 1 for |
      -- Status: 15 chars + 1 space at beginning

      local id = item.id or "Unknown"
      if #id > 18 then
        id = id:sub(1, 15) .. "..."
      end

      local username = item.user_name or "Unknown"
      if #username > 13 then
        username = username:sub(1, 10) .. "..."
      end

      local start_time = item.start_time or "Unknown"
      if #start_time > 19 then
        start_time = start_time:sub(1, 16) .. "..."
      end

      local duration = item.duration or "Unknown"
      if #duration > 8 then
        duration = duration:sub(1, 5) .. "..."
      end

      local status = item.status or "Unknown"
      if #status > 15 then
        status = status:sub(1, 12) .. "..."
      end

      return {
        { string.format("%-18s ", id), "SnacksPickerNormal" },
        { " ", "SnacksPickerComment" },
        { string.format("%-13s ", username), "SnacksPickerComment" },
        { " ", "SnacksPickerComment" },
        { string.format("%-19s ", start_time), "SnacksPickerComment" },
        { " ", "SnacksPickerComment" },
        { string.format("%-8s ", duration), "SnacksPickerComment" },
        { " ", "SnacksPickerComment" },
        { string.format("%s ", status), "SnacksPickerComment" },
      }
    end,
    confirm = function(picker, item)
      if picker and picker.close then
        picker:close()
      end
      if callback and type(callback) == "function" then
        callback(item)
      end
    end,
    preview = function(ctx)
      local item = ctx.item
      if not item then
        return
      end

      if not item then
        return { " No item selected" }
      end

      -- Handle header row
      if item.is_header then
        return {
          Const.ICONS.LOG_INFO .. " Salesforce Debug Logs",
          "",
          Const.ICONS.INFO .. " This picker displays debug logs from your default Salesforce org.",
          Const.ICONS.INFO .. " Select a log entry to view detailed information.",
          "",
          Const.ICONS.LOG_INFO .. " Column Layout:",
          "  " .. Const.ICONS.LOG_ID .. " Log ID (18 chars): Salesforce debug log identifier",
          "  " .. Const.ICONS.USER .. " User (13 chars): Name of the log owner",
          "  " .. Const.ICONS.TIME .. " Start Time (19 chars): When the log was created",
          "  " .. Const.ICONS.DURATION .. " Duration (8 chars): Execution time in milliseconds",
          "  " .. Const.ICONS.SUCCESS .. " Status (15 chars): Execution status or error message",
          "",
          Const.ICONS.INFO .. " Long values are truncated with '...' for table display.",
          Const.ICONS.INFO .. " Full details are shown in this preview panel when you select a log.",
        }
      end

      -- Helper function to get status icon and color
      local function get_status_info(status)
        local status_lower = (status or "unknown"):lower()

        if status_lower:match("success") then
          return Const.ICONS.SUCCESS, "Success"
        elseif status_lower:match("error") or status_lower:match("fail") then
          return Const.ICONS.ERROR, "Error"
        elseif status_lower:match("warning") or status_lower:match("warn") then
          return Const.ICONS.WARNING, "Warning"
        else
          return Const.ICONS.INFO, "Info"
        end
      end

      -- Helper function to get application icon
      local function get_app_icon(app)
        local app_lower = (app or "unknown"):lower()

        if app_lower:match("browser") then
          return Const.ICONS.BROWSER
        elseif app_lower:match("api") then
          return Const.ICONS.API
        elseif app_lower:match("batch") then
          return Const.ICONS.BATCH
        else
          return Const.ICONS.MOBILE
        end
      end

      -- Helper function to format duration with icon
      local function format_duration(duration)
        if not duration or duration == "Unknown" then
          return Const.ICONS.MEDIUM .. " Unknown"
        end

        local num = duration:match("(%d+)")

        if num then
          local ms = tonumber(num)

          if ms and ms > 1000 then
            return Const.ICONS.SLOW .. " " .. duration .. " (slow)"
          elseif ms and ms > 500 then
            return Const.ICONS.MEDIUM .. " " .. duration .. " (medium)"
          else
            return Const.ICONS.FAST .. " " .. duration .. " (fast)"
          end
        end

        return Const.ICONS.MEDIUM .. " " .. duration
      end

      -- Helper function to format size with icon
      local function format_size(size)
        if not size or size == "Unknown" then
          return Const.ICONS.MEDIUM_FILE .. " Unknown"
        end

        if size:match("MB") then
          return Const.ICONS.LARGE_FILE .. " " .. size .. " (large)"
        elseif size:match("KB") then
          return Const.ICONS.MEDIUM_FILE .. " " .. size .. " (medium)"
        else
          return Const.ICONS.SMALL_FILE .. " " .. size .. " (small)"
        end
      end

      -- Helper function to sanitize text by removing problematic characters
      local function sanitize_text(text)
        if not text or text == "" then
          return "Unknown"
        end

        -- Convert to string if not already
        text = tostring(text)

        -- Replace newlines, carriage returns, and tabs with spaces
        text = text:gsub("[\r\n\t]", " ")

        -- Replace multiple consecutive spaces with single space
        text = text:gsub("%s+", " ")

        -- Trim leading and trailing whitespace
        text = text:gsub("^%s+", ""):gsub("%s+$", "")

        return text
      end

      -- Helper function to wrap long text into multiple lines with proper alignment
      local function wrap_text_with_prefix(prefix, text, max_width)
        -- Sanitize the input text first
        local clean_text = sanitize_text(text)

        if not clean_text or clean_text == "" or clean_text == "Unknown" then
          return { prefix .. "Unknown" }
        end

        local lines = {}
        local remaining_text = clean_text
        local prefix_len = vim.fn.strdisplaywidth(prefix)
        local continuation_prefix = string.rep(" ", prefix_len)

        -- First line with the original prefix
        if #remaining_text <= max_width then
          table.insert(lines, prefix .. remaining_text)
        else
          -- Find the best break point within max_width
          local break_point = max_width

          for i = max_width, 1, -1 do
            if remaining_text:sub(i, i):match("%s") then
              break_point = i - 1
              break
            end
          end

          table.insert(lines, prefix .. remaining_text:sub(1, break_point))
          remaining_text = remaining_text:sub(break_point + 1):gsub("^%s+", "") -- Remove leading spaces

          -- Continue with wrapped lines
          while #remaining_text > 0 do
            if #remaining_text <= max_width then
              table.insert(lines, continuation_prefix .. remaining_text)
              break
            else
              break_point = max_width
              for i = max_width, 1, -1 do
                if remaining_text:sub(i, i):match("%s") then
                  break_point = i - 1
                  break
                end
              end

              table.insert(lines, continuation_prefix .. remaining_text:sub(1, break_point))
              remaining_text = remaining_text:sub(break_point + 1):gsub("^%s+", "")
            end
          end
        end

        return lines
      end

      local status_icon = get_status_info(item.status_full or item.status)
      local app_icon = get_app_icon(item.application)
      local duration_formatted = format_duration(item.duration)
      local size_formatted = format_size(item.size)

      -- Format status with proper line wrapping
      local status_prefix = status_icon .. " Status:       "
      local status_lines = wrap_text_with_prefix(status_prefix, item.status_full or item.status or "Unknown", 40)

      local details = {
        "                     " .. Const.ICONS.LOG_INFO .. " Log Information",
        "===========================================================",
        "",
        Const.ICONS.LOG_ID .. " Log ID:       " .. (item.id or "Unknown"),
        Const.ICONS.USER .. " User:         " .. (item.user_name or "Unknown"),
        Const.ICONS.TIME .. " Start Time:   " .. (item.start_time or "Unknown"),
        Const.ICONS.DURATION .. " Duration:     " .. duration_formatted,
        Const.ICONS.SIZE .. " Size:         " .. size_formatted,
      }

      -- Add the wrapped status lines
      for _, line in ipairs(status_lines) do
        table.insert(details, line)
      end

      -- Continue with technical details
      vim.list_extend(details, {
        "",
        "                    " .. Const.ICONS.TECHNICAL .. " Technical Details",
        "===========================================================",
        "",
        Const.ICONS.OPERATION .. " Operation:    " .. (item.operation or "Unknown"),
        app_icon .. " Application:  " .. (item.application or "Unknown"),
        Const.ICONS.REQUEST .. " Request:      " .. (item.request or "Unknown"),
        Const.ICONS.LOCATION .. " Location:     " .. (item.location or "Unknown"),
      })

      -- Add Salesforce URL if available
      if item.log_data and item.log_data.attributes and item.log_data.attributes.url then
        table.insert(details, "")
        table.insert(details, "                     " .. Const.ICONS.LINK .. " Salesforce URL")
        table.insert(details, "===========================================================")
        table.insert(details, "")
        table.insert(details, Const.ICONS.URL .. " " .. item.log_data.attributes.url)
      end

      -- Add metadata section if available
      if item.log_data then
        table.insert(details, "")
        table.insert(details, "                      " .. Const.ICONS.METADATA .. " Metadata")
        table.insert(details, "===========================================================")
        table.insert(details, "")

        -- Add key metadata fields with icons
        if item.log_data.DurationMilliseconds then
          table.insert(details, Const.ICONS.MEDIUM .. " Raw Duration: " .. item.log_data.DurationMilliseconds .. " ms")
        end
        if item.log_data.LogLength then
          table.insert(details, Const.ICONS.SIZE .. " Raw Size: " .. item.log_data.LogLength .. " bytes")
        end
        if item.log_data.attributes and item.log_data.attributes.type then
          table.insert(details, Const.ICONS.TYPE .. " Object Type: " .. item.log_data.attributes.type)
        end
      end

      vim.bo[ctx.buf].modifiable = true
      vim.api.nvim_buf_set_lines(ctx.buf, 0, -1, false, details)

      -- Set filetype for syntax highlighting
      -- vim.bo[ctx.buf].filetype = ""

      vim.bo[ctx.buf].modifiable = false

      return true -- Return true to indicate we handled the preview
    end,
  }

  -- Call Snacks picker with error handling
  local ok, err = pcall(Snacks.picker, picker_config)
  if not ok then
    Log.notify("Failed to create picker: " .. tostring(err), vim.log.levels.ERROR)
    --
    -- Fallback to simple notification
    local log_list = {}

    for i, log in ipairs(logs) do
      table.insert(log_list, string.format("%d. %s (%s)", i, log.id, log.status))
    end

    Log.notify("Available logs:\n" .. table.concat(log_list, "\n"), vim.log.levels.INFO)
  end
end

return Picker
