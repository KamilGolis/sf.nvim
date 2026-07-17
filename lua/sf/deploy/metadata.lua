local Async = require("sf.core.async")
local Config = require("sf.config")
local Const = require("sf.const")
local DeployUtils = require("sf.deploy.utils")
local Diagnostics = require("sf.core.diagnostics")
local Indexes = require("sf.core.indexes")
local Log = require("sf.core.log")
local PathUtils = require("sf.core.path_utils")
local State = require("sf.core.state")
local Utils = require("sf.core.utils")

local Metadata = {}

--- Creates a new instance of the Metadata class.
--- This function initializes a new Metadata object and sets up its metatable.
--- @return table A new instance of the Metadata class.
function Metadata:new()
  local o = {}
  setmetatable(o, self)
  self.__index = self
  return o
end

--- Deploys the currently open file to the Salesforce org.
--- Checks if the SF CLI is available and if another deployment is already running.
--- Clears previous diagnostics, creates a progress handle, and starts a job
--- to execute `sf project deploy start` for the current file.
--- Uses generated callback from DeployUtils to handle the job's completion.
--- @param force boolean|nil Whether to ignore conflicts during deployment
function Metadata:deploy_metadata(force)
  Async.async(function()
    if not DeployUtils.ensure_cli_ready() then
      return
    end

    local options = Config:get_options()
    local current_file = PathUtils.normalize(vim.fn.expand("%:p"))
    local context = DeployUtils.setup_deployment_environment("current_file", current_file, nil, options, Diagnostics)

    DeployUtils.report(context, "start")
    State.start("deploy")

    local args = Const.get_current_file_deploy_args(current_file, options.api_version, force)
    local json_output, exit_code = Async.await_system(options.sf_cli_path, args)

    DeployUtils.report(context, "checking_result")
    DeployUtils.process_deployment_result(json_output, context, exit_code)
    context.handle:finish()
    State.finish("deploy")
  end)()
end

--- Deploys changed metadata files using git delta to identify changes.
--- Validates pre-deployment conditions, sets up deployment environment,
--- and orchestrates manifest preparation followed by deployment using utility functions.
--- Uses generated callbacks for manifest preparation and deployment with standardized job creation patterns.
--- @param force boolean|nil Whether to ignore conflicts during deployment
function Metadata:deploy_changed_metadatas(force)
  Async.async(function()
    if not DeployUtils.ensure_cli_ready() then
      return
    end

    local git_ok, git_err = DeployUtils.require_git_repo()
    if not git_ok then
      Log.notify(git_err, vim.log.levels.ERROR)
      return
    end

    local changed, diff_err = Utils.get_changed_files()
    if not changed then
      Log.notify(diff_err, vim.log.levels.ERROR)
      return
    end

    local paths = DeployUtils.resolve_deploy_paths(changed)
    if #paths == 0 then
      Log.notify("No changed files to deploy", vim.log.levels.WARN)
      return
    end

    local options = Config:get_options()
    local context = DeployUtils.setup_deployment_environment("changed_files", nil, paths, options, Diagnostics)
    DeployUtils.report(context, "start")
    State.start("deploy")

    local args = Const.get_source_dir_deploy_args(paths, options.api_version, force)
    local deploy_stdout, deploy_code = Async.await_system(options.sf_cli_path, args)

    DeployUtils.report(context, "checking_result")
    DeployUtils.process_deployment_result(deploy_stdout, context, deploy_code)
    context.handle:finish()
    State.finish("deploy")
  end)()
end

--- Deploys metadata files listed in the Neovim quickfix list.
--- Uses extracted utility functions for validation, setup, and job creation.
--- Validates quickfix files, prepares them for deployment, and orchestrates
--- manifest preparation followed by deployment using standardized job creation patterns.
--- Uses generated callbacks for manifest preparation and deployment with proper error handling.
--- @param force boolean|nil Whether to ignore conflicts during deployment
function Metadata:deploy_selected_metadata(force)
  Async.async(function()
    if not DeployUtils.ensure_cli_ready() then
      return
    end

    -- Validate and process quickfix files
    local quickfix_success, found_files, missing_files, quickfix_error =
      DeployUtils.validate_quickfix_files(Indexes, Utils)

    if not quickfix_success then
      if quickfix_error then
        Log.notify(quickfix_error, vim.log.levels.WARN)
      end
      if missing_files and #missing_files > 0 then
        Log.notify("Missing indexed files: " .. table.concat(missing_files, ", "), vim.log.levels.WARN)
      end
      return
    end

    local paths = DeployUtils.resolve_deploy_paths(found_files)
    if #paths == 0 then
      Log.notify("No valid files to deploy", vim.log.levels.WARN)
      return
    end

    local options = Config:get_options()
    local context = DeployUtils.setup_deployment_environment("selected_files", nil, paths, options, Diagnostics)
    DeployUtils.report(context, "start")
    State.start("deploy")

    local args = Const.get_source_dir_deploy_args(paths, options.api_version, force)
    local deploy_stdout, deploy_code = Async.await_system(options.sf_cli_path, args)

    DeployUtils.report(context, "checking_result")
    DeployUtils.process_deployment_result(deploy_stdout, context, deploy_code)
    context.handle:finish()
    State.finish("deploy")
  end)()
end

--- Creates and returns a new instance of the Metadata class.
--- @return table: A new instance of the Metadata class.
local metadata = Metadata:new()
return metadata
