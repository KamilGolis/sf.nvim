--- Code Analyzer scanning via sf code-analyzer run.
--- Scans the current buffer's metadata file and displays violations as inline diagnostics.
--- Uses a separate diagnostic namespace (sf.nvim.scan) so deploy diagnostics are preserved.

local Async = require("sf.core.async")
local Config = require("sf.config")
local Const = require("sf.const")
local Diagnostics = require("sf.core.diagnostics")
local Log = require("sf.core.log").scoped("code_analyzer/scan")
local PathUtils = require("sf.core.path_utils")
local Progress = require("sf.core.progress")
local State = require("sf.core.state")

local M = {}

--- Process parsed scan results: build diagnostics per file and apply them.
--- @param result table Parsed scan JSON
--- @param options table Config options
--- @return number violation_count
function M._process_results(result, options)
  local violations = result.violations or {}
  local count = #violations
  local diag_store = {}

  for _, v in ipairs(violations) do
    local idx = v.primaryLocationIndex or 0
    local loc = v.locations and v.locations[idx + 1]

    if loc then
      local file_path = PathUtils.normalize(loc.file)
      if not PathUtils.is_absolute(file_path) and result.runDir then
        file_path = PathUtils.join(result.runDir, file_path)
      end

      file_path = PathUtils.normalize(file_path)

      local msg_parts = {}

      if v.rule then
        table.insert(msg_parts, string.format("%s:", v.rule))
      end

      table.insert(msg_parts, v.message or "No message")
      table.insert(msg_parts, string.format("[sev%d]", v.severity or 0))

      if v.engine then
        table.insert(msg_parts, string.format("[%s]", v.engine))
      end

      if v.resources and #v.resources > 0 then
        table.insert(msg_parts, string.format("(%s)", v.resources[1]))
      end

      local diagnostic = {
        severity = vim.diagnostic.severity.WARN,
        message = table.concat(msg_parts, " "),
        source = "sf-code-analyzer",
        lnum = loc.startLine - 1,
        col = 0,
        end_lnum = (loc.endLine or loc.startLine) - 1,
        end_col = 65535,
      }

      if not diag_store[file_path] then
        diag_store[file_path] = {}
      end

      table.insert(diag_store[file_path], diagnostic)
    end
  end

  for file_path, diagnostics in pairs(diag_store) do
    local buf = vim.fn.bufnr(file_path, true)

    if buf ~= -1 then
      Diagnostics:apply(options.scan_namespace, buf, diagnostics)
    end
  end

  return count
end

--- Run scan CLI, read results, and apply diagnostics.
--- Core async flow shared by scan_current_file and scan_all.
--- @param args string[] CLI arguments for the scan command
--- @param progress_title string Title for the LSP progress spinner
--- @param options table Config options
function M._run_scan(args, progress_title, options)
  if State.is_busy("scan") then
    vim.notify(Const.SF_CLI_MESSAGES.SCAN_ALREADY_RUNNING, vim.log.levels.WARN)
    return
  end

  if vim.fn.isdirectory(options.scan_dir) == 0 then
    vim.fn.mkdir(options.scan_dir, "p")
  end

  Diagnostics:clear_diagnostics(options.scan_namespace)

  local handle = Progress.create_handle({ title = progress_title })
  handle:report({ message = "Running code-analyzer...", percentage = 10 })

  State.start("scan")
  local _, exit_code = Async.await_system(options.sf_cli_path, args)

  if exit_code ~= 0 then
    handle:finish()
    State.finish("scan")
    vim.notify(string.format(Const.SF_CLI_MESSAGES.SCAN_FAILED_EXIT, exit_code), vim.log.levels.ERROR)
    return
  end

  handle:report({ message = "Processing results...", percentage = 70 })

  local f = io.open(options.scan_results_file, "r")
  if not f then
    handle:finish()
    State.finish("scan")

    vim.notify(
      string.format(Const.SF_CLI_MESSAGES.SCAN_FILE_NOT_FOUND, options.scan_results_file),
      vim.log.levels.ERROR
    )

    return
  end

  local content = f:read("*a")
  f:close()

  local ok, result = pcall(vim.json.decode, content)

  if not ok or not result then
    handle:finish()
    State.finish("scan")

    vim.notify(Const.SF_CLI_MESSAGES.SCAN_JSON_PARSE_FAILED, vim.log.levels.ERROR)
    Log.deb("Scan Result JSON parsing error.")

    return
  end

  Log.deb("Scan Result JSON parsed.")
  local count = M._process_results(result, options)

  handle:finish()
  State.finish("scan")

  vim.notify(
    string.format(Const.SF_CLI_MESSAGES.SCAN_COMPLETE_FORMAT, count),
    count > 0 and vim.log.levels.WARN or vim.log.levels.INFO
  )
end

--- Scan the current buffer's file with sf code-analyzer and display violations as diagnostics.
--- @usage require("sf.code_analyzer.scan").scan_current_file()
function M.scan_current_file()
  Async.async(function()
    if not Async.await_cli_check() then
      return
    end

    local options = Config:get_options()
    local current_file = PathUtils.normalize(vim.fn.expand("%:p"))
    if current_file == "" then
      vim.notify(Const.SF_CLI_MESSAGES.SCAN_NO_FILE, vim.log.levels.WARN)
      return
    end

    local args = Const.get_code_analyzer_args(current_file, options.scan_results_file)

    M._run_scan(args, "Scanning " .. vim.fn.fnamemodify(current_file, ":t"), options)
  end)()
end

--- Scan the entire project directory with sf code-analyzer.
--- @usage require("sf.code_analyzer.scan").scan_all()
function M.scan_all()
  Async.async(function()
    if not Async.await_cli_check() then
      return
    end

    local options = Config:get_options()
    local args = Const.get_code_analyzer_all_args(options.scan_results_file)

    M._run_scan(args, "Scanning project...", options)
  end)()
end

--- Re-read cached scan results and recreate diagnostics without running the CLI.
--- @usage require("sf.code_analyzer.scan").scan_resume()
function M.scan_resume()
  local options = Config:get_options()

  if vim.fn.filereadable(options.scan_results_file) ~= 1 then
    vim.notify(Const.SF_CLI_MESSAGES.SCAN_NO_CACHED_RESULTS, vim.log.levels.WARN)
    return
  end

  local f = io.open(options.scan_results_file, "r")
  if not f then
    vim.notify(Const.SF_CLI_MESSAGES.SCAN_NO_CACHED_RESULTS, vim.log.levels.WARN)
    return
  end

  local content = f:read("*a")
  f:close()

  local ok, result = pcall(vim.json.decode, content)
  if not ok or not result then
    vim.notify(Const.SF_CLI_MESSAGES.SCAN_JSON_PARSE_FAILED, vim.log.levels.ERROR)
    return
  end

  Diagnostics:clear_diagnostics(options.scan_namespace)
  local count = M._process_results(result, options)

  vim.notify(
    string.format(Const.SF_CLI_MESSAGES.SCAN_COMPLETE_FORMAT, count),
    count > 0 and vim.log.levels.WARN or vim.log.levels.INFO
  )
end

--- Clear all scan diagnostics from every buffer.
--- @usage require("sf.code_analyzer.scan").clear()
function M.clear()
  local options = Config:get_options()
  Diagnostics:clear_diagnostics(options.scan_namespace)

  vim.notify(Const.SF_CLI_MESSAGES.SCAN_CLEARED, vim.log.levels.INFO)
end

return M
