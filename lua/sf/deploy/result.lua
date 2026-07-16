--- Deployment result processing.
--- Handles parsing deployment JSON output, conflict detection,
--- component failure extraction, and diagnostic creation.

local Context = require("sf.deploy.context")
local Diagnostics = require("sf.core.diagnostics")
local Log = require("sf.core.log").scoped("deploy/result")

local M = {}

--- Detects if the deployment result contains a SourceConflictError
--- @param deploy_result table The parsed deployment result JSON
--- @return boolean is_conflict Whether this is a source conflict error
--- @return string|nil conflict_message The conflict message if present
function M.detect_source_conflict(deploy_result)
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
function M.process_deployment_result(json_output, context, return_val)
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

    local is_conflict, conflict_message = M.detect_source_conflict(deploy_result)

    if is_conflict then
      Context.notify(context, "conflict", "Source conflicts detected: " .. conflict_message, vim.log.levels.ERROR)
      return false
    end

    -- Check if deployment was successful
    if deploy_result.result and deploy_result.result.status == "Succeeded" and deploy_result.result.success == true then
      if context.deployment_type == "current_file" and context.current_file then
        Context.notify(
          context,
          "success",
          "File deployed successfully: " .. vim.fn.fnamemodify(context.current_file, ":t"),
          vim.log.levels.INFO
        )
      else
        Context.notify(context, "success", "Deployment successfull", vim.log.levels.INFO)
      end

      return true
    else
      -- Deployment failed - process failures and create diagnostics
      Log.deb("Deployment failed result:", deploy_result)

      if context.deployment_type == "current_file" and context.current_file then
        Context.notify(
          context,
          "failure",
          "Deployment failed for file: " .. vim.fn.fnamemodify(context.current_file, ":t"),
          vim.log.levels.ERROR
        )
      else
        Context.notify(context, "failure", "Deployment failed", vim.log.levels.ERROR)
      end

      -- Process component failures and create diagnostics
      if
        deploy_result.result
        and deploy_result.result.details
        and deploy_result.result.details.componentFailures
        and deploy_result.result.files
      then
        local diagnostic_results = M.extract_component_failures(deploy_result)
        M.create_diagnostic_entries(diagnostic_results)
      end

      return false
    end
  elseif return_val ~= 0 then
    -- CLI command failed
    if context.deployment_type == "current_file" and context.current_file then
      Context.notify(
        context,
        "failure",
        "Deployment failed for file: " .. vim.fn.fnamemodify(context.current_file, ":t"),
        vim.log.levels.ERROR
      )
    else
      Context.notify(context, "failure", "Deployment failed (status code " .. return_val .. ")", vim.log.levels.ERROR)
    end

    return false
  else
    -- JSON parsing failed
    if context.deployment_type == "current_file" and context.current_file then
      Context.notify(
        context,
        "parsing_failure",
        "Failed to parse deployment result for file: " .. vim.fn.fnamemodify(context.current_file, ":t"),
        vim.log.levels.ERROR
      )
    else
      Context.notify(context, "parsing_failure", "Failed to parse deployment result", vim.log.levels.ERROR)
    end

    return false
  end
end

--- Extracts and processes component failures from deployment result
--- @param deploy_result table The parsed deployment result JSON
--- @return table results Processed component failures ready for diagnostics
function M.extract_component_failures(deploy_result)
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
function M.create_diagnostic_entries(results)
  vim.schedule(function()
    Diagnostics:set_diagnostics(results)
  end)
end

return M
