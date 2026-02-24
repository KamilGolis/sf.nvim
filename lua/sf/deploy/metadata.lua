local PathUtils = require("sf.core.path_utils")
local Config = require("sf.config")
local Connector = require("sf.org.connect")
local Diagnostics = require("sf.core.diagnostics")
local Indexes = require("sf.core.indexes")
local Utils = require("sf.core.utils")
local DeployUtils = require("sf.deploy.utils")

local deploy_job = nil

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
  Connector:check_cli(function()
    -- Validate pre-deployment conditions
    deb("Starting Deploy Metadata function...")

    if
      not DeployUtils.handle_validation_result(
        DeployUtils.validate_deployment_preconditions(deploy_job, Connector, Utils)
      )
    then
      return
    end

    local options = Config:get_options()
    local current_file = PathUtils.normalize(vim.fn.expand("%:p"))

    -- Setup deployment environment and create context
    local context = DeployUtils.setup_deployment_environment(
      "current_file",
      current_file,
      nil,
      options,
      Diagnostics
    )

    -- Notify deployment start
    DeployUtils.notify_deployment_start(context)

    -- Create and start deployment job using utility functions with cleanup callback
    deploy_job = DeployUtils.create_current_file_deploy_job(current_file, context, {
      cleanup_callback = function()
        deploy_job = nil
      end,
    }, force)
    deploy_job:start()
  end)
end

--- Deploys changed metadata files using git delta to identify changes.
--- Validates pre-deployment conditions, sets up deployment environment,
--- and orchestrates manifest preparation followed by deployment using utility functions.
--- Uses generated callbacks for manifest preparation and deployment with standardized job creation patterns.
--- @param force boolean|nil Whether to ignore conflicts during deployment
function Metadata:deploy_changed_metadatas(force)
  deb("Starting Deploy Changed Metadata function...")

  Connector:check_cli(function()
    -- Validate pre-deployment conditions
    if
      not DeployUtils.handle_validation_result(
        DeployUtils.validate_deployment_preconditions(deploy_job, Connector, Utils)
      )
    then
      return
    end

    local options = Config:get_options()

    -- Setup deployment environment and create context
    local context =
      DeployUtils.setup_deployment_environment("changed_files", nil, nil, options, Diagnostics)

    -- Notify deployment start
    DeployUtils.notify_deployment_start(context)

    -- Create deployment job using utility functions
    deploy_job = DeployUtils.create_manifest_deploy_job(options.delta_manifest_path, context, {
      cleanup_callback = function()
        deploy_job = nil
      end,
    }, force)

    -- Create manifest preparation job using utility functions
    local prepare_manifest = DeployUtils.create_changed_files_manifest_job(context, deploy_job)

    -- Start the job sequence
    prepare_manifest:start()
  end)
end

--- Deploys metadata files listed in the Neovim quickfix list.
--- Uses extracted utility functions for validation, setup, and job creation.
--- Validates quickfix files, prepares them for deployment, and orchestrates
--- manifest preparation followed by deployment using standardized job creation patterns.
--- Uses generated callbacks for manifest preparation and deployment with proper error handling.
--- @param force boolean|nil Whether to ignore conflicts during deployment
function Metadata:deploy_selected_metadata(force)
  deb("Starting Deploy Selected Metadata function...")

  Connector:check_cli(function()
    -- Validate pre-deployment conditions
    if
      not DeployUtils.handle_validation_result(
        DeployUtils.validate_deployment_preconditions(deploy_job, Connector, Utils)
      )
    then
      return
    end

    -- Validate and process quickfix files using utility function
    local quickfix_success, found_files, missing_files, quickfix_error =
      DeployUtils.validate_quickfix_files(Config, Indexes, Utils)
    if not quickfix_success then
      DeployUtils.handle_validation_result(false, quickfix_error)
      if missing_files and #missing_files > 0 then
        vim.notify(
          "Missing indexed files: " .. table.concat(missing_files, ", "),
          vim.log.levels.WARN
        )
      end
      return
    end

    local options = Config:get_options()

    -- Setup deployment environment and create context
    local context = DeployUtils.setup_deployment_environment(
      "selected_files",
      nil,
      found_files,
      options,
      Diagnostics
    )

    -- Notify deployment start
    DeployUtils.notify_deployment_start(context)

    -- Prepare quickfix files for deployment using utility function
    local prep_success, prep_error = DeployUtils.prepare_quickfix_files_for_deployment(found_files)
    if not prep_success then
      vim.notify(prep_error, vim.log.levels.ERROR)
      context.handle:finish()
      return
    end

    -- Create deployment job using utility functions with cleanup callback
    deploy_job = DeployUtils.create_manifest_deploy_job(options.delta_manifest_path, context, {
      cleanup_callback = function()
        deploy_job = nil
      end,
    }, force)

    -- Create manifest preparation job using utility functions
    local prepare_manifest = DeployUtils.create_selected_files_manifest_job(context, deploy_job)

    -- Start the job sequence
    prepare_manifest:start()
  end)
end

--- Creates and returns a new instance of the Metadata class.
--- @return table: A new instance of the Metadata class.
local metadata = Metadata:new()
return metadata
