--- sf-nvim log list and retrieval module
-- @license MIT

local Config = require("sf.config")
local Connector = require("sf.org.connect")
local Const = require("sf.const")
local JobUtils = require("sf.core.job_utils")
local Log = require("sf.core.log").scoped("log/list")
local OrgUtils = require("sf.org.utils")
local PathUtils = require("sf.core.path_utils")
local Picker = require("sf.log.picker")
local Utils = require("sf.log.utils")

local LogList = {}

local retrieve_selected_log

--- Display log picker with the given log items
--- @param logs table Array of log items for the picker
--- @param on_select function|nil Callback when a log is selected (receives item)
local function display_log_picker(logs, on_select)
  if not logs or #logs == 0 then
    Log.notify("No debug logs found", vim.log.levels.INFO)
    return
  end

  -- Debug: Log the number of processed logs
  Log.deb("Processing %d logs for picker", #logs)

  -- Create picker for log selection with error handling
  Picker.create_log_selection_picker(logs, function(item)
    if not item then
      Log.notify("No item selected", vim.log.levels.WARN)
      return
    end

    if on_select then
      on_select(item)
    end
  end)
end
--- Ensure a log file is available on disk for the given item.
--- Downloads the log if not already cached locally.
--- @param item table The selected picker item containing id and metadata
--- @param on_ready function(item, log_file_path) Called with the path to the local log file
function LogList.ensure_log_file(item, on_ready)
  local log_id = item.id

  if not log_id or log_id == "Unknown" then
    Log.notify("Invalid log ID", vim.log.levels.ERROR)
    return
  end

  -- Validate log ID against cached file
  local result_file = Utils.get_log_list_path()
  local file = io.open(result_file, "r")

  if not file then
    Log.notify(Const.SF_CLI_MESSAGES.LOG_NOT_IN_CACHE, vim.log.levels.WARN)
    LogList.list_logs()
    return
  end

  local content = file:read("*a")
  file:close()

  local ok, parsed = pcall(vim.json.decode, content)

  if not ok or not parsed or not parsed.result then
    Log.notify(Const.SF_CLI_MESSAGES.LOG_NOT_IN_CACHE, vim.log.levels.WARN)
    LogList.list_logs()
    return
  end

  -- Search for the selected log ID in the cached results
  local found = false

  for _, log_entry in ipairs(parsed.result) do
    if log_entry.Id == log_id then
      found = true
      break
    end
  end

  if not found then
    Log.notify(Const.SF_CLI_MESSAGES.LOG_NOT_IN_CACHE, vim.log.levels.WARN)
    LogList.list_logs()
    return
  end

  -- Proceed with log retrieval
  local log_dir = Config:get_options().log_dir
  vim.fn.mkdir(log_dir, "p")

  -- Check if log file already exists locally
  local log_file = PathUtils.join(log_dir, log_id .. ".log")

  if vim.uv.fs_stat(log_file) then
    vim.schedule(function()
      on_ready(log_file)
    end)
    return
  end

  Connector:check_cli(function()
    local has_org, _, org_error = OrgUtils.check_default_org()

    if not has_org then
      Log.notify(org_error or Const.SF_CLI_MESSAGES.NO_DEFAULT_ORG, vim.log.levels.ERROR)
      return
    end

    local cli_valid, executable_path, cli_error = JobUtils.validate_cli_installation(Config:get_options().sf_cli_path)

    if not cli_valid or not executable_path then
      Log.notify(cli_error or Const.SF_CLI_MESSAGES.NOT_FOUND, vim.log.levels.ERROR)
      return
    end

    local context = JobUtils.create_progress_context(
      Const.SF_CLI_MESSAGES.LOG_RETRIEVE_TITLE,
      Const.SF_CLI_MESSAGES.LOG_RETRIEVE_SUCCESS,
      Const.SF_CLI_MESSAGES.LOG_RETRIEVE_FAILED
    )

    local args = Const.get_apex_log_get_args(log_dir, log_id)

    local job = JobUtils.create_cli_job(executable_path, args, {
      on_success = function(job, return_val)
        context.handle:report({ message = context.success_message, percentage = 100 })
        context.handle:finish()

        -- Call on_ready with the downloaded log file (must run on main event loop)
        local log_file = PathUtils.join(log_dir, log_id .. ".log")

        vim.schedule(function()
          on_ready(log_file)
        end)
      end,
      on_error = function(job, return_val)
        local stderr = job:stderr_result()
        JobUtils.handle_cli_error(return_val, context)
      end,
    })

    job:start()
  end)
end

--- Retrieve a selected debug log and open it in a buffer.
--- @param item table The selected picker item containing id and metadata
retrieve_selected_log = function(item)
  LogList.ensure_log_file(item, function(log_file)
    vim.cmd("edit " .. vim.fn.fnameescape(log_file))
    Log.notify("Log file opened: " .. log_file, vim.log.levels.INFO)
  end)
end
function LogList.list_logs(options)
  options = options or {}
  local on_select = options.on_select or retrieve_selected_log

  -- First check if SF CLI is installed
  Connector:check_cli(function()
    -- Check if default org is set
    local has_default_org, target_org, org_error = OrgUtils.check_default_org()

    if not has_default_org then
      Log.notify(org_error or Const.SF_CLI_MESSAGES.NO_DEFAULT_ORG, vim.log.levels.ERROR)
      return
    end

    -- Validate CLI installation
    local cli_valid, executable_path, error_msg = JobUtils.validate_cli_installation(Config:get_options().sf_cli_path)

    if not cli_valid or not executable_path then
      Log.notify(error_msg or Const.SF_CLI_MESSAGES.NOT_FOUND, vim.log.levels.ERROR)
      return
    end

    -- Create progress context
    local context = JobUtils.create_progress_context(
      Const.SF_CLI_MESSAGES.LOG_LIST_TITLE,
      Const.SF_CLI_MESSAGES.LOG_LIST_SUCCESS,
      Const.SF_CLI_MESSAGES.LOG_LIST_FAILED
    )

    -- Get log list file path and ensure directory exists
    local result_file = Utils.get_log_list_path()
    local result_dir = vim.fn.fnamemodify(result_file, ":h")

    vim.fn.mkdir(result_dir, "p")

    -- Build command arguments
    local args = Const.get_apex_log_list_args(target_org)

    -- Create and start the job
    local job = JobUtils.create_cli_job(executable_path, args, {
      on_success = function(job, return_val)
        local result = table.concat(job:result(), "\n")

        Log.deb("Log list raw result:", result)

        -- Save results to file
        local file = io.open(result_file, "w")

        if file then
          file:write(result)
          file:close()
        end

        if result == "" then
          JobUtils.handle_cli_error(return_val, context, Const.SF_CLI_MESSAGES.LOG_LIST_EMPTY)
          return
        end

        -- Process log list and create picker
        local success, logs, error_message = Utils.process_log_list(result)

        if not success or not logs then
          JobUtils.handle_cli_error(return_val, context, error_message or "Failed to process log list")
          return
        end

        if #logs == 0 then
          JobUtils.handle_cli_error(return_val, context, "No logs found in response")
          return
        end

        display_log_picker(logs, on_select)

        -- Report success
        context.handle:report({ message = context.success_message, percentage = 100 })
        context.handle:finish()
      end,
      on_error = function(job, return_val)
        local stderr = job:stderr_result()
        JobUtils.handle_cli_error(return_val, context)
      end,
    })

    job:start()
  end)
end
--- Pick a log from the cached log list and call on_select with the selected item.
--- Falls back to fetching from org if no cached list exists.
--- @param on_select function(item) Called when a log is selected from the picker
function LogList.pick_cached_logs(on_select)
  local result_file = Utils.get_log_list_path()

  -- If no cached file exists, fall back to fetching from org
  local file_info = vim.uv.fs_stat(result_file)

  if not file_info then
    LogList.list_logs({ on_select = on_select })
    return
  end

  -- Read the cached file
  local file = io.open(result_file, "r")

  if not file then
    Log.notify("Cannot read cached log list file", vim.log.levels.ERROR)
    return
  end

  local result = file:read("*a")
  file:close()

  if not result or result == "" then
    Log.notify("Cached log list file is empty", vim.log.levels.WARN)
    return
  end

  -- Process the cached log list
  local success, logs, error_message = Utils.process_log_list(result)

  if not success or not logs then
    Log.notify(error_message or "Failed to processed cached log list", vim.log.levels.ERROR)
    return
  end

  if #logs == 0 then
    Log.notify("No debug logs found in cached file", vim.log.levels.WARN)
    return
  end

  display_log_picker(logs, on_select)
end

--- Display cached debug logs from the local log list file.
--- If no cached file exists, falls back to fetching from org.
function LogList.resume_logs()
  LogList.pick_cached_logs(retrieve_selected_log)
end

--- Retrieve a debug log and copy it to the DAP directory.
--- @param item table The selected picker item
local retrieve_selected_log_for_debug = function(item)
  LogList.ensure_log_file(item, function(log_file)
    vim.cmd("edit " .. vim.fn.fnameescape(log_file))
    Log.notify("Log file opened: " .. log_file, vim.log.levels.INFO)
    local Dap = require("sf.dap")
    if Dap.copy_log_for_debug(log_file) then
      Dap.launch()
    end
  end)
end

--- Display cached debug logs and copy the selected one to the DAP directory.
function LogList.debug_logs()
  LogList.pick_cached_logs(retrieve_selected_log_for_debug)
end

return LogList
