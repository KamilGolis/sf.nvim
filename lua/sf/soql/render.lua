--- sf-nvim SOQL buffer renderer — builds scratch buffer from QueryState
-- @license MIT

local Compiler = require("sf.soql.compiler")
local Const = require("sf.const")

local M = {}

--- Wrap a comma-separated string into lines that each fit `width` columns.
--- Breaks ONLY between items (at ", "), never inside an item, so field names
--- and a leading "SELECT" keyword stay intact. Continuation lines are prefixed
--- with `indent` (default ""). Returns the single input line if it already fits.
--- @param text string comma-separated items (may include a leading "SELECT ")
--- @param width integer max columns for any output line (excluding `indent`)
--- @param indent? string prefix for continuation lines
--- @return string[] wrapped lines (no trailing separators)
function M.wrap_comma_list(text, width, indent)
  indent = indent or ""

  local items = vim.split(text, ", ", { plain = true })
  local out = {}
  local cur = items[1] or ""

  for i = 2, #items do
    local candidate = cur .. ", " .. items[i]

    if #candidate > width and #cur > 0 then
      out[#out + 1] = cur
      cur = indent .. items[i]
    else
      cur = candidate
    end
  end

  out[#out + 1] = cur

  return out
end

--- Width (columns) available for content in the window showing `bufnr`.
--- Falls back to the builder window's nominal width when no window is found
--- (e.g. render runs before a window is attached).
--- @param bufnr integer
--- @return integer
local function display_width(bufnr)
  local wins = vim.fn.win_findbuf(bufnr)

  for _, w in ipairs(wins) do
    if vim.api.nvim_win_is_valid(w) then
      return vim.api.nvim_win_get_width(w)
    end
  end

  return math.min(120, vim.o.columns - 4)
end

--- Render the full buffer content from a QueryState.
--- @param state table QueryState
function M.render_lines(state)
  if not state then
    return {}
  end

  local lines = {}
  local avail_w = display_width(state.bufnr)
  local divider = string.rep("─", avail_w)
  local section_line = string.rep("╌", avail_w)

  -- Header
  if state.is_subquery then
    local parent_name = (state.parent_state and state.parent_state.sobject) or "?"
    local rel_name = state.relationship_name or "?"

    lines[#lines + 1] = " " .. Const.ICONS.TYPE .. " Subquery Builder — " .. parent_name .. " → " .. rel_name
    lines[#lines + 1] = divider
  else
    lines[#lines + 1] = divider
    lines[#lines + 1] = " " .. Const.ICONS.DATABASE .. " SOQL Builder — " .. (state.sobject or "")
    lines[#lines + 1] = divider
  end

  lines[#lines + 1] = ""

  -- SELECT
  lines[#lines + 1] = " " .. Const.ICONS.TABLE .. " SELECT"
  local fields = vim.tbl_keys(state.selected_fields)

  if #fields == 0 then
    lines[#lines + 1] = "  " .. Const.ICONS.WARNING .. " (no fields selected — 'Id' will be used)"
  else
    table.sort(fields)
    for _, f in ipairs(fields) do
      lines[#lines + 1] = "   \u{2022} " .. f
    end
  end
  -- Subqueries inline (root only, rendered under SELECT like real SOQL)
  if not state.is_subquery then
    for i, sq in ipairs(state.subqueries) do
      lines[#lines + 1] = "   \u{2022} Subquery \u{2014} " .. (sq.relationship_name or "?")
      lines[#lines + 1] = "      [e] Edit  [d] Delete  [" .. i .. "]"
    end
    lines[#lines + 1] = "    [S] Add Subquery"
  end
  lines[#lines + 1] = ""

  -- FROM
  lines[#lines + 1] = " " .. Const.ICONS.METADATA .. " FROM"

  local from_target = state.sobject
  if state.is_subquery and state.relationship_name then
    from_target = state.relationship_name
  end

  lines[#lines + 1] = "   " .. from_target

  -- WHERE
  lines[#lines + 1] = ""
  lines[#lines + 1] = " " .. Const.ICONS.FILTER .. " WHERE"

  if #state.where_clauses > 0 then
    for i, wc in ipairs(state.where_clauses) do
      local value = wc.value

      if not tonumber(value) and value ~= "true" and value ~= "false" and value ~= "null" then
        value = "'" .. value .. "'"
      end

      lines[#lines + 1] = "   " .. i .. ". " .. wc.field .. " " .. wc.op .. " " .. value
    end
  end

  lines[#lines + 1] = "  " .. Const.ICONS.FILTER .. " [AND] "

  -- ORDER BY
  lines[#lines + 1] = ""
  lines[#lines + 1] = " " .. Const.ICONS.SORT .. " ORDER BY"

  if #state.order_by > 0 then
    for _, ob in ipairs(state.order_by) do
      local clause = ob.field .. " " .. ob.direction

      if ob.nulls then
        clause = clause .. " NULLS " .. ob.nulls
      end

      lines[#lines + 1] = "   " .. clause
    end
  end

  -- LIMIT / OFFSET
  lines[#lines + 1] = ""

  local limit = "[NA]"
  local offset = "[NA]"

  if state.limit then
    limit = state.limit
  end

  if state.offset then
    offset = state.offset
  end

  lines[#lines + 1] = " " .. Const.ICONS.STOP .. " LIMIT: " .. limit
  lines[#lines + 1] = " " .. Const.ICONS.STOP .. " OFFSET: " .. offset

  -- GENERATED SOQL
  lines[#lines + 1] = ""
  lines[#lines + 1] = divider

  if state.is_subquery then
    lines[#lines + 1] = " " .. Const.ICONS.TYPE .. " Subquery"
  else
    lines[#lines + 1] = " " .. Const.ICONS.TABLE .. " SOQL Preview"
  end

  lines[#lines + 1] = divider

  local soql = Compiler.compile(state, state.is_subquery)
  local indent = "  "
  local avail = display_width(state.bufnr) - 1
  local wrapw = math.max(20, avail - #indent - 1)

  for line in vim.gsplit(soql, "\n", { plain = true }) do
    if #line <= avail or not line:find(", ") then
      lines[#lines + 1] = " " .. line
    else
      for _, wl in ipairs(M.wrap_comma_list(line, wrapw, indent)) do
        lines[#lines + 1] = " " .. wl
      end
    end
  end

  lines[#lines + 1] = divider

  return lines
end

--- Render the full buffer content from a QueryState into the buffer.
--- Writes M.render_lines(state) to the buffer.
--- @param state table QueryState
function M.render(state)
  local lines = M.render_lines(state)
  if #lines == 0 then
    return
  end

  vim.bo[state.bufnr].modifiable = true
  vim.api.nvim_buf_set_lines(state.bufnr, 0, -1, false, lines)
  vim.bo[state.bufnr].modifiable = false
end

return M
