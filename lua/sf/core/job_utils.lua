local Const = require("sf.const")
local Log = require("sf.core.log")
local Progress = require("sf.core.progress")

local M = {}

--- Progress context structure for standardized progress reporting
--- @class ProgressContext
--- @field title string Progress dialog title
--- @field success_message string Message to show on success
--- @field failure_message string Message to show on failure
--- @field handle table Progress handle from Process module

--- CLI job configuration structure
--- @class CliJobConfig
--- @field command string SF CLI executable path
--- @field args table Command arguments
--- @field context ProgressContext Progress reporting context
--- @field on_success function Success callback
--- @field on_error function Error callback

--- Version information structure for SF CLI version parsing
--- @class VersionInfo
--- @field current_version string|nil The current installed version
--- @field available_version string|nil The available update version (if any)
--- @field platform string|nil The platform information
--- @field node_version string|nil The Node.js version information
--- @field has_update boolean Whether an update is available

--- Creates a standardized progress context for SF CLI operations
--- @param title string The title for the progress dialog
--- @param success_message string Message to display on successful completion
--- @param failure_message string Message to display on failure
--- @return ProgressContext The progress context with handle
--- @usage local context = JobUtils.create_progress_context("Checking CLI", "Success", "Failed")
function M.create_progress_context(title, success_message, failure_message)
  local handle = Progress.create_handle({ title = title })

  return {
    title = title,
    success_message = success_message,
    failure_message = failure_message,
    handle = handle,
  }
end

--- Creates a job using Neovim native vim.system (compat API)
--- @param config table { command: string, args: string[], on_start?: fun(), on_stdout?: fun(err: string, data: string), on_stderr?: fun(err: string, data: string), on_exit: fun(self: table, code: number) }
--- @return table { start: function, result: function, stderr_result: function }
function M.create_system_job(config)
  local self = {
    _command = config.command,
    _args = config.args or {},
    _stdout = {},
    _stderr = {},
  }

  function self.start()
    if config.on_start then
      vim.schedule(config.on_start)
    end

    local opts = { text = true }
    if config.on_stdout then
      opts.stdout = function(err, data)
        if data then
          table.insert(self._stdout, data)
        end
        config.on_stdout(err, data)
      end
    else
      opts.stdout = function(_, data)
        if data then
          table.insert(self._stdout, data)
        end
      end
    end
    if config.on_stderr then
      opts.stderr = function(err, data)
        if data then
          table.insert(self._stderr, data)
        end
        config.on_stderr(err, data)
      end
    else
      opts.stderr = function(_, data)
        if data then
          table.insert(self._stderr, data)
        end
      end
    end

    local args = { self._command }
    for _, a in ipairs(self._args) do
      table.insert(args, a)
    end

    self._sys_obj = vim.system(args, opts, function(obj)
      vim.schedule(function()
        if config.on_exit then
          config.on_exit(self, obj.code)
        end
      end)
    end)
    return self._sys_obj
  end

  function self.result()
    return vim.split(table.concat(self._stdout, "") or "", "\n")
  end

  function self.stderr_result()
    return vim.split(table.concat(self._stderr, "") or "", "\n")
  end
  return self
end

--- Creates a standardized SF CLI job with consistent error handling
--- @param command string The SF CLI executable path
--- @param args table Command arguments array
--- @param callbacks table Table containing on_success and on_error callbacks
--- @return table The created Job instance
function M.create_cli_job(command, args, callbacks)
  return M.create_system_job({
    command = command,
    args = args,
    on_exit = function(job, return_val)
      Log.deb("CLI job exit", { command = command, return_val = return_val })
      if return_val == 0 then
        if callbacks.on_success then
          callbacks.on_success(job, return_val)
        end
      else
        local stderr = job:stderr_result()
        Log.deb("CLI job error", { command = command, return_val = return_val, stderr = stderr })
        if callbacks.on_error then
          callbacks.on_error(job, return_val)
        end
      end
    end,
  })
end

--- Handles CLI result processing with standardized progress reporting
--- @param job table The Job instance that completed
--- @param return_val number The exit code from the CLI command
--- @param context ProgressContext The progress context for reporting
--- @param success_callback function|nil Optional callback to execute on success
--- @param error_callback function|nil Optional callback to execute on error
--- @usage JobUtils.handle_cli_result(job, 0, context, function() print("Success") end)
function M.handle_cli_result(job, return_val, context, success_callback, error_callback)
  if return_val == 0 then
    context.handle:report({ message = context.success_message, percentage = 100 })
    context.handle:finish()

    if success_callback then
      success_callback(job, return_val)
    end
  else
    context.handle:report({ message = context.failure_message, percentage = 100 })
    context.handle:finish()

    if error_callback then
      error_callback(job, return_val)
    end
  end
end

--- Validates SF CLI installation and returns executable path
--- @param cli_path string The configured SF CLI path
--- @return boolean success True if CLI is installed and executable
--- @return string|nil executable_path The full path to the executable, or nil if not found
--- @return string|nil error_message Error message if validation fails
--- @usage local valid, path, err = JobUtils.validate_cli_installation("sf")
function M.validate_cli_installation(cli_path)
  local executable_path = vim.fn.fnamemodify(vim.fn.exepath(cli_path), ":p")

  if executable_path == "" then
    return false, nil, Const.SF_CLI_MESSAGES.NOT_FOUND
  end

  return true, executable_path, nil
end

--- Validates and parses JSON response from SF CLI
--- @param json_string string The JSON string to parse
--- @param expected_structure table|nil Optional table describing expected structure
--- @return boolean success True if JSON is valid and matches expected structure
--- @return table|nil parsed_data The parsed JSON data, or nil if parsing failed
--- @return string|nil error_message Error message if validation fails
--- @usage local ok, data, err = JobUtils.validate_json_response('{"result": {}}', {result = "table"})
function M.validate_json_response(json_string, expected_structure)
  Log.deb("Validating JSON response...")

  if not json_string or json_string == "" then
    return false, nil, "Empty JSON response"
  end

  local ok, parsed = pcall(vim.json.decode, json_string)
  if not ok then
    Log.deb("JSON parse error:", json_string)
    return false, nil, Const.SF_CLI_MESSAGES.JSON_PARSE_ERROR
  end

  Log.deb("Parsed JSON: OK")

  -- If expected structure is provided, validate it
  if expected_structure then
    for key, expected_type in pairs(expected_structure) do
      if parsed[key] == nil then
        return false, nil, string.format("Missing required field: %s", key)
      end

      if expected_type ~= "any" and type(parsed[key]) ~= expected_type then
        return false,
          nil,
          string.format("Invalid type for field %s: expected %s, got %s", key, expected_type, type(parsed[key]))
      end
    end
  end

  return true, parsed, nil
end

--- Handles CLI errors with standardized error reporting
--- @param _ number The exit code from the CLI command (unused but kept for API consistency)
--- @param context ProgressContext The progress context for error reporting
--- @param custom_error_message string|nil Optional custom error message
--- @usage JobUtils.handle_cli_error(1, context, "Custom error occurred")
function M.handle_cli_error(_, context, custom_error_message)
  local error_message = custom_error_message or context.failure_message

  context.handle:report({ message = error_message, percentage = 100 })
  context.handle:finish()

  -- Log the error for debugging
  Log.notify(error_message, vim.log.levels.ERROR)
  Log.trace()
end

--- Notifies operation result with consistent formatting
--- @param success boolean Whether the operation was successful
--- @param context ProgressContext The progress context containing messages
--- @param details string|nil Optional additional details to include in notification
--- @usage JobUtils.notify_operation_result(true, context, "Operation completed successfully")
function M.notify_operation_result(success, context, details)
  if success then
    context.handle:report({ message = context.success_message, percentage = 100 })
    context.handle:finish()

    local message = details or context.success_message
    Log.notify(message, vim.log.levels.INFO)
  else
    context.handle:report({ message = context.failure_message, percentage = 100 })
    context.handle:finish()

    local message = details or context.failure_message
    Log.notify(message, vim.log.levels.ERROR)
  end
end

--- Parses SF CLI version information from command output
--- @param result string The raw output from SF CLI --version command
--- @return boolean success True if version information was successfully parsed
--- @return VersionInfo|nil version_info Parsed version information, or nil if parsing failed
--- @return string|nil error_message Error message if parsing fails
--- @usage local ok, info, err = JobUtils.parse_version_info("@salesforce/cli/2.15.9 darwin-x64 node-v18.17.1")
function M.parse_version_info(result)
  Log.deb("Parsing SF CLI version info:", result)

  if not result or result == "" then
    Log.deb("Empty version output")
    return false, nil, "Empty version output"
  end

  local version_info = {
    current_version = nil,
    available_version = nil,
    platform = nil,
    node_version = nil,
    has_update = false,
  }

  -- Check for update warning first
  local current, available = result:match(Const.UPDATE_WARNING_PATTERN)
  if current and available then
    version_info.current_version = current
    version_info.available_version = available
    version_info.has_update = true
  end

  -- Parse main version info using the complete pattern
  local version, platform, node = result:match(Const.VERSION_INFO_PATTERN)
  if version and platform and node then
    -- Use version from main pattern if not already found from update warning
    if not version_info.current_version then
      version_info.current_version = version
    end

    version_info.platform = platform
    version_info.node_version = node
  else
    -- If we don't have a complete version pattern and no update warning, fail
    if not version_info.current_version then
      return false, nil, "Unable to parse complete version information from SF CLI output"
    end
  end

  -- Validate that we found at least the current version
  if not version_info.current_version then
    Log.deb("Unable to parse version from output")
    return false, nil, "Unable to parse version information from SF CLI output"
  end

  Log.deb("Parsed version info:", version_info)
  return true, version_info, nil
end

--- Formats version information into a user-friendly message
--- @param version_info VersionInfo The parsed version information
--- @param executable_path string The path to the SF CLI executable
--- @return string formatted_message The formatted version message
--- @usage local message = JobUtils.format_version_message(version_info, "/usr/bin/sf")
function M.format_version_message(version_info, executable_path)
  if not version_info or not version_info.current_version then
    return Const.SF_CLI_MESSAGES.VERSION_UNKNOWN
  end

  -- Build the main version message
  local message = string.format(
    Const.SF_CLI_MESSAGES.VERSION_FOUND_FORMAT,
    executable_path,
    version_info.current_version,
    version_info.platform or "Unknown",
    version_info.node_version or "Unknown"
  )

  -- Add update information if available
  if version_info.has_update and version_info.available_version then
    message = message .. string.format(Const.SF_CLI_MESSAGES.VERSION_UPDATE_FORMAT, version_info.available_version)
  end

  return message
end

return M
