--- sf-nvim trace flag utility functions
-- @license MIT

local Const = require("sf.const")

local TraceUtils = {}

--- Format an ISO datetime string to local display format "dd.mm.yyyy HH:MM".
--- @param iso string|nil The ISO datetime string (e.g. "2022-12-15T00:26:04.000+0000")
--- @return string Formatted date string or empty string if input is nil/empty
function TraceUtils.format_datetime_local(iso)
  if not iso or iso == "" then
    return ""
  end

  local year, month, day, hour, min = string.match(iso, Const.DATE_PATTERNS.ISO_PARSE)
  if not year then
    return ""
  end

  -- ISO components are UTC. Compute the epoch, then offset by the local timezone
  -- difference for that specific date (handles DST correctly).
  -- os.time interprets the table as local time and auto-detects DST based on date.
  local local_epoch = os.time({
    year = tonumber(year),
    month = tonumber(month),
    day = tonumber(day),
    hour = tonumber(hour),
    min = tonumber(min),
    sec = 0,
  })

  -- Compute the local timezone offset at local_epoch
  local l = os.date("*t", local_epoch)
  local u = os.date("!*t", local_epoch)
  local offset = (l.hour - u.hour) * 3600 + (l.min - u.min) * 60 + (l.sec - u.sec)

  if offset > 43200 then
    offset = offset - 86400
  elseif offset < -43200 then
    offset = offset + 86400
  end

  -- Adjust: local_epoch is epoch for H:M local. We want epoch for H:M UTC.
  -- If offset = +7200 (CEST), then H:M local corresponds to (H-2):M UTC.
  -- To get epoch for H:M UTC, add offset.
  local utc_epoch = local_epoch + offset
  return os.date("%d.%m.%Y %H:%M", utc_epoch)
end

--- Parse a local datetime string "dd.mm.yyyy HH:MM" to ISO format "YYYY-MM-DDTHH:MM:SS.000+0000".
--- @param local_str string The datetime string in "dd.mm.yyyy HH:MM" format
--- @return string|nil iso_string The ISO formatted string, or nil on failure
--- @return string|nil error_message Error description if parsing fails
function TraceUtils.parse_datetime_local(local_str)
  if not local_str or local_str == "" then
    return nil, Const.SF_CLI_MESSAGES.TRACE_EMPTY_DATE
  end

  local day, month, year, hour, min = string.match(local_str, Const.DATE_PATTERNS.LOCAL_PARSE)
  if not day then
    return nil, Const.SF_CLI_MESSAGES.TRACE_INVALID_DATE_FORMAT
  end

  local ok, epoch = pcall(os.time, {
    year = tonumber(year),
    month = tonumber(month),
    day = tonumber(day),
    hour = tonumber(hour),
    min = tonumber(min),
    sec = 0,
  })

  if not ok then
    return nil, Const.SF_CLI_MESSAGES.TRACE_INVALID_DATE_VALUES
  end

  return os.date("!%Y-%m-%dT%H:%M:%S.000+0000", epoch), nil
end

--- Get current time formatted as "dd.mm.yyyy HH:MM".
--- @return string
function TraceUtils.now_local()
  return os.date("%d.%m.%Y %H:%M")
end

--- Get current time + 1 hour formatted as "dd.mm.yyyy HH:MM".
--- @return string
function TraceUtils.now_plus_1h_local()
  return os.date("%d.%m.%Y %H:%M", os.time() + 3600)
end

--- Extract the picklist fields from a DebugLevel record that are required by TraceFlag.
--- @param dl table A DebugLevel record with fields like ApexCode, ApexProfiling, etc.
--- @return table { ApexCode, ApexProfiling, Callout, Database, System, Validation, Visualforce, Workflow, LogType }
function TraceUtils.required_trace_fields_from_debug_level(dl)
  local fields = {}

  for _, name in ipairs(Const.TRACE_FLAG_PICKLIST_FIELDS) do
    fields[name] = dl[name] or "NONE"
  end

  fields.LogType = "USER_DEBUG"
  return fields
end

--- Build the CLI -v value string for sf data create/update record command.
--- @param fields table The required fields from required_trace_fields_from_debug_level
--- @param selected_dl table The selected DebugLevel record (must have Id)
--- @param user_id string The User Id for TracedEntityId
--- @param start_iso string StartDate in ISO format
--- @param exp_iso string ExpirationDate in ISO format
--- @return string The formatted value string
function TraceUtils.build_trace_value_string(fields, selected_dl, user_id, start_iso, exp_iso)
  local parts = {}

  table.insert(parts, "DebugLevelId=" .. selected_dl.Id)
  table.insert(parts, "StartDate=" .. start_iso)
  table.insert(parts, "ExpirationDate=" .. exp_iso)
  table.insert(parts, "LogType=" .. fields.LogType)
  table.insert(parts, "TracedEntityId=" .. user_id)

  for _, name in ipairs(Const.TRACE_FLAG_PICKLIST_FIELDS) do
    local value = fields[name] or "NONE"

    -- Enclose values with spaces in single quotes
    if string.find(value, " ") then
      table.insert(parts, name .. "='" .. value .. "'")
    else
      table.insert(parts, name .. "=" .. value)
    end
  end

  return table.concat(parts, " ")
end

--- Check if the error message indicates an overlapping trace flag conflict.
--- @param err_msg string|nil The error message from the CLI response
--- @return boolean
function TraceUtils.is_overlap_error(err_msg)
  if not err_msg then
    return false
  end

  return err_msg:find("already being traced") ~= nil or err_msg:find("overlap") ~= nil
end

return TraceUtils
