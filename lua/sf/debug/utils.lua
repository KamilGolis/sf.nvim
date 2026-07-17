local Config = require("sf.config")
local Const = require("sf.const")
local JobUtils = require("sf.core.job_utils")
local Log = require("sf.core.log").scoped("debug/utils")
local OrgUtils = require("sf.org.utils")
local PathUtils = require("sf.core.path_utils")

local DebugUtils = {}

--- Parse org.json response → extract Username.
--- @param json_response string The raw JSON from sf org display
--- @return string|nil username, string|nil error
function DebugUtils.parse_org_data(json_response)
  local ok, parsed, err = JobUtils.validate_json_response(json_response)

  if not ok then
    return nil, Const.SF_CLI_MESSAGES.DEBUG_WORKFLOW_INVALID_ORG_DATA .. ": " .. (err or "unknown error")
  end

  if parsed.status ~= 0 then
    return nil, Const.SF_CLI_MESSAGES.DEBUG_WORKFLOW_ORG_CMD_FAILED
  end

  local username = parsed.result and parsed.result.username

  if not username then
    return nil, Const.SF_CLI_MESSAGES.DEBUG_WORKFLOW_NO_USERNAME
  end

  return username, nil
end

--- Parse user.json response → extract Id (UserId) and Name.
--- @param json_response string The raw JSON from sf data record get
--- @return string|nil user_id, string|nil user_name, string|nil error
function DebugUtils.parse_user_data(json_response)
  local ok, parsed, err = JobUtils.validate_json_response(json_response)

  if not ok then
    return nil, nil, Const.SF_CLI_MESSAGES.DEBUG_WORKFLOW_INVALID_USER_DATA .. ": " .. (err or "unknown error")
  end

  if parsed.status ~= 0 then
    return nil, nil, Const.SF_CLI_MESSAGES.DEBUG_WORKFLOW_USER_CMD_FAILED
  end

  local user_id = parsed.result and parsed.result.Id
  local user_name = parsed.result and parsed.result.Name

  if not user_id then
    return nil, nil, Const.SF_CLI_MESSAGES.DEBUG_WORKFLOW_NO_USER_ID
  end

  return user_id, user_name, nil
end

--- Parse debug-level.json → array of debug level records.
--- @param json_response string The raw JSON from sf data query
--- @return table|nil debug_levels, string|nil error
function DebugUtils.parse_debug_levels(json_response)
  local ok, parsed, err = JobUtils.validate_json_response(json_response)

  if not ok then
    return nil, Const.SF_CLI_MESSAGES.DEBUG_WORKFLOW_INVALID_DEBUG_DATA .. ": " .. (err or "unknown error")
  end

  if parsed.status ~= 0 then
    return nil, Const.SF_CLI_MESSAGES.DEBUG_WORKFLOW_DEBUG_CMD_FAILED
  end

  local records = parsed.result and parsed.result.records

  if not records or type(records) ~= "table" then
    return nil, Const.SF_CLI_MESSAGES.DEBUG_WORKFLOW_NO_DEBUG_RECORDS
  end

  local debug_levels = {}

  for _, record in ipairs(records) do
    table.insert(debug_levels, record)
  end

  return debug_levels, nil
end

--- Parse trace flags JSON → store all trace flags.
--- For sf data record get, the result may be a single record or an array.
--- @param json_response string The raw JSON from sf data record get
--- @return table|nil trace_flags, string|nil error
function DebugUtils.parse_trace_flags(json_response)
  local ok, parsed, err = JobUtils.validate_json_response(json_response)

  if not ok then
    return nil, Const.SF_CLI_MESSAGES.DEBUG_WORKFLOW_INVALID_TRACE_DATA .. ": " .. (err or "unknown error")
  end

  if parsed.status ~= 0 then
    return nil, Const.SF_CLI_MESSAGES.DEBUG_WORKFLOW_TRACE_CMD_FAILED
  end

  local result = parsed.result

  if result == nil or result == vim.NIL then
    return {}, nil
  end

  -- Single record returned (sf data record get)
  if result.Id then
    return { result }, nil
  end

  -- Array of records returned
  if type(result) == "table" then
    local flags = {}

    for _, item in ipairs(result) do
      table.insert(flags, item)
    end

    if #flags > 0 then
      return flags, nil
    end
  end

  return {}, nil
end

--- Convert field-values table to CLI value string: "ApexCode=Fine DeveloperName=Foo ..."
--- @param fields table { DeveloperName = "...", ApexCode = "...", ... }
--- @return string
function DebugUtils.fields_to_value_string(fields)
  local parts = {}

  for _, field_def in ipairs(Const.DEBUG_LEVEL_FIELDS) do
    local field_name = field_def.name
    local value = fields[field_name]

    if value and value ~= "" then
      table.insert(parts, field_name .. "=" .. value)
    end
  end

  return table.concat(parts, " ")
end

--- Save debug level JSON to .sf/.sf.nvim/debug-levels/<DeveloperName>.json.
--- Ensures directory exists.
--- @param fields table The field values to save
function DebugUtils.save_debug_level_json(fields)
  local dir = Config:get_options().debug_levels_dir
  vim.fn.mkdir(dir, "p")

  local safe_name = fields.DeveloperName and fields.DeveloperName:gsub("[^%w_-]", "_") or ""
  if safe_name == "" then
    Log.deb("Empty DeveloperName, cannot save JSON")
    return
  end

  local filepath = PathUtils.join(dir, safe_name .. ".json")
  local data = vim.json.encode(fields)
  local file, err = io.open(filepath, "w")

  if file then
    file:write(data)
    file:close()
  else
    Log.deb("Failed to save debug level JSON:", filepath, err)
  end
end

--- Build a picker item from a debug level record for display.
--- @param dl table DebugLevel record with Id, DeveloperName, MasterLabel, etc.
--- @return table Picker item with id, text, description, details, developer_name, master_label
function DebugUtils.debug_level_to_picker_item(dl)
  return {
    id = dl.Id,
    developer_name = dl.DeveloperName,
    master_label = dl.MasterLabel,
    text = dl.DeveloperName .. " (" .. dl.MasterLabel .. ")",
    description = "Created: " .. (dl.CreatedDate or "unknown"),
    details = dl,
  }
end

--- Run the 4-step workflow sequentially via coroutine await calls:
---   1. sf org display → parse Username
---   2. sf data record get -s User → parse Id (UserId)
---   3. sf data query -q "SELECT ... FROM DebugLevel" → parse records
---   4. sf data record get -s TraceFlag -w → parse trace flags
---
--- On success, calls on_complete(true, data).
--- On any failure, calls on_complete(false, nil, error_msg).
---
--- @param on_complete fun(success: boolean, data: table|nil, error_msg: string|nil)
---   data = { username, user_id, debug_levels, trace_flags }
function DebugUtils.run_workflow(on_complete)
  local Async = require("sf.core.async")
  local Progress = require("sf.core.progress")
  local config = Config:get_options()
  local executable_path = config.sf_cli_path or "sf"
  local workflow_data = {}

  Async.async(function()
    if not Async.await_cli_check() then
      if on_complete then
        on_complete(false, nil, Const.SF_CLI_MESSAGES.CLI_NOT_INSTALLED)
      end

      return
    end

    local has_default_org, target_org, org_error = OrgUtils.check_default_org()
    if not has_default_org then
      Log.notify(org_error or Const.SF_CLI_MESSAGES.NO_DEFAULT_ORG, vim.log.levels.ERROR)

      if on_complete then
        on_complete(false, nil, org_error or Const.SF_CLI_MESSAGES.NO_DEFAULT_ORG)
      end

      return
    end

    -- Step 1: Get org display
    local org_handle = Progress.create_handle({ title = Const.SF_CLI_MESSAGES.DEBUG_LEVEL_FETCHING_ORG })
    local org_args = Const.get_org_display_args(target_org)
    local org_stdout, org_code = Async.await_system(executable_path, org_args)

    if org_code ~= 0 then
      org_handle:finish()

      if on_complete then
        on_complete(false, nil, "Failed to get org info")
      end

      return
    end

    local username, org_parse_err = DebugUtils.parse_org_data(org_stdout)
    if not username then
      org_handle:report({ message = Const.SF_CLI_MESSAGES.DEBUG_LEVEL_WORKFLOW_FAILED, percentage = 100 })
      org_handle:finish()

      if on_complete then
        on_complete(false, nil, org_parse_err)
      end

      return
    end

    org_handle:finish()
    workflow_data.username = username

    -- Step 2: Get User record
    local user_handle = Progress.create_handle({ title = Const.SF_CLI_MESSAGES.DEBUG_LEVEL_FETCHING_USER })
    local user_args = Const.get_record_get_args("User", "Username='" .. username .. "'", target_org)
    local user_stdout, user_code = Async.await_system(executable_path, user_args)
    if user_code ~= 0 then
      user_handle:finish()

      if on_complete then
        on_complete(false, nil, "Failed to fetch user data")
      end

      return
    end

    local user_id, user_name, user_parse_err = DebugUtils.parse_user_data(user_stdout)
    if not user_id then
      user_handle:report({ message = Const.SF_CLI_MESSAGES.DEBUG_LEVEL_WORKFLOW_FAILED, percentage = 100 })
      user_handle:finish()

      if on_complete then
        on_complete(false, nil, user_parse_err)
      end

      return
    end

    user_handle:finish()
    workflow_data.user_id = user_id
    workflow_data.user_name = user_name

    -- Step 3: Query debug levels
    local debug_handle = Progress.create_handle({ title = Const.SF_CLI_MESSAGES.DEBUG_LEVEL_FETCHING_LEVELS })
    local debug_args = Const.get_query_args(Const.QUERIES.DEBUG_LEVEL_SELECT, target_org, config.api_version)
    local debug_stdout, debug_code = Async.await_system(executable_path, debug_args)

    if debug_code ~= 0 then
      debug_handle:report({ message = Const.SF_CLI_MESSAGES.DEBUG_LEVEL_WORKFLOW_FAILED, percentage = 100 })
      debug_handle:finish()

      if on_complete then
        on_complete(false, nil, "Failed to fetch debug levels")
      end

      return
    end

    local levels, debug_parse_err = DebugUtils.parse_debug_levels(debug_stdout)
    if not levels then
      debug_handle:report({ message = Const.SF_CLI_MESSAGES.DEBUG_LEVEL_WORKFLOW_FAILED, percentage = 100 })
      debug_handle:finish()

      if on_complete then
        on_complete(false, nil, debug_parse_err)
      end

      return
    end

    debug_handle:finish()
    workflow_data.debug_levels = levels

    -- Step 4: Fetch trace flags
    local trace_handle = Progress.create_handle({ title = Const.SF_CLI_MESSAGES.DEBUG_LEVEL_FETCHING_TRACES })
    local trace_args = Const.get_tooling_record_get_args(
      "TraceFlag",
      "TracedEntityId='" .. workflow_data.user_id .. "'",
      target_org,
      config.api_version
    )

    local trace_stdout, trace_code = Async.await_system(executable_path, trace_args)
    if trace_code ~= 0 then
      workflow_data.trace_flags = {}
      Log.notify("Failed to fetch trace flags", vim.log.levels.WARN)
      trace_handle:report({ message = Const.SF_CLI_MESSAGES.DEBUG_LEVEL_WORKFLOW_SUCCESS, percentage = 100 })
      trace_handle:finish()

      if on_complete then
        on_complete(true, workflow_data, nil)
      end

      return
    end

    local traces, trace_parse_err = DebugUtils.parse_trace_flags(trace_stdout)
    if not traces then
      traces = {}
    end

    workflow_data.trace_flags = traces

    trace_handle:report({ message = Const.SF_CLI_MESSAGES.DEBUG_LEVEL_WORKFLOW_SUCCESS, percentage = 100 })
    trace_handle:finish()

    if on_complete then
      on_complete(true, workflow_data, nil)
    end
  end)()
end

return DebugUtils
