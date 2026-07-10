--- sf-nvim trace flag picker module
-- @license MIT

local Const = require("sf.const")
local TraceUtils = require("sf.trace.utils")

local Picker = {}

--- Show a Snacks picker for selecting a TraceFlag with details preview.
--- @param trace_flags table Array of TraceFlag records from the workflow
--- @param on_select fun(tf: table) Called with the selected full TraceFlag record
function Picker.create_trace_flag_picker(trace_flags, on_select)
  local Snacks = require("snacks")

  local items = {}
  for _, tf in ipairs(trace_flags) do
    local start_str = TraceUtils.format_datetime_local(tf.StartDate)
    local exp_str = TraceUtils.format_datetime_local(tf.ExpirationDate)
    local label = "TraceFlag: " .. (tf.DebugLevelId or "unknown")
    local desc = start_str .. " → " .. exp_str

    table.insert(items, {
      text = label,
      description = desc,
      details = tf,
    })
  end

  Snacks.picker({
    title = "Select Trace Flag",
    items = items,
    layout = { preset = "telescope", width = 0.9, height = 0.8 },
    format = function(item, _)
      local name = item.text or ""
      if #name > 30 then
        name = name:sub(1, 27) .. "..."
      end

      local description = item.description or ""
      if #description > 40 then
        description = description:sub(1, 37) .. "..."
      end

      return {
        { string.format("%-30s ", name), "SnacksPickerNormal" },
        { " ", "SnacksPickerComment" },
        { string.format("%-40s ", description), "SnacksPickerComment" },
      }
    end,
    confirm = function(picker, item)
      picker:close()

      if not item or not item.details then
        return
      end

      on_select(item.details)
    end,
    preview = function(ctx)
      local item = ctx.item
      if not item then
        return { " No item selected" }
      end

      local tf = ctx.item.details
      if not tf then
        return { " No details available" }
      end

      local function sanitize_text(text)
        if not text or text == "" then
          return "Unknown"
        end

        text = tostring(text)
        text = text:gsub("[\r\n\t]", " ")
        text = text:gsub("%s+", " ")
        text = text:gsub("^%s+", ""):gsub("%s+$", "")

        return text
      end

      local start_fmt = TraceUtils.format_datetime_local(tf.StartDate)
      local exp_fmt = TraceUtils.format_datetime_local(tf.ExpirationDate)

      if start_fmt == "" then
        start_fmt = "Unknown"
      end

      if exp_fmt == "" then
        exp_fmt = "Unknown"
      end

      local details = {
        "                     " .. Const.ICONS.LOG_INFO .. " Trace Flag Details",
        "===========================================================",
        "",
        Const.ICONS.LOG_ID .. " Id:              " .. sanitize_text(tf.Id),
        Const.ICONS.USER .. " TracedEntityId:  " .. sanitize_text(tf.TracedEntityId),
        Const.ICONS.INFO .. " DebugLevelId:    " .. sanitize_text(tf.DebugLevelId),
        Const.ICONS.LOG_INFO .. " LogType:         " .. sanitize_text(tf.LogType),
        Const.ICONS.TIME .. " StartDate:       " .. start_fmt,
        Const.ICONS.TIME .. " ExpirationDate:  " .. exp_fmt,
        "",
        "                    " .. Const.ICONS.METADATA .. " Log Categories",
        "===========================================================",
        "",
        "Apex Code:       " .. sanitize_text(tf.ApexCode),
        "Apex Profiling:  " .. sanitize_text(tf.ApexProfiling),
        "Callout:         " .. sanitize_text(tf.Callout),
        "Database:        " .. sanitize_text(tf.Database),
        "System:          " .. sanitize_text(tf.System),
        "Validation:      " .. sanitize_text(tf.Validation),
        "Visualforce:     " .. sanitize_text(tf.Visualforce),
        "Workflow:        " .. sanitize_text(tf.Workflow),
      }

      vim.bo[ctx.buf].modifiable = true
      vim.api.nvim_buf_set_lines(ctx.buf, 0, -1, false, details)
      vim.bo[ctx.buf].modifiable = false

      return true
    end,
  })
end

return Picker
