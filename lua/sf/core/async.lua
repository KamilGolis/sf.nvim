--- Coroutine-based async/await engine for sf.nvim CLI operations.
---
--- Replaces callback chains with sequential coroutine code.
--- Three core primitives:
---   - async(fn)     — wraps a function body in a coroutine
---   - await_system  — yields until vim.system finishes
---   - await_json    — yields + parses JSON stdout
---
--- Convenience helpers:
---   - await_sf        — wraps progress.lua's sf_execute in a coroutine
---   - await_cli_check — verifies SF CLI is installed (cached)

local Config = require("sf.config")
local Const = require("sf.const")
local Log = require("sf.core.log")

local M = {}

--- Wraps a function in a coroutine so it can yield and resume.
--- Errors inside the coroutine are surfaced via vim.notify(ERROR).
---
--- @param fn function The function body (may call await_* primitives)
--- @return function An invocable function that starts the coroutine
--- @usage local task = async.async(function() local r = await_json(...) end); task()
function M.async(fn)
  return function(...)
    local co = coroutine.create(fn)
    local function step(...)
      local ok, err = coroutine.resume(co, ...)
      if not ok then
        vim.notify("Async Crash: " .. tostring(err), vim.log.levels.ERROR)
      end
    end
    step(...)
  end
end

--- Yields the current coroutine until vim.system completes.
--- Returns the full stdout string and exit code.
---
--- @param command string The executable path (e.g. Config:get_options().sf_cli_path)
--- @param args string[] Command arguments
--- @return string stdout The full stdout output
--- @return integer exit_code The process exit code
function M.await_system(command, args)
  local co = coroutine.running()
  assert(co, "await_system must be called inside an M.async block!")

  local cmd = { command }
  for _, a in ipairs(args) do
    table.insert(cmd, a)
  end

  vim.system(cmd, { text = true }, function(obj)
    vim.schedule(function()
      local stdout
      if type(obj.stdout) == "string" then
        -- Real vim.system API: result object with .stdout property
        stdout = obj.stdout
      elseif type(obj.result) == "function" then
        -- Mock API: use :result() which returns a lines table
        local lines = obj:result()
        stdout = type(lines) == "table" and table.concat(lines, "\n") or ""
      else
        stdout = ""
      end
      coroutine.resume(co, stdout, obj.code)
    end)
  end)

  return coroutine.yield()
end

--- Awaits a CLI command and parses its JSON output.
---
--- @param command string The executable path
--- @param args string[] Command arguments
--- @return table|nil data Parsed JSON table, or nil on failure
--- @return string|nil error_message Error message if command or parsing failed
function M.await_json(command, args)
  local stdout, code = M.await_system(command, args)

  if code ~= 0 then
    local err_msg = stdout ~= "" and stdout or "Command failed with exit code " .. tostring(code)
    return nil, err_msg
  end

  local ok, parsed = pcall(vim.json.decode, stdout)
  if not ok then
    return nil, "Failed to parse JSON output"
  end

  return parsed, nil
end

--- Runs an sf CLI command with an LSP progress spinner via coroutine.
--- Bridges the callback-based Progress.sf_execute into a coroutine yield.
---
--- @param args string[] CLI arguments to pass after "sf"
--- @param title string Label for the LSP progress spinner
---
--- @return table|nil parsed Parsed JSON data, or nil on failure
--- @return string|nil err Error message if command or parsing failed
--- @return string|nil raw_stdout The raw stdout from the CLI command
function M.await_sf(args, title)
  local co = coroutine.running()
  assert(co, "await_sf must be called inside an M.async block!")

  local Progress = require("sf.core.progress")
  Progress.sf_execute(args, title, {
    on_complete = function(parsed, err, raw_stdout)
      coroutine.resume(co, parsed, err, raw_stdout)
    end,
  })

  return coroutine.yield()
end

--- Checks if SF CLI is installed and available.
--- Caches the result in vim.g.sf_cli_checked so subsequent calls are instant.
---
--- @return boolean success True if CLI is available
function M.await_cli_check()
  if vim.g.sf_cli_checked then
    return true
  end

  local JobUtils = require("sf.core.job_utils")
  local cli_valid, executable_path, error_msg = JobUtils.validate_cli_installation(Config:get_options().sf_cli_path)

  if not cli_valid or not executable_path then
    Log.notify(error_msg or Const.SF_CLI_MESSAGES.CLI_NOT_INSTALLED, vim.log.levels.ERROR)
    return false
  end

  local _, code = M.await_system(executable_path, { "--version" })
  if code ~= 0 then
    Log.notify(Const.SF_CLI_MESSAGES.CLI_CHECK_FAILED, vim.log.levels.ERROR)
    return false
  end

  vim.g.sf_cli_checked = true
  return true
end

return M
