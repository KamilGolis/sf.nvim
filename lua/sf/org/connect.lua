local Config = require("sf.config")
local Const = require("sf.const")
local JobUtils = require("sf.core.job_utils")
local OrgUtils = require("sf.org.utils")

-- =============================================================================
-- CONNECT CLASS DEFINITION
-- =============================================================================

--- Connect class for managing Salesforce CLI operations and org connections
--- @class Connect
--- @field __index table The metatable index for the Connect class
local Connect = {}

--- Creates a new Connect instance
--- @return Connect A new Connect instance
--- @usage local connect = Connect:new()
function Connect:new()
  local o = {}
  setmetatable(o, self)
  self.__index = self

  return o
end

-- =============================================================================
-- PRIVATE UTILITY FUNCTIONS
-- =============================================================================

--- Check if SF CLI is installed and get version information
--- @param callback function Callback function to handle the result, receives boolean success parameter
--- @usage check_sf_cli(function(success) print("CLI check:", success) end)
--- @see Connect:check_cli For the public API method
local function check_sf_cli(callback)
  if vim.g.sf_cli_checked then
    callback(true)
    return
  end

  -- Validate CLI installation using utility function
  local cli_valid, executable_path, error_msg =
    JobUtils.validate_cli_installation(Config:get_options().sf_cli_path)
  if not cli_valid or not executable_path then
    callback(false)
    vim.notify(error_msg or Const.SF_CLI_MESSAGES.NOT_FOUND, vim.log.levels.ERROR)
    return
  end

  -- Create progress context using utility function
  local context = JobUtils.create_progress_context(
    Const.SF_CLI_MESSAGES.VERSION_CHECK_TITLE,
    Const.SF_CLI_MESSAGES.VERSION_CHECK_TITLE, -- Will be updated with actual version info
    Const.SF_CLI_MESSAGES.VERSION_CHECK_FAILED
  )

  -- Create CLI job using utility function
  local job = JobUtils.create_cli_job(executable_path, { Const.SF_CLI.VERSION.CMD }, {
    on_success = function(job, return_val)
      local result = table.concat(job:result(), "\n")

      -- Parse version information using utility function
      local parse_success, version_info, parse_error = JobUtils.parse_version_info(result)

      if parse_success and version_info then
        -- Format version message using utility function
        local message = JobUtils.format_version_message(version_info, executable_path)

        context.handle:report({ message = message, percentage = 100 })
        context.handle:finish()
        callback(true)
        vim.g.sf_cli_checked = true
      else
        JobUtils.handle_cli_error(
          return_val,
          context,
          parse_error or Const.SF_CLI_MESSAGES.VERSION_UNKNOWN
        )
        callback(false)
      end
    end,
    on_error = function(_, return_val)
      JobUtils.handle_cli_error(return_val, context)
      callback(false)
    end,
  })

  job:start()
end

-- =============================================================================
-- PUBLIC API METHODS
-- =============================================================================

--- Public method to check if SF CLI is installed and available
--- @param callback function Callback function to execute if CLI is available (no parameters)
--- @usage connect:check_cli(function() print("CLI is ready") end)
function Connect:check_cli(callback)
  -- Check if SF CLI is installed using the refactored utility function
  check_sf_cli(function(is_installed)
    if is_installed then
      callback()
    else
      -- Error notification is already handled by check_sf_cli function
      -- No need to duplicate error notification here
    end
  end)
end

--- Fetch the list of Salesforce orgs and present a picker for default org selection
--- This method will first verify CLI installation, then fetch the org list, and present
--- a picker interface for the user to select their default org
--- @usage connect:select_default_org()
function Connect:select_default_org()
  -- First, check if SF CLI is installed
  check_sf_cli(function(_)
    -- Validate CLI installation using utility function
    local cli_valid, executable_path, error_msg =
      JobUtils.validate_cli_installation(Config:get_options().sf_cli_path)
    if not cli_valid or not executable_path then
      vim.notify(error_msg or Const.SF_CLI_MESSAGES.NOT_FOUND, vim.log.levels.ERROR)
      return
    end

    -- Create progress context using utility function
    local context = JobUtils.create_progress_context(
      Const.SF_CLI_MESSAGES.ORG_LIST_TITLE,
      Const.SF_CLI_MESSAGES.ORG_LIST_SUCCESS,
      Const.SF_CLI_MESSAGES.ORG_LIST_FAILED
    )

    -- Create CLI job using utility function
    local args = vim.split(Const.SF_CLI.ORG.LIST.CMD, " ")
    table.insert(args, Const.SF_CLI.ORG.LIST.ARGS.JSON)
    local job = JobUtils.create_cli_job(executable_path, args, {
      on_success = function(job, return_val)
        local result = table.concat(job:result(), "\n")

        if result == "" then
          JobUtils.handle_cli_error(return_val, context, Const.SF_CLI_MESSAGES.ORG_LIST_EMPTY)
          return
        end

        -- Use new JSON validation and org processing utilities
        local success, orgs, error_message = OrgUtils.process_org_list(result)
        if not success or not orgs then
          JobUtils.handle_cli_error(return_val, context, error_message)
          return
        end

        -- Use standardized picker creation function
        OrgUtils.create_org_selection_picker(orgs, function(item)
          -- Use new target org setting utility with progress reporting
          OrgUtils.set_target_org(item.org_data)
        end)

        -- Report success
        context.handle:report({ message = context.success_message, percentage = 100 })
        context.handle:finish()
      end,
      on_error = function(_, return_val)
        JobUtils.handle_cli_error(return_val, context)
      end,
    })

    job:start()
  end)
end

-- =============================================================================
-- MODULE EXPORT
-- =============================================================================

--- Create and return a singleton Connect instance for org connection operations
--- @type Connect
local connect = Connect:new()
return connect
