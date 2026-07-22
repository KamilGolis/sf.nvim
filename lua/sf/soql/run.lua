--- sf-nvim SOQL quick-run — scratch buffer editor to write + execute queries
-- @license MIT

local Async = require("sf.core.async")
local Config = require("sf.config")
local Const = require("sf.const")
local OrgUtils = require("sf.org.utils")
local PathUtils = require("sf.core.path_utils")

local snacks_ok, Snacks = pcall(require, "snacks")

if not snacks_ok then
  Snacks = nil
end

local M = {}

--- Last compiled or entered SOQL string, for rerun.
local last_soql = nil

--- Write results and SOQL source to disk under cache_path/soql/results/<ts>.*
--- @param soql string
--- @param result string
--- @param ts string|nil Timestamp to reuse (for editor pre-created file)
--- @return { soql_file: string, result_file: string }
local function save_results(soql, result, ts)
  local config = Config:get_options()
  local results_dir = PathUtils.join(config.cache_path, "soql", "results")

  vim.fn.mkdir(results_dir, "p")

  ts = ts or tostring(os.time())
  local soql_file = PathUtils.join(results_dir, ts .. ".soql")
  local result_file = PathUtils.join(results_dir, ts .. ".result")

  local stripped = (result or ""):gsub("\27%[[%d;]*m", "")

  local f = io.open(soql_file, "w")
  if f then
    f:write(soql)
    f:close()
  end

  f = io.open(result_file, "w")
  if f then
    f:write(stripped)
    f:close()
  end

  return { soql_file = soql_file, result_file = result_file }
end

--- Open a result file in current window (no split).
--- @param result_file string
--- @param result_format string "human" | "csv" | "json"
local function open_result_file(result_file, result_format)
  local escaped = vim.fn.fnameescape(result_file)
  vim.cmd("edit " .. escaped)

  vim.bo.filetype = result_format

  vim.bo.modifiable = false
end

--- Open a scratch-buffer editor, execute the query on <CR>, show results.
function M.run()
  if not Snacks then
    vim.notify(Const.SOQL.MESSAGES.SNACKS_REQUIRED_BUILDER, vim.log.levels.ERROR)
    return
  end

  -- Pre-create timestamped .soql file in project results dir so LSP attaches.
  -- The file is empty initially; execute_query overwrites it with the query text.
  local results_dir = PathUtils.join(Config:get_options().cache_path, "soql", "results")
  vim.fn.mkdir(results_dir, "p")
  local ts = tostring(os.time())
  local scratch_file = PathUtils.join(results_dir, ts .. ".soql")
  local f = io.open(scratch_file, "w")

  if f then
    f:close()
  end

  local execute_query

  execute_query = function(self)
    local soql = vim.trim(self:text())

    if soql == "" then
      vim.notify("Query is empty", vim.log.levels.WARN)
      return
    end

    self:close()
    last_soql = soql

    Async.async(function()
      if not Async.await_cli_check() then
        return
      end

      local has_org, target_org, org_err = OrgUtils.check_default_org()
      if not has_org then
        vim.notify(org_err or "No default org set", vim.log.levels.ERROR)
        return
      end

      local Progress = require("sf.core.progress")
      local handle = Progress.create_handle({ title = "SOQL Query" })
      handle:report({ message = "Running query...", percentage = 0 })

      local sf_cli = Config:get_options().sf_cli_path
      local result_format = (Config:get_options().soql or {}).result_format or "human"
      local args = Const.get_data_query_raw_args(soql, target_org, nil, result_format)
      local env = result_format == "human" and { COLUMNS = "100000" } or nil
      local stdout, code = Async.await_system(sf_cli, args, env)

      vim.schedule(function()
        handle:finish()

        local result
        if stdout ~= "" then
          result = stdout
        else
          result = "(no output)"
        end

        if code ~= 0 then
          result = "Query failed with exit code " .. tostring(code) .. "\n\n" .. result
        end

        local files = save_results(soql, result, ts)
        open_result_file(files.result_file, result_format)
      end)
    end)()
  end

  Snacks.win({
    title = " SOQL Run ",
    position = "float",
    border = "single",
    width = math.min(120, vim.o.columns - 4),
    height = math.max(math.floor(vim.o.lines * 0.5), 20),
    file = scratch_file,
    enter = true,
    actions = {
      execute_query = {
        action = execute_query,
        desc = "Execute query",
      },
    },
    keys = {
      q = "close",
      ["?"] = "toggle_help",
      ["<CR>"] = { "<CR>", "execute_query", mode = "n", desc = "Execute query" },
    },
    footer_keys = { "q", "?", "<CR>" },
    on_win = function(self)
      vim.bo[self.buf].modifiable = true
    end,
  })
end

--- Re-run the last compiled/entered SOQL query.
function M.run_last()
  if not last_soql then
    vim.notify(Const.SOQL.MESSAGES.NO_PREV_QUERY, vim.log.levels.WARN)
    return
  end

  Async.async(function()
    if not Async.await_cli_check() then
      return
    end

    local has_org, target_org, org_err = OrgUtils.check_default_org()
    if not has_org then
      vim.notify(org_err or "No default org set", vim.log.levels.ERROR)
      return
    end

    local Progress = require("sf.core.progress")
    local handle = Progress.create_handle({ title = "SOQL Rerun" })

    handle:report({ message = "Running query...", percentage = 0 })

    local sf_cli = Config:get_options().sf_cli_path
    local result_format = (Config:get_options().soql or {}).result_format or "human"
    local args = Const.get_data_query_raw_args(last_soql, target_org, nil, result_format)
    local env = result_format == "human" and { COLUMNS = "100000" } or nil
    local stdout, code = Async.await_system(sf_cli, args, env)

    vim.schedule(function()
      handle:finish()

      local result
      if stdout ~= "" then
        result = stdout
      else
        result = "(no output)"
      end

      if code ~= 0 then
        result = "Query failed with exit code " .. tostring(code) .. "\n\n" .. result
      end

      local files = save_results(last_soql, result)
      open_result_file(files.result_file, result_format)
    end)
  end)()
end

--- Bridge for executor to record last compiled SOQL from the builder.
--- @param soql string
function M.set_last_soql(soql)
  last_soql = soql
end

return M
