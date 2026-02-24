local Path = require("plenary.path")

local Process = require("sf.core.process")
local Diagnostics = require("sf.core.diagnostics")
local Const = require("sf.const")

local DeployUtils = {}

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

  local handle = Process.create_progress_handle({ title = title })

  return {
    deployment_type = deployment_type,
    current_file = current_file,
    files = files,
    handle = handle,
    options = vim.tbl_deep_extend("force", {}, options), -- Create a deep copy of options
    metadata = {},
  }
end

--- Notifies the user of deployment start with consistent messaging
--- @param context DeploymentContext The deployment context
function DeployUtils.notify_deployment_start(context)
  if context.handle then
    context.handle:report({ message = "Starting deployment...", percentage = 0 })
  end
end

--- Notifies the user of successful deployment with context-aware messaging
--- @param context DeploymentContext The deployment context
function DeployUtils.notify_deployment_success(context)
  if context.handle then
    context.handle:report({ message = "Deployment successful", percentage = 100 })
  end

  vim.schedule(function()
    if context.deployment_type == "current_file" and context.current_file then
      vim.notify(
        "File deployed successfully: " .. vim.fn.fnamemodify(context.current_file, ":t"),
        vim.log.levels.INFO
      )
    else
      vim.notify("Deployment successfull", vim.log.levels.INFO)
    end
  end)
end

--- Notifies the user of deployment failure with context-aware messaging
--- @param context DeploymentContext The deployment context
--- @param error_details table|nil Optional error details for enhanced messaging
function DeployUtils.notify_deployment_failure(context, error_details)
  if context.handle then
    context.handle:report({ message = "Deployment failed", percentage = 100 })
  end

  vim.schedule(function()
    if context.deployment_type == "current_file" and context.current_file then
      vim.notify(
        "Deployment failed for file: " .. vim.fn.fnamemodify(context.current_file, ":t"),
        vim.log.levels.ERROR
      )
    else
      vim.notify("Deployment failed", vim.log.levels.ERROR)
    end
  end)
end

--- Notifies the user of CLI command failure with context-aware messaging
--- @param context DeploymentContext The deployment context
--- @param return_val number The return value from the failed command
function DeployUtils.notify_cli_failure(context, return_val)
  if context.handle then
    context.handle:report({ message = "Deployment failed", percentage = 100 })
  end

  vim.schedule(function()
    if context.deployment_type == "current_file" and context.current_file then
      vim.notify(
        "Deployment failed for file: " .. vim.fn.fnamemodify(context.current_file, ":t"),
        vim.log.levels.ERROR
      )
    else
      vim.notify("Deployment failed (status code " .. return_val .. ")", vim.log.levels.ERROR)
    end
  end)
end

--- Notifies the user of JSON parsing failure with context-aware messaging
--- @param context DeploymentContext The deployment context
function DeployUtils.notify_parsing_failure(context)
  if context.handle then
    context.handle:report({ message = "Failed to parse deployment result", percentage = 100 })
  end

  vim.schedule(function()
    if context.deployment_type == "current_file" and context.current_file then
      vim.notify(
        "Failed to parse deployment result for file: "
          .. vim.fn.fnamemodify(context.current_file, ":t"),
        vim.log.levels.ERROR
      )
    else
      vim.notify("Failed to parse deployment result", vim.log.levels.ERROR)
    end
  end)
end

--- Notifies the user of source conflict error with specific conflict details
--- @param context DeploymentContext The deployment context
--- @param conflict_message string The conflict message from SF CLI
function DeployUtils.notify_source_conflict(context, conflict_message)
  if context.handle then
    context.handle:report({ message = "Source conflicts detected", percentage = 100 })
  end

  vim.schedule(function()
    vim.notify("Source conflicts detected: " .. conflict_message, vim.log.levels.ERROR)
  end)
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

--- Creates a progress reporter with standardized messaging patterns
--- @param context DeploymentContext The deployment context
--- @return table progress_reporter Object with methods for reporting progress
function DeployUtils.create_progress_reporter(context)
  return {
    --- Reports deployment start progress
    report_start = function()
      context.handle:report({ message = "Starting deployment...", percentage = 0 })
    end,

    --- Reports manifest preparation progress
    report_manifest_preparation = function()
      context.handle:report({ message = "Preparing manifest...", percentage = 10 })
    end,

    --- Reports deployment in progress
    report_deploying = function()
      if context.deployment_type == "selected_files" then
        context.handle:report({ message = "Deploying selected files...", percentage = 50 })
      elseif context.deployment_type == "changed_files" then
        context.handle:report({ message = "Deploying...", percentage = 30 })
      else
        context.handle:report({ message = "Deploying...", percentage = 50 })
      end
    end,

    --- Reports result checking progress
    report_checking_result = function()
      context.handle:report({ message = "Checking deployment result...", percentage = 90 })
    end,

    --- Reports deployment success
    report_success = function()
      context.handle:report({ message = "Deployment successful", percentage = 100 })
    end,

    --- Reports deployment failure
    report_failure = function()
      context.handle:report({ message = "Deployment failed", percentage = 100 })
    end,

    --- Reports parsing failure
    report_parsing_failure = function()
      context.handle:report({ message = "Failed to parse deployment result", percentage = 100 })
    end,

    --- Finishes the progress handle
    finish = function()
      context.handle:finish()
    end,
  }
end

--- Notifies the user of manifest preparation success
--- @param context DeploymentContext The deployment context
function DeployUtils.notify_manifest_success(context)
  vim.schedule(function()
    vim.notify("Manifest prepared successfully", vim.log.levels.INFO)
    if context.handle then
      context.handle:report({ message = "Deploying...", percentage = 20 })
    end
  end)
end

--- Notifies the user of manifest preparation failure
--- @param context DeploymentContext The deployment context
function DeployUtils.notify_manifest_failure(context)
  vim.schedule(function()
    vim.notify("Failed to prepare manifest", vim.log.levels.ERROR)
    if context.handle then
      context.handle:finish()
    end
  end)
end

--- Notifies the user of job failure with context-aware messaging
--- @param context DeploymentContext The deployment context
--- @param job_name string The name of the failed job
function DeployUtils.notify_job_failure(context, job_name)
  vim.schedule(function()
    vim.notify("Job failed: " .. (job_name or "Unnamed Job"), vim.log.levels.ERROR)
    if context.handle then
      context.handle:finish()
    end
  end)
end

--- Processes deployment JSON result and handles success/failure scenarios
--- @param json_output string The JSON output from the deployment command
--- @param context DeploymentContext The deployment context
--- @param return_val number The return value from the job execution
--- @return boolean success Whether the deployment was successful
function DeployUtils.process_deployment_result(json_output, context, return_val)
  deb("Deployment JSON output:", json_output)
  
  local ok, deploy_result = pcall(vim.json.decode, json_output)

  -- Save the JSON output to file for debugging
  local deploy_json_path = Path:new(context.options.deploy_file)

  if not ok then
    deb("Failed to parse deployment JSON")
  else
    deb("Deployment result:", deploy_result)
  end

  if ok then
    -- Save the JSON output to file
    Path:new(context.options.cache_path):mkdir({ parents = true, exists_ok = true })
    deploy_json_path:write(json_output, "w")

    -- Check for source conflict error first
    local is_conflict, conflict_message = DeployUtils.detect_source_conflict(deploy_result)
    if is_conflict then
      DeployUtils.notify_source_conflict(context, conflict_message)
      return false
    end

    -- Check if deployment was successful
    if
      deploy_result.result
      and deploy_result.result.status == "Succeeded"
      and deploy_result.result.success == true
    then
      DeployUtils.notify_deployment_success(context)
      return true
    else
      -- Deployment failed - process failures and create diagnostics
      deb("Deployment failed result:", deploy_result)
      DeployUtils.notify_deployment_failure(context)

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
    DeployUtils.notify_cli_failure(context, return_val)
    return false
  else
    -- JSON parsing failed
    DeployUtils.notify_parsing_failure(context)
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

    results[component_failure.fullName] =
      vim.tbl_deep_extend("keep", results[component_failure.fullName], {
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

  deb("Deployment diagnostics extract: ", results)
  return results
end

--- Creates diagnostic entries from processed component failures
--- @param results table Processed component failures from extract_component_failures
function DeployUtils.create_diagnostic_entries(results)
  vim.schedule(function()
    Diagnostics:set_diagnostics(results)
  end)
end

--- Job callback generator options structure
--- @class JobCallbackOptions
--- @field context DeploymentContext The deployment context
--- @field next_job table|nil The next job to execute after success
--- @field cleanup_job table|nil The cleanup job to execute after failure
--- @field job_name string|nil The name of the job for logging purposes
--- @field success_message string|nil Custom success message
--- @field failure_message string|nil Custom failure message

--- Creates a parameterized deploy callback to replace duplicated deploy_job_callback logic
--- @param context DeploymentContext The deployment context
--- @param options table|nil Additional options for the callback
--- @return function callback The generated deploy callback function
function DeployUtils.create_deploy_callback(context, options)
  options = options or {}

  return function(j, return_val)
    local progress_reporter = DeployUtils.create_progress_reporter(context)
    progress_reporter.report_checking_result()

    local stdout = j:result()
    local json_output = table.concat(stdout, "\n")

    local success = DeployUtils.process_deployment_result(json_output, context, return_val)

    -- Cleanup and handle next job
    if options.cleanup_callback then
      options.cleanup_callback()
    end

    if options.next_job then
      options.next_job:start()
    else
      context.handle:finish()
    end
  end
end

--- Creates a job chain callback to replace duplicated run_next_job logic
--- @param context DeploymentContext The deployment context
--- @param next_job table|nil The next job to execute after success
--- @param cleanup_job table|nil The cleanup job to execute after failure
--- @param job_name string|nil The name of the job for logging purposes
--- @return function callback The generated job chain callback function
function DeployUtils.create_job_chain_callback(context, next_job, cleanup_job, job_name)
  return function(j, return_val)
    if return_val ~= 0 then
      vim.schedule(function()
        deb("Failed to run job:" .. (job_name or "Unnamed Job"), { j = j, return_val = return_val, context = context })
        DeployUtils.notify_job_failure(context, job_name)

        if cleanup_job then
          cleanup_job:start()
        end
      end)
    else
      vim.schedule(function()
        deb("Completed job:" .. (job_name or "Unnamed Job"), { j = j, return_val = return_val, context = context })

        -- Start the next job after the current one finishes
        if next_job then
          next_job:start()
        else
          -- If there's no next job, finish the handle
          if context.handle then
            context.handle:finish()
          end
        end
      end)
    end
  end
end

--- Creates a manifest preparation callback to replace duplicated prepare_manifest_callback logic
--- @param context DeploymentContext The deployment context
--- @param next_job table The next job to execute after successful manifest preparation
--- @return function callback The generated manifest preparation callback function
function DeployUtils.create_manifest_preparation_callback(context, next_job)
  return function(j, return_val)
    if return_val == 0 then
      DeployUtils.notify_manifest_success(context)
      -- Start the deployment job after manifest preparatio
      next_job:start()
    else
      vim.schedule(function()
        deb("Manifest preparation failed:", j:result())
        DeployUtils.notify_manifest_failure(context)
      end)
    end
  end
end

--- Validates pre-deployment conditions including CLI availability and running jobs
--- @param deploy_job table|nil The current deploy job to check if running
--- @param connector table The connector instance for CLI checking
--- @param utils table The utils instance for job status checking
--- @return boolean success Whether validation passed
--- @return string|nil error_message Error message if validation failed
function DeployUtils.validate_deployment_preconditions(deploy_job, connector, utils)
  -- Validate required parameters
  if not utils then
    error("utils parameter is required for deployment precondition validation")
  end

  -- Check if another deployment is already running
  if deploy_job and utils.is_job_running(deploy_job) then
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
function DeployUtils.setup_deployment_environment(
  deployment_type,
  current_file,
  files,
  options,
  diagnostics
)
  -- Clear previous diagnostics
  diagnostics:clear_diagnostics()

  -- Create deployment context with progress handle
  local context =
    DeployUtils.create_deployment_context(deployment_type, current_file, files, options)

  deb("Setup deployment context: ", context)
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
      vim.notify(
        "Could not find index entry for: " .. table.concat(missing_files, ", "),
        vim.log.levels.WARN
      )
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
  local Job = require("plenary.job")
  options = options or {}

  local progress_reporter = DeployUtils.create_progress_reporter(context)
  local callback = DeployUtils.create_deploy_callback(context, options)

  return Job:new({
    command = context.options.sf_cli_path,
    args = args,
    on_start = function(_, _)
      progress_reporter.report_deploying()
    end,
    on_exit = callback,
    on_stdout = function(_, data)
      -- Handle stdout if needed for progress reporting
      deb("Create deploy job stdout: ", data)
    end,
    on_stderr = function(_, data)
      -- Handle stderr if needed for error reporting
      deb("Create deploy job stderr: ", data)
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
  local Job = require("plenary.job")
  options = options or {}

  local progress_reporter = DeployUtils.create_progress_reporter(context)
  local callback = DeployUtils.create_manifest_preparation_callback(context, next_job)

  -- Parse command and args
  local cmd_parts = {}
  for part in command:gmatch("%S+") do
    table.insert(cmd_parts, part)
  end

  local cmd = table.remove(cmd_parts, 1)
  local args = cmd_parts

  return Job:new({
    command = cmd,
    args = args,
    on_start = function(_, _)
      progress_reporter.report_manifest_preparation()
    end,
    on_exit = callback,
  })
end

--- Creates a git operation job with standardized configuration
--- @param operation string The git operation to perform (e.g., "commit", "reset")
--- @param context DeploymentContext The deployment context
--- @param next_job table|nil The next job to execute after successful operation
--- @param cleanup_job table|nil The cleanup job to execute after failure
--- @param job_name string|nil The name of the job for logging purposes
--- @param options table|nil Additional options for job configuration
--- @return table job The created git operation job
function DeployUtils.create_git_operation_job(
  operation,
  context,
  next_job,
  cleanup_job,
  job_name,
  options
)
  local Job = require("plenary.job")
  options = options or {}

  local callback = DeployUtils.create_job_chain_callback(context, next_job, cleanup_job, job_name)

  -- Parse operation into command and args
  local cmd_parts = {}
  for part in operation:gmatch("%S+") do
    table.insert(cmd_parts, part)
  end

  local cmd = table.remove(cmd_parts, 1)
  local args = cmd_parts

  return Job:new({
    command = cmd,
    args = args,
    on_exit = callback,
  })
end

--- Extracts common job configuration patterns for standardized job creation
--- @param job_type string The type of job: "deploy", "manifest", "git"
--- @param context DeploymentContext The deployment context
--- @param options table|nil Additional configuration options
--- @return table config The standardized job configuration
function DeployUtils.extract_job_config_patterns(job_type, context, options)
  options = options or {}

  local base_config = {
    context = context,
    options = context.options,
  }

  if job_type == "deploy" then
    local deploy_args = {}
    for _, part in ipairs(vim.split(Const.SF_CLI.PROJECT.DEPLOY.CMD, " ")) do
      table.insert(deploy_args, part)
    end
    vim.list_extend(deploy_args, {
      Const.SF_CLI.PROJECT.DEPLOY.ARGS.JSON,
      Const.SF_CLI.PROJECT.DEPLOY.ARGS.API_VERSION,
      context.options.api_version,
    })

    return vim.tbl_deep_extend("force", base_config, {
      command = context.options.sf_cli_path,
      base_args = deploy_args,
      callback_generator = DeployUtils.create_deploy_callback,
      progress_reporter = DeployUtils.create_progress_reporter(context),
    })
  elseif job_type == "manifest" then
    local sgd_args = {}
    for _, part in ipairs(vim.split(Const.SF_CLI.SGD.SOURCE.DELTA.CMD, " ")) do
      table.insert(sgd_args, part)
    end
    vim.list_extend(sgd_args, {
      Const.SF_CLI.SGD.SOURCE.DELTA.ARGS.COMPARE,
      Const.SF_CLI.SGD.SOURCE.DELTA.ARGS.OUTPUT_DIR,
      context.options.delta_path,
    })

    return vim.tbl_deep_extend("force", base_config, {
      command = "sf",
      base_args = sgd_args,
      callback_generator = DeployUtils.create_manifest_preparation_callback,
      progress_reporter = DeployUtils.create_progress_reporter(context),
    })
  elseif job_type == "git" then
    return vim.tbl_deep_extend("force", base_config, {
      command = "git",
      base_args = {},
      callback_generator = DeployUtils.create_job_chain_callback,
    })
  else
    error("Unknown job type: " .. job_type)
  end
end

--- Creates a standardized deployment job for current file deployment
--- @param current_file string The path to the current file to deploy
--- @param context DeploymentContext The deployment context
--- @param options table|nil Additional options for job configuration
--- @param force boolean|nil Whether to ignore conflicts during deployment
--- @return table job The created deployment job
function DeployUtils.create_current_file_deploy_job(current_file, context, options, force)
  local args = Const.get_current_file_deploy_args(current_file, context.options.api_version, force)
  deb("Create current file deploy job args: ", args)
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
  deb("Create manidest deploy job args: ", args)
  return DeployUtils.create_deploy_job(args, context, options)
end

--- Creates a standardized manifest preparation job for changed files deployment
--- @param context DeploymentContext The deployment context
--- @param next_job table The next job to execute after successful manifest preparation
--- @param options table|nil Additional options for job configuration
--- @return table job The created manifest preparation job
function DeployUtils.create_changed_files_manifest_job(context, next_job, options)
  local Job = require("plenary.job")
  options = options or {}

  local progress_reporter = DeployUtils.create_progress_reporter(context)
  local callback = DeployUtils.create_manifest_preparation_callback(context, next_job)

  local command = Const.get_sgd_delta_command(context.options.delta_path)
  local bash_args = Const.get_bash_command_args(command)

  return Job:new({
    command = Const.SHELL.BASH.CMD,
    args = bash_args,
    on_start = function(_, _)
      progress_reporter.report_manifest_preparation()
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

--- Creates a job with standardized error handling and progress reporting
--- @param job_config table The job configuration including command, args, callbacks
--- @param context DeploymentContext The deployment context
--- @return table job The created job with standardized configuration
function DeployUtils.create_standardized_job(job_config, context)
  local Job = require("plenary.job")

  -- Ensure required fields are present
  if not job_config.command then
    error("Job configuration must include 'command' field")
  end

  -- Set default values
  job_config.args = job_config.args or {}
  job_config.on_start = job_config.on_start or function() end
  job_config.on_stdout = job_config.on_stdout or function() end
  job_config.on_stderr = job_config.on_stderr or function() end

  -- Ensure on_exit callback exists
  if not job_config.on_exit then
    error("Job configuration must include 'on_exit' callback")
  end

  return Job:new(job_config)
end

--- Validates job creation parameters to ensure consistency
--- @param job_type string The type of job being created
--- @param context DeploymentContext The deployment context
--- @param required_options table List of required option keys
--- @return boolean valid Whether the parameters are valid
--- @return string|nil error_message Error message if validation failed
function DeployUtils.validate_job_creation_params(job_type, context, required_options)
  if not job_type or type(job_type) ~= "string" then
    return false, "Job type must be a non-empty string"
  end

  if not context or type(context) ~= "table" then
    return false, "Context must be a table"
  end

  if not context.options then
    return false, "Context must include options"
  end

  if required_options then
    for _, option_key in ipairs(required_options) do
      if not context.options[option_key] then
        return false, "Missing required option: " .. option_key
      end
    end
  end

  return true, nil
end

--- Handles validation results with consistent error notification
--- @param success boolean Whether validation was successful
--- @param error_message string|nil Error message if validation failed
--- @return boolean success Whether validation passed (for easy chaining)
function DeployUtils.handle_validation_result(success, error_message)
  if not success and error_message then
    vim.notify(error_message, vim.log.levels.WARN)
    return false
  end
  return success
end

return DeployUtils
