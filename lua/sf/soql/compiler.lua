--- sf-nvim SOQL compiler — traverses QueryState tree → formatted SOQL
-- @license MIT

local M = {}

local Util = require("sf.soql.util")

--- Compile a QueryState tree into a formatted SOQL string.
--- @param state table QueryState The root state to compile
--- @param is_subquery boolean Internal flag for recursive subquery formatting
--- @return string
function M.compile(state, is_subquery)
  -- If no fields selected, fall back to "Id"
  local fields = vim.tbl_keys(state.selected_fields)
  if #fields == 0 then
    fields = { "Id" }
  end

  table.sort(fields)

  local lines = {}

  -- SELECT
  local select_line = "SELECT " .. table.concat(fields, ", ")
  -- Subqueries (inline after fields)
  if #state.subqueries > 0 then
    local sub_parts = {}

    for _, sq in ipairs(state.subqueries) do
      sub_parts[#sub_parts + 1] = M.compile(sq, true)
    end

    lines[#lines + 1] = select_line .. ", " .. table.concat(sub_parts, ", ")
  else
    lines[#lines + 1] = select_line
  end

  -- FROM
  local from_target = state.sobject
  if is_subquery or state.is_subquery then
    from_target = state.relationship_name or state.sobject
  end

  lines[#lines + 1] = "FROM " .. from_target

  -- WHERE
  if #state.where_clauses > 0 then
    local conditions = {}

    for i, wc in ipairs(state.where_clauses) do
      local value = Util.quote_value(wc.value)
      local cond = wc.field .. " " .. wc.op .. " " .. value

      if i > 1 then
        cond = (wc.connector or "AND") .. " " .. cond
      end

      conditions[#conditions + 1] = cond
    end

    lines[#lines + 1] = "WHERE " .. table.concat(conditions, " ")
  end

  -- GROUP BY
  if not vim.tbl_isempty(state.group_by) then
    local group_fields = vim.tbl_keys(state.group_by)
    table.sort(group_fields)
    lines[#lines + 1] = "GROUP BY " .. table.concat(group_fields, ", ")
  end

  -- HAVING
  if #state.having_clauses > 0 then
    local conditions = {}

    for i, hc in ipairs(state.having_clauses) do
      local value = Util.quote_value(hc.value)
      local cond = hc.field .. " " .. hc.op .. " " .. value

      if i > 1 then
        cond = (hc.connector or "AND") .. " " .. cond
      end

      conditions[#conditions + 1] = cond
    end

    lines[#lines + 1] = "HAVING " .. table.concat(conditions, " ")
  end

  -- ORDER BY
  if #state.order_by > 0 then
    local orders = {}

    for _, ob in ipairs(state.order_by) do
      local clause = ob.field .. " " .. ob.direction

      if ob.nulls then
        clause = clause .. " NULLS " .. ob.nulls
      end

      orders[#orders + 1] = clause
    end

    lines[#lines + 1] = "ORDER BY " .. table.concat(orders, ", ")
  end

  -- LIMIT
  if state.limit then
    lines[#lines + 1] = "LIMIT " .. state.limit
  end

  -- OFFSET
  if state.offset then
    lines[#lines + 1] = "OFFSET " .. state.offset
  end

  -- ALL ROWS
  if state.all_rows then
    lines[#lines + 1] = "ALL ROWS"
  end

  local result = table.concat(lines, is_subquery and " " or "\n")

  -- Wrap subquery in parentheses
  if is_subquery then
    result = "(" .. result .. ")"
  end

  return result
end

return M
