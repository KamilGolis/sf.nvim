--- sf-nvim Anonymous Apex execution module
-- @license MIT

local Config = require("sf.config")
local Connector = require("sf.org.connect")
local Const = require("sf.const")
local Diagnostics = require("sf.core.diagnostics")
local JobUtils = require("sf.core.job_utils")
local Log = require("sf.core.log")
local OrgUtils = require("sf.org.utils")
local PathUtils = require("sf.core.path_utils")
local Picker = require("sf.apex.picker")
local State = require("sf.core.state")
local Utils = require("sf.core.utils")

local Execute = {}

--- Creates a new instance of the Execute class.
--- @return table A new instance of the Execute class.
function Execute:new()
  local o = {}
  setmetatable(o, self)
  self.__index = self
  return o
end

--- Executes anonymous Apex from the given file.
--- If file_path belongs to scripts_dir, runs it directly.
--- Otherwise copies buffer content to a temp file under apex_temp_dir.
--- @param file_path string|nil Path to the .apex file. Uses current buffer if nil.
--- @param opts table|nil Options: { display_mode = "split"|"buffer" } (default "split")
function Execute:execute_file(file_path, opts)
  opts = opts or {}
  opts.display_mode = opts.display_mode or "split"

  if not file_path then
    file_path = vim.fn.expand("%:p")
  end

  if not file_path:match("%.apex$") then
    vim.notify("Not an .apex file", vim.log.levels.ERROR)
    return
  end

  Connector:check_cli(function()
    if State.is_busy("apex") then
      vim.notify("Apex execution already in progress", vim.log.levels.WARN)
      return
    end

    local cli_valid, executable_path, cli_error = JobUtils.validate_cli_installation(Config:get_options().sf_cli_path)
    if not cli_valid or not executable_path then
      vim.notify(cli_error or Const.SF_CLI_MESSAGES.NOT_FOUND, vim.log.levels.ERROR)
      return
    end

    local has_default_org, target_org, org_error = OrgUtils.check_default_org()
    if not has_default_org then
      vim.notify(org_error or Const.SF_CLI_MESSAGES.NO_DEFAULT_ORG, vim.log.levels.ERROR)
      return
    end

    Diagnostics:clear_diagnostics()

    local options = Config:get_options()
    local scripts_dir_full = PathUtils.join(Utils.get_sf_root(), options.scripts_dir) .. "/"
    local script_path = file_path
    local original_path = file_path

    -- Check if file is under scripts_dir
    if not file_path:find(scripts_dir_full, 1, true) then
      -- Copy content to temp file
      vim.fn.mkdir(options.apex_temp_dir, "p")
      local temp_file = PathUtils.join(options.apex_temp_dir, os.time() .. ".apex")
      local content_lines = {}

      -- If file exists on disk, read from it (e.g. from execute_list flow)
      if vim.fn.filereadable(file_path) == 1 then
        local f = io.open(file_path, "r")

        if f then
          local content = f:read("*a")
          f:close()
          content_lines = vim.split(content, "\n")
        end
      else
        -- Read from current buffer (for :Sf apex execute file on open buffer)
        content_lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
      end

      local temp_f = io.open(temp_file, "w")

      if temp_f then
        temp_f:write(table.concat(content_lines, "\n"))
        temp_f:close()
      end

      script_path = temp_file
    end

    local context = JobUtils.create_progress_context(
      Const.SF_CLI_MESSAGES.APEX_EXECUTE_TITLE,
      Const.SF_CLI_MESSAGES.APEX_EXECUTE_SUCCESS,
      Const.SF_CLI_MESSAGES.APEX_EXECUTE_FAILED
    )

    local args = Const.get_apex_run_args(script_path, options.api_version, target_org)

    State.start("apex")

    local job = JobUtils.create_system_job({
      command = options.sf_cli_path or "sf",
      args = args,
      on_exit = function(j, return_val)
        vim.schedule(function()
          State.finish("apex")

          if return_val == 0 then
            self:_handle_success(j, context, options, opts, original_path)
          else
            self:_handle_error(j, return_val, context, original_path)
          end
        end)
      end,
    })

    job:start()
  end)
end

--- Parse JSON response from apex run command.
--- @param json_string string Raw JSON output from CLI
--- @return table { success: boolean, logs?: string, error?: { message: string, line?: number, column?: number } }
function Execute:_parse_response(json_string)
  local ok, parsed = pcall(vim.json.decode, json_string)
  if not ok then
    return { success = false, error = { message = "Failed to parse response" } }
  end
  if parsed.name and parsed.status ~= 0 then
    local data = parsed.data or {}
    return {
      success = false,
      error = {
        message = (data.compileProblem and data.compileProblem ~= "") and data.compileProblem
          or (data.exceptionMessage and data.exceptionMessage ~= "") and data.exceptionMessage
          or parsed.message
          or "Unknown error",
        line = tonumber(data.line) or 1,
        column = tonumber(data.column) or 1,
      },
    }
  end
  if parsed.status == 0 and parsed.result and parsed.result.success then
    return { success = true, logs = parsed.result.logs or "" }
  end
  return { success = false, error = { message = "Unexpected response from apex run" } }
end
--- Handle successful apex execution response
--- @param j table The job object
--- @param context table Progress context
--- @param options table Config options
--- @param opts table Display options
function Execute:_handle_success(j, context, options, opts, original_path)
  local result = table.concat(j:result(), "\n")
  local parsed_result = self:_parse_response(result)

  if not parsed_result.success then
    local err = parsed_result.error or {}
    local source = {
      error_type = "Error",
      file_path = original_path,
      error_message = err.message or "Unknown error",
      error_line_number = err.line or 1,
      error_column_number = err.column or 1,
    }

    Diagnostics:set_diagnostics({ source })

    context.handle:report({ message = Const.SF_CLI_MESSAGES.APEX_EXECUTE_FAILED, percentage = 100 })
    context.handle:finish()
    vim.notify(source.error_message, vim.log.levels.ERROR)
    return
  end

  -- Success
  local logs = parsed_result.logs or ""
  local log_lines = vim.split(logs, "\n")

  vim.fn.mkdir(options.anonymous_log_dir, "p")

  local log_file = PathUtils.join(options.anonymous_log_dir, os.time() .. ".log")
  local f = io.open(log_file, "w")
  if f then
    f:write(table.concat(log_lines, "\n"))
    f:close()
  end

  context.handle:report({ message = context.success_message, percentage = 100 })
  context.handle:finish()
  vim.notify(Const.SF_CLI_MESSAGES.APEX_EXECUTE_SUCCESS, vim.log.levels.INFO)

  if opts.display_mode == "buffer" then
    vim.cmd("edit " .. vim.fn.fnameescape(log_file))
  else
    vim.cmd("vsplit")
    vim.cmd("edit " .. vim.fn.fnameescape(log_file))
  end
end

--- Handle error response from apex execution
--- @param j table The job object
--- @param return_val number The exit code
--- @param context table Progress context
--- @param original_path string The original .apex file path
function Execute:_handle_error(j, return_val, context, original_path)
  local stderr = j:stderr_result()
  Log.deb("Apex execute error", { return_val = return_val, stderr = stderr })

  local output = table.concat(j:result(), "\n")
  local ok, parsed = pcall(vim.json.decode, output)

  if ok and parsed.name then
    local data = parsed.data or {}
    local source = {
      error_type = "Error",
      file_path = original_path,
      error_message = data.compileProblem or data.exceptionMessage or parsed.message or "Unknown error",
      error_line_number = tonumber(data.line) or 1,
      error_column_number = tonumber(data.column) or 1,
    }

    Diagnostics:set_diagnostics({ source })

    context.handle:report({ message = Const.SF_CLI_MESSAGES.APEX_EXECUTE_FAILED, percentage = 100 })
    context.handle:finish()

    vim.notify(source.error_message, vim.log.levels.ERROR)

    return
  end

  JobUtils.handle_cli_error(return_val, context)
end

--- Creates a new empty Apex script file in the scripts directory.
--- Opens the new file in a buffer.
function Execute:execute_new()
  local options = Config:get_options()
  local dir = Utils.get_sf_root() .. "/" .. options.scripts_dir

  if vim.fn.isdirectory(dir) == 0 then
    vim.fn.mkdir(dir, "p")

    if vim.fn.isdirectory(dir) == 0 then
      vim.notify(Const.SF_CLI_MESSAGES.APEX_EXECUTE_NEW_FAILED, vim.log.levels.ERROR)
      return
    end
  end

  local path = dir .. "/" .. os.time() .. ".apex"
  local f = io.open(path, "w")

  if f then
    f:close()
  end

  vim.cmd("edit " .. vim.fn.fnameescape(path))
  vim.notify("Created: " .. path, vim.log.levels.INFO)
end

--- Cleans up temp apex files from apex_temp_dir.
function Execute:execute_cleanup()
  local dir = Config:get_options().apex_temp_dir

  if vim.fn.isdirectory(dir) == 0 then
    vim.notify("Nothing to clean up.", vim.log.levels.INFO)
    return
  end

  vim.fn.delete(dir, "rf")
  vim.fn.mkdir(dir, "p")
  vim.notify(Const.SF_CLI_MESSAGES.APEX_EXECUTE_CLEANUP_SUCCESS, vim.log.levels.INFO)
end

--- Lists apex scripts from the scripts directory and shows a picker.
--- Selecting a script executes it and shows the log in a new buffer.
function Execute:execute_list()
  local options = Config:get_options()
  local dir = Utils.get_sf_root() .. "/" .. options.scripts_dir

  if vim.fn.isdirectory(dir) == 0 then
    vim.notify(Const.SF_CLI_MESSAGES.APEX_LIST_DIR_MISSING, vim.log.levels.ERROR)
    return
  end

  local entries = vim.fn.readdir(dir)
  local files = {}

  for _, entry in ipairs(entries) do
    if entry:match("%.apex$") then
      table.insert(files, entry)
    end
  end

  if #files == 0 then
    vim.notify(Const.SF_CLI_MESSAGES.APEX_LIST_NO_SCRIPTS, vim.log.levels.WARN)
    return
  end

  local items = {}
  for _, filename in ipairs(files) do
    local file_path = PathUtils.join(dir, filename)
    local f = io.open(file_path, "r")
    local content = f and f:read("*a") or ""

    if f then
      f:close()
    end

    table.insert(items, {
      file_path = file_path,
      file_name = filename,
      content = content,
    })
  end

  Picker.create_scripts_picker(items, function(item)
    self:execute_file(item.file_path, { display_mode = "buffer" })
  end)
end

local execute = Execute:new()
return execute
