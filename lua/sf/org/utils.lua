local Snacks = require("snacks")

local Config = require("sf.config")
local Const = require("sf.const")
local JobUtils = require("sf.core.job_utils")

local M = {}

-- =============================================================================
-- TYPE DEFINITIONS
-- =============================================================================

--- Org picker item structure for standardized org selection UI
--- @class OrgPickerItem
--- @field text string Display text (alias)
--- @field description string Org username
--- @field details string Instance URL
--- @field org_data table Full org data from SF CLI

-- =============================================================================
-- ORG DATA PROCESSING UTILITIES
-- =============================================================================

--- Processes org list JSON response and converts it to picker-compatible format
--- @param json_response string The JSON string from SF CLI org list command
--- @return boolean success True if processing was successful
--- @return table|nil orgs Array of OrgPickerItem objects, or nil if processing failed
--- @return string|nil error_message Error message if processing fails
--- @usage local ok, orgs, err = OrgUtils.process_org_list(json_string)
function M.process_org_list(json_response)
  -- Validate and parse the JSON response
  local success, parsed, error_message = JobUtils.validate_json_response(json_response, {
    result = "table",
  })

  if not success then
    return false, nil, error_message
  end

  -- Check if the parsed result has the expected structure
  if not parsed or not parsed.result or not parsed.result.nonScratchOrgs then
    return false, nil, Const.SF_CLI_MESSAGES.JSON_PARSE_ERROR
  end

  local orgs = {}
  for _, org in ipairs(parsed.result.nonScratchOrgs) do
    table.insert(orgs, {
      text = org.alias,
      description = org.username,
      details = org.instanceUrl,
      org_data = org,
    })
  end

  return true, orgs, nil
end

-- =============================================================================
-- ORG SELECTION UI UTILITIES
-- =============================================================================

--- Creates a standardized org selection picker using Snacks
--- @param orgs table Array of OrgPickerItem objects
--- @param callback function Callback function to handle org selection, receives selected item
--- @usage OrgUtils.create_org_selection_picker(orgs, function(item) print("Selected:", item.text) end)
function M.create_org_selection_picker(orgs, callback)
  Snacks.picker({
    items = orgs,
    layout = {
      preset = "vscode",
    },
    format = function(item, _)
      local ret = {}
      ret[#ret + 1] = {
        item.org_data.alias .. " (" .. item.org_data.username .. ")",
      }
      return ret
    end,
    confirm = function(picker, item)
      picker:close()
      if callback then
        callback(item)
      end
    end,
  })
end

-- =============================================================================
-- ORG VALIDATION UTILITIES
-- =============================================================================

--- Checks if a default org is set by reading the SF CLI config
--- @return boolean success True if default org is set
--- @return string|nil org_username The username of the default org, or nil if not set
--- @return string|nil error_message Error message if check fails
--- @usage local has_org, username, err = OrgUtils.check_default_org()
function M.check_default_org()
  local config_path = ".sf/config.json"
  
  -- Check if config file exists
  if vim.fn.filereadable(config_path) ~= 1 then
    return false, nil, Const.SF_CLI_MESSAGES.NO_DEFAULT_ORG
  end

  -- Read and parse the config file
  local file_content = vim.fn.readfile(config_path)
  if not file_content or #file_content == 0 then
    return false, nil, Const.SF_CLI_MESSAGES.NO_DEFAULT_ORG
  end

  local json_string = table.concat(file_content, "\n")
  local ok, config = pcall(vim.json.decode, json_string)

  if not ok or not config then
    return false, nil, "Failed to parse SF CLI config file"
  end

  -- Check if target-org is set
  local target_org = config["target-org"]
  if not target_org or target_org == "" then
    return false, nil, Const.SF_CLI_MESSAGES.NO_DEFAULT_ORG
  end

  return true, target_org, nil
end

-- =============================================================================
-- ORG CONFIGURATION UTILITIES
-- =============================================================================

--- Sets the target org using SF CLI with progress reporting
--- @param org_data table The org data object containing username and alias
--- @param context table|nil Optional progress context, will create one if not provided
--- @param callback function|nil Optional callback to execute after setting org, receives success boolean and message
--- @usage OrgUtils.set_target_org(org_data, nil, function(success, msg) print("Result:", success, msg) end)
function M.set_target_org(org_data, context, callback)
  -- Create progress context if not provided
  local progress_context = context
    or JobUtils.create_progress_context(
      Const.SF_CLI_MESSAGES.ORG_SET_TITLE,
      Const.SF_CLI_MESSAGES.ORG_SET_SUCCESS,
      Const.SF_CLI_MESSAGES.ORG_SET_FAILED
    )

  -- Validate CLI installation
  local cli_valid, executable_path, error_msg =
    JobUtils.validate_cli_installation(Config:get_options().sf_cli_path)
  if not cli_valid or not executable_path then
    local error_message = error_msg or "SF CLI validation failed"
    JobUtils.handle_cli_error(1, progress_context, error_message)
    if callback then
      callback(false, error_message)
    end
    return
  end

  -- Create and start the job to set target org
  local args = vim.split(Const.SF_CLI.ORG.CONFIG.SET.CMD, " ")
  table.insert(args, Const.SF_CLI.ORG.CONFIG.SET.ARGS.TARGET_ORG)
  table.insert(args, org_data.username)
  local job = JobUtils.create_cli_job(executable_path, args, {
    on_success = function(job, return_val)
      JobUtils.handle_cli_result(job, return_val, progress_context, function()
        -- Notify success with org details
        local success_message = string.format(
          Const.SF_CLI_MESSAGES.ORG_SET_SUCCESS_FORMAT,
          org_data.alias or org_data.username
        )
        vim.notify(success_message, vim.log.levels.INFO)

        if callback then
          callback(true, success_message)
        end
      end, nil)
    end,
    on_error = function(job, return_val)
      JobUtils.handle_cli_result(job, return_val, progress_context, nil, function()
        vim.notify(Const.SF_CLI_MESSAGES.ORG_SET_ERROR, vim.log.levels.ERROR)

        if callback then
          callback(false, Const.SF_CLI_MESSAGES.ORG_SET_ERROR)
        end
      end)
    end,
  })

  job:start()
end

return M
