--- sf-nvim log utility functions
-- @license MIT

local Config = require("sf.config")
local JobUtils = require("sf.core.job_utils")
local Log = require("sf.core.log")

local Utils = {}

--- Get the path to store log list results
--- @return string The path to store log list JSON
function Utils.get_log_list_path()
  return Config:get_options().log_list_file
end

--- Process log list JSON response and convert to picker format
--- @param json_response string The JSON string from SF CLI apex list log command
--- @return boolean success True if processing was successful
--- @return table|nil logs Array of log items for picker, or nil if processing failed
--- @return string|nil error_message Error message if processing fails
function Utils.process_log_list(json_response)
  Log.deb("Processing log list...")

  -- Validate and parse the JSON response
  local success, parsed, error_message = JobUtils.validate_json_response(json_response, {
    status = "number",
    result = "table",
  })

  if not success then
    Log.deb("Failed to validate log list JSON:", error_message)
    return false, nil, error_message
  end

  Log.deb("Parsed log list:", parsed)

  -- Check if the parsed result has the expected structure
  if not parsed or not parsed.result or parsed.status ~= 0 then
    Log.deb("Invalid log list structure or command failed")
    return false, nil, "Invalid log list response format or command failed"
  end

  local logs = {}
  local log_records = parsed.result

  -- Handle case where result is an array of logs
  if type(log_records) == "table" then
    for _, log in ipairs(log_records) do
      if log.Id then
        -- Format dates for better readability (handle timezone format)
        local start_time = log.StartTime or "Unknown"

        if start_time ~= "Unknown" and start_time:match("T") then
          -- Handle both Z and +0000 timezone formats
          start_time = start_time:gsub("T", " "):gsub("%.%d+Z", ""):gsub("%+%d%d%d%d", "")
        end

        -- Format log size
        local log_size = "Unknown"

        if log.LogLength then
          local size_num = tonumber(log.LogLength)

          if size_num then
            if size_num > 1024 * 1024 then
              log_size = string.format("%.1f MB", size_num / (1024 * 1024))
            elseif size_num > 1024 then
              log_size = string.format("%.1f KB", size_num / 1024)
            else
              log_size = string.format("%d B", size_num)
            end
          end
        end

        -- Format status (sanitize and truncate long error messages for table display)
        local status = log.Status or "Unknown"
        --
        -- Sanitize status text to remove newlines and other problematic characters
        if status ~= "Unknown" then
          status = tostring(status):gsub("[\r\n\t]", " "):gsub("%s+", " "):gsub("^%s+", ""):gsub("%s+$", "")
        end

        local status_display = status

        if #status > 15 then
          status_display = status:sub(1, 12) .. "..."
        end

        table.insert(logs, {
          -- Store all the data we need for display
          id = log.Id or "Unknown",
          user_name = (log.LogUser and log.LogUser.Name) or "Unknown",
          start_time = start_time,
          duration = log.DurationMilliseconds and (log.DurationMilliseconds .. " ms") or "Unknown",
          size = log_size,
          status = status_display,
          status_full = status, -- Keep full status for preview
          operation = log.Operation or "Unknown",
          application = log.Application or "Unknown",
          request = log.Request or "Unknown",
          location = log.Location or "Unknown",
          log_data = log,
        })
      end
    end
  end

  Log.deb("Processed log list entries:", { count = #logs })

  return true, logs, nil
end

return Utils
