local Progress = require("sf.core.progress")

local Const = require("sf.const")
local Diagnostics = require("sf.core.diagnostics")
local Log = require("sf.core.log")
local State = require("sf.core.state")

local DeployUtils = {}

--- Progress state messages keyed by deployment phase
local PROGRESS = {
  start = { message = "Starting deployment...", percentage = 0 },
  deploying = { message = "Deploying...", percentage = 50 },
  deploying_selected = { message = "Deploying selected files...", percentage = 50 },
  deploying_changed = { message = "Deploying...", percentage = 30 },
  preparing_manifest = { message = "Preparing manifest...", percentage = 10 },
  checking_result = { message = "Checking deployment result...", percentage = 90 },
  success = { message = "Deployment successful", percentage = 100 },
  failure = { message = "Deployment failed", percentage = 100 },
  parsing_failure = { message = "Failed to parse deployment result", percentage = 100 },
  conflict = { message = "Source conflicts detected", percentage = 100 },
  manifest_success = { message = "Deploying...", percentage = 20 },
}

--- Report progress to the context handle
function DeployUtils.report(context, state)
  if context.handle and PROGRESS[state] then
    context.handle:report(PROGRESS[state])
  end
end

local function notify(context, state, msg, level)
  DeployUtils.report(context, state)

  if msg then
    vim.schedule(function()
      vim.notify(msg, level or vim.log.levels.INFO)
    end)
  end
end

--- Deployment context structure for consistent messaging across deployment methods
--- @class DeploymentContext
--- @field deployment_type string Type of deployment: "current_file", "changed_files", "selected_files"
--- @field current_file string|nil Path to current file (for single file deployments)
--- @field files table|nil List of files (for multi-file deployments)
--- @field handle table Progress handle for UI updates
--- @field options table Configuration options
--- @field metadata table|nil Additional metadata for the deployment

--- Creates a deployment context for consistent messaging and progress reporting
--- @param deployment_type string The type of deployment being performed
--- @param current_file string|nil The current file being deployed (optional)
--- @param files table|nil List of files being deployed (optional)
--- @param options table Configuration options
--- @return DeploymentContext context The deployment context
function DeployUtils.create_deployment_context(deployment_type, current_file, files, options)
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
    options = vim.tbl_deep_extend("force", {}, options), -- Create a deep copy of options
    metadata = {},
  }
end

--- Detects if the deployment result contains a SourceConflictError
--- @param deploy_result table The parsed deployment result JSON
--- @return boolean is_conflict Whether this is a source conflict error
--- @return string|nil conflict_message The conflict message if present
function DeployUtils.detect_source_conflict(deploy_result)
  -- Check if this is a SourceConflictError
  if deploy_result.name == "SourceConflictError" and deploy_result.message then
    return true, deploy_result.message
  end

  return false, nil
end

--- Processes deployment JSON result and handles success/failure scenarios
--- @param json_output string The JSON output from the deployment command
--- @param context DeploymentContext The deployment context
--- @param return_val number The return value from the job execution
--- @return boolean success Whether the deployment was successful
function DeployUtils.process_deployment_result(json_output, context, return_val)
  Log.deb("Deployment JSON output:", json_output)

  local ok, deploy_result = pcall(vim.json.decode, json_output)

  -- Save the JSON output to file for debugging
  local deploy_json_path = context.options.deploy_file

  if not ok then
    Log.deb("Failed to parse deployment JSON")
  else
    Log.deb("Deployment result:", deploy_result)
  end

  if ok then
    -- Save the JSON output to file
    vim.fn.mkdir(context.options.cache_path, "p")
    local f = io.open(deploy_json_path, "w")

    if f then
      f:write(json_output)
      f:close()
    end
    local is_conflict, conflict_message = DeployUtils.detect_source_conflict(deploy_result)

    if is_conflict then
      notify(context, "conflict", "Source conflicts detected: " .. conflict_message, vim.log.levels.ERROR)
      return false
    end

    -- Check if deployment was successful
    if deploy_result.result and deploy_result.result.status == "Succeeded" and deploy_result.result.success == true then
      if context.deployment_type == "current_file" and context.current_file then
        notify(
          context,
          "success",
          "File deployed successfully: " .. vim.fn.fnamemodify(context.current_file, ":t"),
          vim.log.levels.INFO
        )
      else
        notify(context, "success", "Deployment successfull", vim.log.levels.INFO)
      end

      return true
    else
      -- Deployment failed - process failures and create diagnostics
      Log.deb("Deployment failed result:", deploy_result)

      if context.deployment_type == "current_file" and context.current_file then
        notify(
          context,
          "failure",
          "Deployment failed for file: " .. vim.fn.fnamemodify(context.current_file, ":t"),
          vim.log.levels.ERROR
        )
      else
        notify(context, "failure", "Deployment failed", vim.log.levels.ERROR)
      end

      -- Process component failures and create diagnostics
      if
        deploy_result.result
        and deploy_result.result.details
        and deploy_result.result.details.componentFailures
        and deploy_result.result.files
      then
        local diagnostic_results = DeployUtils.extract_component_failures(deploy_result)
        DeployUtils.create_diagnostic_entries(diagnostic_results)
      end

      return false
    end
  elseif return_val ~= 0 then
    -- CLI command failed
    if context.deployment_type == "current_file" and context.current_file then
      notify(
        context,
        "failure",
        "Deployment failed for file: " .. vim.fn.fnamemodify(context.current_file, ":t"),
        vim.log.levels.ERROR
      )
    else
      notify(context, "failure", "Deployment failed (status code " .. return_val .. ")", vim.log.levels.ERROR)
    end

    return false
  else
    -- JSON parsing failed
    if context.deployment_type == "current_file" and context.current_file then
      notify(
        context,
        "parsing_failure",
        "Failed to parse deployment result for file: " .. vim.fn.fnamemodify(context.current_file, ":t"),
        vim.log.levels.ERROR
      )
    else
      notify(context, "parsing_failure", "Failed to parse deployment result", vim.log.levels.ERROR)
    end

    return false
  end
end

--- Extracts and processes component failures from deployment result
--- @param deploy_result table The parsed deployment result JSON
--- @return table results Processed component failures ready for diagnostics
function DeployUtils.extract_component_failures(deploy_result)
  local results = {}

  -- Process component failures
  for _, component_failure in ipairs(deploy_result.result.details.componentFailures) do
    if not results[component_failure.fullName] then
      results[component_failure.fullName] = {}
    end

    results[component_failure.fullName] = vim.tbl_deep_extend("keep", results[component_failure.fullName], {
      full_name = component_failure.fullName,
      file_name = component_failure.fileName,
      error_line_number = component_failure.lineNumber,
      error_column_number = component_failure.columnNumber,
      error_type = component_failure.problemType,
      component_type = component_failure.componentType,
    })
  end

  -- Process file errors
  for _, file in ipairs(deploy_result.result.files) do
    if file.error then
      results[file.fullName] = vim.tbl_deep_extend("keep", results[file.fullName], {
        file_path = file.filePath,
        error_message = file.error,
      })
    end
  end

  Log.deb("Deployment diagnostics extract: ", results)
  return results
end

--- Creates diagnostic entries from processed component failures
--- @param results table Processed component failures from extract_component_failures
function DeployUtils.create_diagnostic_entries(results)
  vim.schedule(function()
    Diagnostics:set_diagnostics(results)
  end)
end

--- Create a job callback with configurable success/failure/cleanup behavior
--- @param context table The deployment context
--- @param opts table Configuration: { on_success = fn(j, return_val), on_failure = fn(j, return_val), cleanup = fn() }
--- @return function callback The generated callback function
function DeployUtils.create_callback(context, opts)
  opts = opts or {}

  return function(j, return_val)
    vim.schedule(function()
      if return_val == 0 then
        if opts.on_success then
          opts.on_success(j, return_val)
        end
      else
        if opts.on_failure then
          opts.on_failure(j, return_val)
        end
      end
      if opts.cleanup then
        opts.cleanup()
      end
    end)
  end
end

--- Validates pre-deployment conditions including CLI availability and running jobs
--- @param deploy_job table|nil The current deploy job to check if running
--- @param connector table The connector instance for CLI checking
--- @param utils table The utils instance for job status checking
--- Validate pre-deployment conditions using state registry
--- @return boolean valid Whether pre-deployment conditions are met
--- @return string|nil error_message Error message if validation failed
function DeployUtils.validate_deployment_preconditions()
  if State.is_busy("deploy") then
    return false, "A deployment is already in progress. Please wait for it to finish."
  end

  return true, nil
end

--- Sets up the deployment environment by clearing diagnostics and preparing progress tracking
--- @param deployment_type string The type of deployment being performed
--- @param current_file string|nil The current file being deployed (optional)
--- @param files table|nil List of files being deployed (optional)
--- @param options table Configuration options
--- @param diagnostics table The diagnostics instance for clearing previous diagnostics
--- @return DeploymentContext context The prepared deployment context
function DeployUtils.setup_deployment_environment(deployment_type, current_file, files, options, diagnostics)
  -- Clear previous diagnostics
  diagnostics:clear_diagnostics()

  -- Create deployment context with progress handle
  local context = DeployUtils.create_deployment_context(deployment_type, current_file, files, options)

  Log.deb("Setup deployment context: ", context)

  return context
end

--- Validates and processes quickfix list files for selected metadata deployment
--- @param config table The config instance for debug settings
--- @param indexes table The indexes instance for file lookups
--- @param utils table The utils instance for file name extraction
--- @return boolean success Whether validation passed
--- @return table|nil found_files List of valid files found in quickfix list
--- @return table|nil missing_files List of files not found in index
--- @return string|nil error_message Error message if validation failed
function DeployUtils.validate_quickfix_files(config, indexes, utils)
  local items = vim.fn.getqflist({ items = 1 }) -- Get only the actual list items

  if #items == 0 then
    return false, nil, nil, "Quickfix list is empty"
  end

  if config:get_options().debug then
    require("snacks").debug.inspect("Quickfix List Items", items)
  end

  local indexed_files = indexes.get_file_index()
  local found = {}
  local missing_files = {}

  for _, item in ipairs(items) do
    -- Ensure item has bufnr and it's valid before proceeding
    if item.bufnr and vim.fn.bufexists(item.bufnr) == 1 then
      local file = vim.fn.bufname(item.bufnr)
      local file_name = utils.get_file_name(file)
      local full_path = indexed_files[file_name]

      if full_path and full_path ~= "" then
        -- Avoid duplicates
        if not vim.tbl_contains(found, full_path) then
          table.insert(found, full_path)
        end
      else
        if not vim.tbl_contains(missing_files, file_name) then
          table.insert(missing_files, file_name)
        end
      end
    else
      if config:get_options().debug then
        require("snacks").debug.log("Skipping invalid quickfix item", item)
      end
    end
  end

  if #found == 0 then
    local error_msg = "No valid, indexed files found in the quickfix list."

    if #missing_files > 0 then
      error_msg = error_msg .. " Missing indexed files: " .. table.concat(missing_files, ", ")
    end
    return false, nil, missing_files, error_msg
  end

  if #missing_files > 0 then
    vim.schedule(function()
      vim.notify("Could not find index entry for: " .. table.concat(missing_files, ", "), vim.log.levels.WARN)
    end)
  end

  if config:get_options().debug then
    require("snacks").debug.inspect("Found Files to Deploy", found)
    require("snacks").debug.inspect("Missing Files", missing_files)
  end

  return true, found, missing_files, nil
end

--- Prepares quickfix files for deployment by appending newlines to ensure git detects changes
--- @param files table List of file paths to prepare
--- @return boolean success Whether all files were successfully prepared
--- @return string|nil error_message Error message if preparation failed
function DeployUtils.prepare_quickfix_files_for_deployment(files)
  for _, file in ipairs(files) do
    local f = io.open(file, "a") -- Open file in append mode

    if f then
      f:write("\n") -- Write a new line at the end
      f:close() -- Close the file
    else
      return false, "Failed to open file for modification: " .. file
    end
  end

  return true, nil
end

--- Creates a standardized deployment job with consistent configuration
--- @param args table The command arguments for the deployment
--- @param context DeploymentContext The deployment context
--- @param options table|nil Additional options for job configuration
--- @return table job The created deployment job
function DeployUtils.create_deploy_job(args, context, options)
  local JobUtils = require("sf.core.job_utils")
  options = options or {}

  local function handle_deploy_result(j, return_val)
    DeployUtils.report(context, "checking_result")
    local stdout = j:result()
    local json_output = table.concat(stdout, "\n")
    DeployUtils.process_deployment_result(json_output, context, return_val)

    if options.next_job then
      options.next_job:start()
    else
      context.handle:finish()
    end
  end

  local callback = DeployUtils.create_callback(context, {
    on_success = handle_deploy_result,
    on_failure = handle_deploy_result,
    cleanup = options.cleanup_callback,
  })

  return JobUtils.create_system_job({
    command = context.options.sf_cli_path,
    args = args,
    on_start = function(_, _)
      DeployUtils.report(context, "start")
    end,
    on_exit = callback,
    on_stdout = function(_, data)
      -- Handle stdout if needed for progress reporting
      Log.deb("Create deploy job stdout: ", data)
    end,
    on_stderr = function(_, data)
      -- Handle stderr if needed for error reporting
      Log.deb("Create deploy job stderr: ", data)
    end,
  })
end

--- Creates a manifest preparation job with standardized configuration
--- @param command string The command to execute for manifest preparation
--- @param context DeploymentContext The deployment context
--- @param next_job table The next job to execute after successful manifest preparation
--- @param options table|nil Additional options for job configuration
--- @return table job The created manifest preparation job
function DeployUtils.create_manifest_job(command, context, next_job, options)
  local JobUtils = require("sf.core.job_utils")
  options = options or {}

  local callback = DeployUtils.create_callback(context, {
    on_success = function(j, return_val)
      notify(context, "manifest_success", "Manifest prepared successfully")
      next_job:start()
    end,
    on_failure = function(j, return_val)
      Log.deb("Manifest preparation failed:", j:result())
      DeployUtils.report(context, "failure")

      if context.handle then
        context.handle:finish()
      end

      vim.notify("Failed to prepare manifest", vim.log.levels.ERROR)
    end,
  })

  -- Parse command and args
  local cmd_parts = {}

  for part in command:gmatch("%S+") do
    table.insert(cmd_parts, part)
  end

  local cmd = table.remove(cmd_parts, 1)
  local args = cmd_parts

  return JobUtils.create_system_job({
    command = cmd,
    args = args,
    on_start = function(_, _)
      DeployUtils.report(context, "preparing_manifest")
    end,
    on_exit = callback,
  })
end

--- Creates a standardized deployment job for current file deployment
--- @param current_file string The path to the current file to deploy
--- @param context DeploymentContext The deployment context
--- @param options table|nil Additional options for job configuration
--- @param force boolean|nil Whether to ignore conflicts during deployment
--- @return table job The created deployment job
function DeployUtils.create_current_file_deploy_job(current_file, context, options, force)
  local args = Const.get_current_file_deploy_args(current_file, context.options.api_version, force)
  Log.deb("Create current file deploy job args: ", args)

  return DeployUtils.create_deploy_job(args, context, options)
end

--- Creates a standardized deployment job for manifest-based deployment
--- @param manifest_path string The path to the manifest file
--- @param context DeploymentContext The deployment context
--- @param options table|nil Additional options for job configuration
--- @param force boolean|nil Whether to ignore conflicts during deployment
--- @return table job The created deployment job
function DeployUtils.create_manifest_deploy_job(manifest_path, context, options, force)
  local args = Const.get_manifest_deploy_args(manifest_path, context.options.api_version, force)
  Log.deb("Create manifest deploy job args: ", args)

  return DeployUtils.create_deploy_job(args, context, options)
end

--- Creates a standardized manifest preparation job for changed files deployment
--- @param context DeploymentContext The deployment context
--- @param next_job table The next job to execute after successful manifest preparation
--- @param options table|nil Additional options for job configuration
--- @return table job The created manifest preparation job
function DeployUtils.create_changed_files_manifest_job(context, next_job, options)
  local JobUtils = require("sf.core.job_utils")
  options = options or {}

  local callback = DeployUtils.create_callback(context, {
    on_success = function(j, return_val)
      notify(context, "manifest_success", "Manifest prepared successfully")
      next_job:start()
    end,
    on_failure = function(j, return_val)
      Log.deb("Manifest preparation failed:", j:result())
      DeployUtils.report(context, "failure")
      if context.handle then
        context.handle:finish()
      end

      vim.notify("Failed to prepare manifest", vim.log.levels.ERROR)
    end,
  })

  local command = Const.get_sgd_delta_command(context.options.delta_path)
  local bash_args = Const.get_bash_command_args(command)

  return JobUtils.create_system_job({
    command = Const.SHELL.BASH.CMD,
    args = bash_args,
    on_start = function(_, _)
      DeployUtils.report(context, "preparing_manifest")
    end,
    on_exit = callback,
  })
end

--- Creates a standardized manifest preparation job for selected files deployment
--- @param context DeploymentContext The deployment context
--- @param next_job table The next job to execute after successful manifest preparation
--- @param options table|nil Additional options for job configuration
--- @return table job The created manifest preparation job
function DeployUtils.create_selected_files_manifest_job(context, next_job, options)
  local command = Const.get_sgd_delta_command(context.options.delta_path)

  return DeployUtils.create_manifest_job(command, context, next_job, options)
end

return DeployUtils
