--- sf-nvim SOQL query executor — run queries and display results
-- @license MIT

local Async = require("sf.core.async")
local Compiler = require("sf.soql.compiler")
local Config = require("sf.config")
local Const = require("sf.const")
local Log = require("sf.core.log").scoped("soql/executor")
local OrgUtils = require("sf.org.utils")
local Util = require("sf.soql.util")

local M = {}

--- Bridge to run.lua for :Sf soql rerun.
local Run = require("sf.soql.run")
--- Walk to the root state from any subquery.
--- @param state table QueryState
--- @return table QueryState
local function get_root(state)
  while state.parent_state do
    state = state.parent_state
  end

  return state
end

--- Recursively collect all bufnrs from a QueryState tree.
--- @param state table QueryState
--- @return integer[]
local function collect_buffers(state)
  local bufs = { state.bufnr }

  for _, sq in ipairs(state.subqueries or {}) do
    vim.list_extend(bufs, collect_buffers(sq))
  end

  return bufs
end

--- Display raw CLI output: save .soql / .result files to disk, then
--- open the result file in current window (no split). File is editable
--- (not scratch buffer). Sets filetype based on result_format when applicable.
--- @param output string Raw stdout from sf data query
--- @param soql string|nil The compiled SOQL to save as .soql
--- @param result_format string "human" | "csv" | "json"
local function display_raw_output(output, soql, result_format)
  Util.save_and_open_result({
    soql = soql,
    result = output or "(no output)",
    result_format = result_format,
    editable = true,
  })
end

--- Execute a compiled SOQL query and display results.
--- Closes the builder buffer immediately, then runs asynchronously.
--- Uses manual progress handle for spinner, await_system for raw output.
--- @param state table QueryState
function M.run_query(state)
  local root = get_root(state)
  local soql = Compiler.compile(root)

  Run.set_last_soql(soql)
  local all_bufs = collect_buffers(root)

  for _, bufnr in ipairs(all_bufs) do
    if vim.api.nvim_buf_is_valid(bufnr) then
      local wins = vim.fn.win_findbuf(bufnr)

      for _, win in ipairs(wins) do
        if vim.api.nvim_win_is_valid(win) then
          vim.api.nvim_win_close(win, true)
        end
      end

      if vim.api.nvim_buf_is_valid(bufnr) then
        vim.api.nvim_buf_delete(bufnr, { force = true })
      end
    end
  end

  Async.async(function()
    if not Async.await_cli_check() then
      return
    end

    local has_org, target_org, org_err = OrgUtils.check_default_org()
    if not has_org then
      Log.notify(org_err or "No default org set", vim.log.levels.ERROR)
      return
    end

    local Progress = require("sf.core.progress")
    local handle = Progress.create_handle({ title = "SOQL Query" })

    handle:report({ message = "Running query...", percentage = 0 })

    local soql_config = Config:get_options().soql or {}
    local result_format = root.result_format_override or soql_config.result_format or "human"
    local args = Const.get_data_query_raw_args(soql, target_org, nil, result_format, root.use_tooling)
    local env = result_format == "human" and { COLUMNS = "100000" } or nil
    local stdout, code = Async.await_system(Config:get_options().sf_cli_path, args, env)

    vim.schedule(function()
      handle:finish()

      if code ~= 0 then
        display_raw_output(
          (stdout ~= "" and stdout or "Query failed with exit code " .. tostring(code)),
          soql,
          result_format
        )
      else
        display_raw_output(stdout or "(no output)", soql, result_format)
      end
    end)
  end)()
end

return M
