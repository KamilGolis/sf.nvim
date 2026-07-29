--- sf-nvim SOQL shared utilities — quoting, ANSI strip, result save/open
-- @license MIT

local Config = require("sf.config")
local PathUtils = require("sf.core.path_utils")

local M = {}

--- SOQL date-literal tokens that must NOT be string-quoted.
--- @type string[]
local DATE_LITERALS = {
  "TODAY",
  "TOMORROW",
  "YESTERDAY",
  "THIS_WEEK",
  "LAST_WEEK",
  "NEXT_WEEK",
  "THIS_MONTH",
  "LAST_MONTH",
  "NEXT_MONTH",
  "THIS_QUARTER",
  "LAST_QUARTER",
  "NEXT_QUARTER",
  "THIS_YEAR",
  "LAST_YEAR",
  "NEXT_YEAR",
  "LAST_N_DAYS",
  "NEXT_N_DAYS",
  "LAST_N_DAYS_FISCAL",
  "NEXT_N_DAYS_FISCAL",
}

--- Build a lookup set for O(1) date-literal checks.
--- @type table<string, true>
local DATE_LITERAL_SET = {}

for _, lit in ipairs(DATE_LITERALS) do
  DATE_LITERAL_SET[lit] = true
end

--- Quote a SOQL WHERE value correctly for output.
--- Numeric, boolean, null, date-literal, and IN-list values are left unquoted.
--- String values are single-quoted with embedded quotes escaped.
--- @param value string
--- @return string
function M.quote_value(value)
  if value == nil or value == "" then
    return "''"
  end

  -- Numeric → unquoted
  if tonumber(value) then
    return value
  end

  -- Boolean / null literals → unquoted
  if value == "true" or value == "false" or value == "null" then
    return value
  end

  -- Date-literal pattern: YYYY-MM-DD… absolute or UPPERCASE_TOKEN[:n]
  if value:match("^%d%d%d%d%-%d%d%-%d%d") then
    return value
  end

  -- Uppercase-token date literals (e.g. LAST_N_DAYS:4)
  local leading_token = value:match("^([A-Z_][A-Z_0-9]*)")
  if leading_token and DATE_LITERAL_SET[leading_token] then
    return value
  end

  -- IN-list literal (starts with '(') → unquoted
  if value:match("^%(") then
    return value
  end

  -- String: single-quote with embedded ' escaped as \'
  return "'" .. value:gsub("'", "\\'") .. "'"
end

--- Strip ANSI SGR escape sequences (color, bold, etc.) from a string.
--- @param text string
--- @return string
function M.strip_ansi(text)
  return (text or ""):gsub("\27%[[%d;]*m", "")
end

--- Save query results and open the result file in the current window.
--- Writes <cache>/soql/results/<ts>.soql and <cache>/soql/results/<ts>.result.
--- @param opts table with keys:
---   soql       (string)  The compiled SOQL to save
---   result     (string)  The CLI output (raw, will be ANSI-stripped)
---   ts         (string?) Timestamp override; defaults to os.time()
---   result_format (string) "human" | "csv" | "json"
---   editable   (boolean?) If true, set buftype=acwrite + modifiable
--- @return string The result_file path
function M.save_and_open_result(opts)
  local config = Config:get_options()
  local results_dir = PathUtils.join(config.cache_path, "soql", "results")

  vim.fn.mkdir(results_dir, "p")

  local ts = opts.ts or tostring(os.time())
  local soql_file = PathUtils.join(results_dir, ts .. ".soql")
  local result_file = PathUtils.join(results_dir, ts .. ".result")

  -- Write .soql
  local f = io.open(soql_file, "w")
  if f then
    f:write(opts.soql or "")
    f:close()
  end

  -- Write stripped .result
  local stripped = M.strip_ansi(opts.result or "")
  f = io.open(result_file, "w")
  if f then
    f:write(stripped)
    f:close()
  end

  -- Open result file
  vim.cmd("noswapfile edit " .. vim.fn.fnameescape(result_file))

  if opts.editable then
    vim.bo.buftype = "acwrite"
    vim.bo.modifiable = true
  else
    vim.bo.modifiable = false
  end

  if opts.result_format == "csv" then
    vim.bo.filetype = "csv"
  elseif opts.result_format == "json" then
    vim.bo.filetype = "json"
  end

  return result_file
end

return M
