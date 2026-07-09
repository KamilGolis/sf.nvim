--- sf-nvim debug level utility functions
-- @license MIT

local Config = require("sf.config")
local Connector = require("sf.org.connect")
local Const = require("sf.const")
local JobUtils = require("sf.core.job_utils")
local Log = require("sf.core.log")
local OrgUtils = require("sf.org.utils")
local PathUtils = require("sf.core.path_utils")

local DebugUtils = {}

--- Parse org.json response → extract Username.
--- @param json_response string The raw JSON from sf org display
--- @return string|nil username, string|nil error
function DebugUtils.parse_org_data(json_response)
  local ok, parsed, err = JobUtils.validate_json_response(json_response)

  if not ok then
    return nil, "Invalid org data response: " .. (err or "unknown error")
  end

  if parsed.status ~= 0 then
    return nil, "Org display command failed"
  end

  local username = parsed.result and parsed.result.username

  if not username then
    return nil, "Could not find Username in org data"
  end

  return username, nil
end

--- Parse user.json response → extract Id (UserId).
--- @param json_response string The raw JSON from sf data record get
--- @return string|nil user_id, string|nil error
function DebugUtils.parse_user_data(json_response)
  local ok, parsed, err = JobUtils.validate_json_response(json_response)

  if not ok then
    return nil, "Invalid user data response: " .. (err or "unknown error")
  end

  if parsed.status ~= 0 then
    return nil, "User record get command failed"
  end

  local user_id = parsed.result and parsed.result.Id

  if not user_id then
    return nil, "Could not find Id in user data"
  end

  return user_id, nil
end

--- Parse debug-level.json → array of debug level records.
--- @param json_response string The raw JSON from sf data query
--- @return table|nil debug_levels, string|nil error
function DebugUtils.parse_debug_levels(json_response)
  local ok, parsed, err = JobUtils.validate_json_response(json_response)

  if not ok then
    return nil, "Invalid debug levels response: " .. (err or "unknown error")
  end

  if parsed.status ~= 0 then
    return nil, "Debug level query command failed"
  end

  local records = parsed.result and parsed.result.records

  if not records or type(records) ~= "table" then
    return nil, "No debug level records found"
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
    return nil, "Invalid trace flags response: " .. (err or "unknown error")
  end

  if parsed.status ~= 0 then
    return nil, "Trace flag get command failed"
  end

  local result = parsed.result

  if not result then
    return nil, "No trace flag data found"
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

  local filepath = PathUtils.join(dir, fields.DeveloperName .. ".json")
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

--- Run the 4-step workflow sequentially via nested CLI jobs:
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
  local state = require("sf.core.state")
  state.start("debug")

  local config = Config:get_options()

  Connector:check_cli(function()
    local has_default_org, target_org, org_error = OrgUtils.check_default_org()

    if not has_default_org then
      state.finish("debug")
      vim.notify(org_error or Const.SF_CLI_MESSAGES.NO_DEFAULT_ORG, vim.log.levels.ERROR)

      if on_complete then
        on_complete(false, nil, org_error or Const.SF_CLI_MESSAGES.NO_DEFAULT_ORG)
      end

      return
    end

    local cli_valid, executable_path, error_msg = JobUtils.validate_cli_installation(config.sf_cli_path)
    if not cli_valid or not executable_path then
      state.finish("debug")
      vim.notify(error_msg or Const.SF_CLI_MESSAGES.NOT_FOUND, vim.log.levels.ERROR)

      if on_complete then
        on_complete(false, nil, error_msg or Const.SF_CLI_MESSAGES.NOT_FOUND)
      end

      return
    end

    local workflow_data = {}
    local context

    -- Fetch trace flags for the UserId, then call on_complete
    local function fetch_trace_flags_and_finish()
      local trace_args =
        Const.get_record_get_args("TraceFlag", "TracedEntityId='" .. workflow_data.user_id .. "'", target_org)

      context = JobUtils.create_progress_context(
        Const.SF_CLI_MESSAGES.DEBUG_LEVEL_FETCHING_TRACES,
        Const.SF_CLI_MESSAGES.DEBUG_LEVEL_WORKFLOW_SUCCESS,
        Const.SF_CLI_MESSAGES.DEBUG_LEVEL_WORKFLOW_FAILED
      )

      local trace_job = JobUtils.create_cli_job(executable_path, trace_args, {
        on_success = function(job, _)
          local result = table.concat(job:result(), "\n")
          local traces, parse_err = DebugUtils.parse_trace_flags(result)

          if not traces then
            traces = {}
          end

          workflow_data.trace_flags = traces

          context.handle:report({ message = Const.SF_CLI_MESSAGES.DEBUG_LEVEL_WORKFLOW_SUCCESS, percentage = 100 })
          context.handle:finish()
          state.finish("debug")

          if on_complete then
            on_complete(true, workflow_data, nil)
          end
        end,
        on_error = function(job, return_val)
          local stderr = job:stderr_result()
          Log.deb("Trace flags fetch error", { return_val = return_val, stderr = stderr })
          workflow_data.trace_flags = {}

          context.handle:report({ message = Const.SF_CLI_MESSAGES.DEBUG_LEVEL_WORKFLOW_SUCCESS, percentage = 100 })
          context.handle:finish()
          state.finish("debug")

          if on_complete then
            on_complete(true, workflow_data, nil)
          end
        end,
      })
      trace_job:start()
    end

    -- Query all DebugLevel records, then fetch trace flags
    local function fetch_debug_levels_and_proceed()
      local query =
        "SELECT Id,ApexCode,ApexProfiling,Callout,CreatedDate,DataAccess,Database,DeveloperName,Language,MasterLabel,Nba,System,Validation,Visualforce,Wave,Workflow FROM DebugLevel"
      local debug_args = Const.get_query_args(query, target_org)

      context = JobUtils.create_progress_context(
        Const.SF_CLI_MESSAGES.DEBUG_LEVEL_FETCHING_LEVELS,
        Const.SF_CLI_MESSAGES.DEBUG_LEVEL_WORKFLOW_SUCCESS,
        Const.SF_CLI_MESSAGES.DEBUG_LEVEL_WORKFLOW_FAILED
      )

      local debug_job = JobUtils.create_cli_job(executable_path, debug_args, {
        on_success = function(job, _)
          local result = table.concat(job:result(), "\n")
          local levels, parse_err = DebugUtils.parse_debug_levels(result)

          if not levels then
            context.handle:report({ message = Const.SF_CLI_MESSAGES.DEBUG_LEVEL_WORKFLOW_FAILED, percentage = 100 })
            context.handle:finish()
            state.finish("debug")

            if on_complete then
              on_complete(false, nil, parse_err)
            end

            return
          end
          workflow_data.debug_levels = levels
          context.handle:finish()

          fetch_trace_flags_and_finish()
        end,
        on_error = function(job, return_val)
          local stderr = job:stderr_result()
          Log.deb("Debug levels fetch error", { return_val = return_val, stderr = stderr })

          JobUtils.handle_cli_error(return_val, context)
          state.finish("debug")

          if on_complete then
            on_complete(false, nil, "Failed to fetch debug levels")
          end
        end,
      })

      debug_job:start()
    end

    -- Get User record by username, extract Id, then query debug levels
    local function fetch_user_and_proceed(username)
      workflow_data.username = username
      local user_args = Const.get_record_get_args("User", "Username='" .. username .. "'", target_org)

      context = JobUtils.create_progress_context(
        Const.SF_CLI_MESSAGES.DEBUG_LEVEL_FETCHING_USER,
        Const.SF_CLI_MESSAGES.DEBUG_LEVEL_WORKFLOW_SUCCESS,
        Const.SF_CLI_MESSAGES.DEBUG_LEVEL_WORKFLOW_FAILED
      )

      local user_job = JobUtils.create_cli_job(executable_path, user_args, {
        on_success = function(job, _)
          local result = table.concat(job:result(), "\n")
          local user_id, parse_err = DebugUtils.parse_user_data(result)

          if not user_id then
            context.handle:report({ message = Const.SF_CLI_MESSAGES.DEBUG_LEVEL_WORKFLOW_FAILED, percentage = 100 })
            context.handle:finish()
            state.finish("debug")

            if on_complete then
              on_complete(false, nil, parse_err)
            end

            return
          end

          workflow_data.user_id = user_id
          context.handle:finish()

          fetch_debug_levels_and_proceed()
        end,
        on_error = function(job, return_val)
          local stderr = job:stderr_result()

          Log.deb("User fetch error", { return_val = return_val, stderr = stderr })
          JobUtils.handle_cli_error(return_val, context)
          state.finish("debug")

          if on_complete then
            on_complete(false, nil, "Failed to fetch user data")
          end
        end,
      })

      user_job:start()
    end

    -- Start step 1: Get org display
    context = JobUtils.create_progress_context(
      Const.SF_CLI_MESSAGES.DEBUG_LEVEL_FETCHING_ORG,
      Const.SF_CLI_MESSAGES.DEBUG_LEVEL_WORKFLOW_SUCCESS,
      Const.SF_CLI_MESSAGES.DEBUG_LEVEL_WORKFLOW_FAILED
    )

    local org_args = Const.get_org_display_args(target_org)
    local org_job = JobUtils.create_cli_job(executable_path, org_args, {
      on_success = function(job, _)
        local result = table.concat(job:result(), "\n")
        local username, parse_err = DebugUtils.parse_org_data(result)

        if not username then
          context.handle:report({ message = Const.SF_CLI_MESSAGES.DEBUG_LEVEL_WORKFLOW_FAILED, percentage = 100 })
          context.handle:finish()
          state.finish("debug")

          if on_complete then
            on_complete(false, nil, parse_err)
          end

          return
        end

        context.handle:finish()
        fetch_user_and_proceed(username)
      end,
      on_error = function(job, return_val)
        local stderr = job:stderr_result()

        Log.deb("Org display error", { return_val = return_val, stderr = stderr })
        JobUtils.handle_cli_error(return_val, context)
        state.finish("debug")

        if on_complete then
          on_complete(false, nil, "Failed to get org info")
        end
      end,
    })

    org_job:start()
  end)
end

return DebugUtils
