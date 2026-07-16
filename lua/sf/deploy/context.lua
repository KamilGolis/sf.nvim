--- Deployment context and progress reporting.
--- Manages progress handle lifecycle, deployment context objects,
--- and notification helpers for the deploy workflow.

local Log = require("sf.core.log").scoped("deploy/context")
local Progress = require("sf.core.progress")

local M = {}

--- Progress state messages keyed by deployment phase
local PROGRESS = {
  start = { message = "Starting deployment...", percentage = 0 },
  checking_result = { message = "Checking deployment result...", percentage = 90 },
  success = { message = "Deployment successful", percentage = 100 },
  failure = { message = "Deployment failed", percentage = 100 },
  parsing_failure = { message = "Failed to parse deployment result", percentage = 100 },
  conflict = { message = "Source conflicts detected", percentage = 100 },
}

--- Report progress to the context handle
--- @param context table Deployment context with a handle
--- @param state string Progress state key
function M.report(context, state)
  if context.handle and PROGRESS[state] then
    context.handle:report(PROGRESS[state])
  end
end

--- Notify with progress and a log message
--- @param context table Deployment context
--- @param state string Progress state key
--- @param msg string|nil Log message
--- @param level number|nil Log level (default INFO)
function M.notify(context, state, msg, level)
  M.report(context, state)

  if msg then
    vim.schedule(function()
      Log.notify(msg, level or vim.log.levels.INFO)
    end)
  end
end

--- @class DeploymentContext
--- @field deployment_type string "current_file" | "changed_files" | "selected_files"
--- @field current_file string|nil Path to current file
--- @field files table|nil List of files
--- @field handle table Progress handle
--- @field options table Configuration options

--- Creates a deployment context for consistent messaging and progress reporting
--- @param deployment_type string The type of deployment being performed
--- @param current_file string|nil The current file being deployed (optional)
--- @param files table|nil List of files being deployed (optional)
--- @param options table Configuration options
--- @return DeploymentContext context The deployment context
function M.create_deployment_context(deployment_type, current_file, files, options)
  -- Validate required parameters
  if not deployment_type or type(deployment_type) ~= "string" then
    error("deployment_type must be a non-empty string")
  end

  if not options or type(options) ~= "table" then
    error("options must be a table")
  end

  local title

  if deployment_type == "current_file" and current_file then
    title = vim.fn.fnamemodify(current_file, ":t")
  elseif deployment_type == "changed_files" then
    title = "Changed metadata"
  elseif deployment_type == "selected_files" then
    title = "Selected metadata"
  else
    title = "Metadata deployment"
  end

  local handle = Progress.create_handle({ title = title })

  return {
    deployment_type = deployment_type,
    current_file = current_file,
    files = files,
    handle = handle,
    options = vim.tbl_deep_extend("force", {}, options),
    metadata = {},
  }
end

--- Sets up the deployment environment by clearing diagnostics and preparing progress tracking
--- @param deployment_type string The type of deployment being performed
--- @param current_file string|nil The current file being deployed (optional)
--- @param files table|nil List of files being deployed (optional)
--- @param options table Configuration options
--- @param diagnostics table The diagnostics instance for clearing previous diagnostics
--- @return DeploymentContext context The prepared deployment context
function M.setup_deployment_environment(deployment_type, current_file, files, options, diagnostics)
  diagnostics:clear_diagnostics()
  local context = M.create_deployment_context(deployment_type, current_file, files, options)

  Log.deb("Setup deployment context: ", context)

  return context
end

return M
