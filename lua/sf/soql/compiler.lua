--- sf-nvim SOQL compiler — traverses QueryState tree → formatted SOQL
-- @license MIT

local M = {}

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

    for _, wc in ipairs(state.where_clauses) do
      local value = wc.value
      -- Quote string values that aren't numeric or boolean
      if not tonumber(value) and value ~= "true" and value ~= "false" and value ~= "null" then
        value = "'" .. value .. "'"
      end

      conditions[#conditions + 1] = wc.field .. " " .. wc.op .. " " .. value
    end

    lines[#lines + 1] = "WHERE " .. table.concat(conditions, " AND ")
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

  local result = table.concat(lines, "\n")

  -- Wrap subquery in parentheses
  if is_subquery then
    result = "(" .. result .. ")"
  end

  return result
end

return M
