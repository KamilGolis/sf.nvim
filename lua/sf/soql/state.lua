--- sf-nvim SOQL state engine — QueryState and clause constructors
-- @license MIT

local Const = require("sf.const")

local M = {}

--- @class WhereCondition
--- @field field string
--- @field op string
--- @field value string
function M.new_where_condition(field, op, value)
  return { field = field, op = op, value = value }
end

--- @class OrderByClause
--- @field field string
--- @field direction string "ASC" | "DESC"
--- @field nulls string|nil "FIRST" | "LAST"
function M.new_order_by_clause(field, direction, nulls)
  return { field = field, direction = direction, nulls = nulls }
end

--- @class QueryState
--- @field bufnr integer
--- @field is_subquery boolean
--- @field parent_state QueryState|nil
--- @field relationship_name string|nil
--- @field sobject string
--- @field selected_fields table<string, boolean>
--- @field subqueries QueryState[]
--- @field where_clauses WhereCondition[]
--- @field order_by OrderByClause[]
--- @field limit integer|nil
--- @field offset integer|nil
local QueryState = {}
QueryState.__index = QueryState

function QueryState:new(opts)
  opts = opts or {}
  local o = {
    bufnr = opts.bufnr,
    is_subquery = opts.is_subquery or false,
    parent_state = opts.parent_state or nil,
    relationship_name = opts.relationship_name or nil,
    sobject = opts.sobject or "",
    selected_fields = {},
    subqueries = {},
    where_clauses = {},
    order_by = {},
    limit = opts.limit or nil,
    subquery_saved = false,
    offset = opts.offset or nil,
  }

  setmetatable(o, self)

  -- Pre-populate system fields
  for _, f in ipairs(Const.SOQL.SYSTEM_FIELDS) do
    o.selected_fields[f] = true
  end

  return o
end

--- Parse a comma-separated field string and add any not-yet-selected fields to
--- state.selected_fields. Additive only: never removes, tolerates surrounding
--- whitespace and fields split across lines. Empty tokens are skipped; existing
--- fields are left untouched (idempotent).
--- @param state table QueryState
--- @param raw string comma-separated field list (may span multiple lines)
function M.merge_fields_from_string(state, raw)
  local lines = vim.split(raw, "\n")
  local joined = table.concat(lines, ", ")

  for token in vim.gsplit(joined, ",", { plain = true }) do
    local field = vim.trim(token)

    if field ~= "" and not state.selected_fields[field] then
      state.selected_fields[field] = true
    end
  end
end

--- Remove the given field names from state.selected_fields, skipping SYSTEM_FIELDS
--- (must stay so the compiled query remains valid). Absent names are ignored.
--- @param state table QueryState
--- @param fields string[] field API names to remove
--- @return integer number of fields actually removed
function M.remove_fields(state, fields)
  local removed = 0

  for _, f in ipairs(fields) do
    if state.selected_fields[f] and not vim.tbl_contains(Const.SOQL.SYSTEM_FIELDS, f) then
      state.selected_fields[f] = nil
      removed = removed + 1
    end
  end

  return removed
end

M.QueryState = QueryState

return M
