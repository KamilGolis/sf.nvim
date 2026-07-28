--- sf-nvim SOQL parser — reconstructs QueryState from compiled SOQL text
-- @license MIT

local M = {}

--- Split a SOQL string into individual lines, stripping surrounding whitespace.
--- Handles both single-line and multi-line formats produced by the compiler.
--- @param raw string
--- @return string[]
local function split_lines(raw)
  if not raw or raw == "" then
    return {}
  end

  -- Normalize line endings
  raw = raw:gsub("\r\n", "\n")

  -- For single-line SOQL, split on keywords instead
  -- Heuristic: if there's no newline, the whole query is on one line
  if not raw:find("\n") then
    -- Single-line: return as-is (normalize_multiline handles splitting)
    return { raw }
  end

  local lines = {}
  for line in vim.gsplit(raw, "\n", { plain = true }) do
    line = line:match("^%s*(.-)%s*$") or ""

    if line ~= "" then
      lines[#lines + 1] = line
    end
  end

  return lines
end

--- Try to detect and handle single-line SOQL by inserting newlines before clauses.
--- @param raw string
--- @return string
local function normalize_multiline(raw)
  if raw:find("\n") then
    return raw
  end

  -- Insert newlines before FROM, WHERE, ORDER BY, LIMIT, OFFSET
  -- but NOT before subquery SELECTs (those are parenthesized)
  local result = raw
  result = result:gsub("%s+FROM%s+", "\nFROM ")
  result = result:gsub("%s+WHERE%s+", "\nWHERE ")
  result = result:gsub("%s+ORDER%s+BY%s+", "\nORDER BY ")
  result = result:gsub("%s+LIMIT%s+", "\nLIMIT ")
  result = result:gsub("%s+OFFSET%s+", "\nOFFSET ")
  result = result:gsub("%s+GROUP%s+BY%s+", "\nGROUP BY ")
  result = result:gsub("%s+HAVING%s+", "\nHAVING ")
  result = result:gsub("%s+ALL%s+ROWS%s*$", "\nALL ROWS")

  return result
end

--- Parse a SELECT clause line, extracting field names and inline subquery text.
--- Returns { fields = string[], subquery_texts = string[] }
--- @param line string e.g. "SELECT Id, Name, (SELECT ... FROM ...)"
--- @return table
local function parse_select(line)
  -- Strip the "SELECT " prefix
  local rest = line:match("^SELECT%s+(.*)$")
  if not rest then
    return { fields = {}, subquery_texts = {} }
  end

  local fields = {}
  local subquery_texts = {}
  local current = ""

  -- Parse token by token, tracking parentheses for subqueries
  local paren_depth = 0
  local in_subquery = false

  -- Process character by character to handle nested parens
  for i = 1, #rest do
    local ch = rest:sub(i, i)

    if ch == "(" then
      paren_depth = paren_depth + 1

      if paren_depth == 1 then
        local func_name = current:match("^%s*(%a+)%s*$")
        local AGG_FUNCS = { COUNT = true, SUM = true, MAX = true, MIN = true, AVG = true }

        if not (func_name and AGG_FUNCS[func_name:upper()]) then
          in_subquery = true
        end
      end
      current = current .. ch
    elseif ch == ")" then
      paren_depth = paren_depth - 1
      current = current .. ch

      if paren_depth == 0 and in_subquery then
        -- End of subquery — trim leading whitespace so parse_subquery works
        current = current:match("^%s*(.-)%s*$") or current
        table.insert(subquery_texts, current)
        current = ""
        in_subquery = false
      end
    elseif ch == "," and paren_depth == 0 then
      -- Comma at top level = field separator
      local field = current:match("^%s*(.-)%s*$") or ""
      if field ~= "" then
        table.insert(fields, field)
      end
      current = ""
    else
      current = current .. ch
    end
  end

  -- Don't forget the last field
  if current ~= "" then
    local field = current:match("^%s*(.-)%s*$") or ""
    if field ~= "" then
      table.insert(fields, field)
    end
  end

  return { fields = fields, subquery_texts = subquery_texts }
end

--- Parse a subquery text (without the outer parens) into its parts.
--- @param text string e.g. "(SELECT Id FROM Contacts)"
--- @return table|nil parsed subquery data
local function parse_subquery(text)
  -- Strip outer parentheses if present
  local inner = text:match("^%((.*)%)$")
  if not inner then
    return nil
  end

  -- Parse the inner SOQL recursively
  return M.parse(inner)
end

--- Parse a condition string into individual clauses with connectors.
--- Splits on " AND " and " OR " while tracking the connector for each condition.
--- Reused by both parse_where and parse_having.
--- @param text string The text after the WHERE/HAVING keyword
--- @return table[] clauses with field, op, value, and connector fields
local function parse_conditions(text)
  local clauses = {}

  -- Split on " AND " and " OR " manually, tracking connectors.
  local parts = {}
  local current = ""
  local pos = 1
  local connectors = {}

  while pos <= #text do
    local and_match = text:sub(pos):match("^%s+AND%s+")
    local or_match = text:sub(pos):match("^%s+OR%s+")

    if and_match then
      table.insert(parts, current)
      table.insert(connectors, "AND")
      current = ""
      pos = pos + #and_match
    elseif or_match then
      table.insert(parts, current)
      table.insert(connectors, "OR")
      current = ""
      pos = pos + #or_match
    else
      current = current .. text:sub(pos, pos)
      pos = pos + 1
    end
  end

  if current ~= "" then
    table.insert(parts, current)
    table.insert(connectors, nil)
  end

  -- Parse each part as a field op value.
  for ci, cond in ipairs(parts) do
    local field = cond:match("^%s*([%w_().]+)%s+(.*)$")

    if field then
      local cond_rest = cond:match("^%s*" .. field .. "%s+(.*)$")

      if cond_rest then
        local ops = { "NOT%s+IN", "<=", ">=", "<>", "!=", "=", "<", ">", "LIKE", "IN", "INCLUDES", "EXCLUDES" }
        local matched_op, value

        for _, op_pattern in ipairs(ops) do
          local v = cond_rest:match("^" .. op_pattern .. "%s+(.+)$")

          if v then
            matched_op = cond_rest:match("^(" .. op_pattern .. ")")
            value = v
            break
          end
        end

        if matched_op and value then
          value = value:match("^'(.*)'$") or value
          table.insert(clauses, { field = field, op = matched_op, value = value, connector = connectors[ci] })
        end
      end
    end
  end

  return clauses
end

--- Parse a WHERE clause line into individual conditions.
--- @param line string e.g. "WHERE Name = 'Test' AND Industry != 'Technology'"
--- @return table[] where_clauses
local function parse_where(line)
  local rest = line:match("^WHERE%s+(.*)$")
  if not rest then
    return {}
  end
  return parse_conditions(rest)
end

--- Parse a GROUP BY clause line into a field set.
--- @param line string e.g. "GROUP BY Industry, Type"
--- @return table<string, boolean>
local function parse_group_by(line)
  local rest = line:match("^GROUP%s+BY%s+(.*)$")
  if not rest then
    return {}
  end
  local fields = {}
  for token in vim.gsplit(rest, ",", { plain = true }) do
    local field = vim.trim(token)
    if field ~= "" then
      fields[field] = true
    end
  end
  return fields
end

--- Parse a HAVING clause line.
--- @param line string e.g. "HAVING COUNT(Id) > 5"
--- @return table[] having_clauses
local function parse_having(line)
  local rest = line:match("^HAVING%s+(.*)$")
  if not rest then
    return {}
  end
  return parse_conditions(rest)
end

--- Parse an ORDER BY clause line.
--- @param line string e.g. "ORDER BY Name ASC, CreatedDate DESC NULLS LAST"
--- @return table[] order_by clauses
local function parse_order_by(line)
  local rest = line:match("^ORDER%s+BY%s+(.*)$")
  if not rest then
    return {}
  end

  local clauses = {}
  local parts = vim.split(rest, ",")

  for _, part in ipairs(parts) do
    part = part:match("^%s*(.-)%s*$") or ""

    -- 1. Full form: field DIRECTION NULLS NULLPOS
    local field, nulls_part = part:match("^([%w_.]+)%s+(ASC)%s+(NULLS%s+%u+)$")

    if not field then
      field, nulls_part = part:match("^([%w_.]+)%s+(DESC)%s+(NULLS%s+%u+)$")
    end

    if field and nulls_part then
      local direction = nulls_part:match("^(ASC)") or nulls_part:match("^(DESC)") or "ASC"
      local nulls = nulls_part:match("NULLS%s+(%u+)$")
      nulls = nulls and "NULLS " .. nulls or nil

      table.insert(clauses, { field = field, direction = direction, nulls = nulls })
    end

    -- 2. field DIRECTION (no nulls)
    if not field then
      local f, d = part:match("^([%w_.]+)%s+(ASC)$")

      if not f then
        f, d = part:match("^([%w_.]+)%s+(DESC)$")
      end

      if f then
        table.insert(clauses, { field = f, direction = d, nulls = nil })
        field = f
      end
    end

    -- 3. Bare field, assume ASC
    if not field then
      field = part:match("^([%w_.]+)%s*$")

      if field then
        table.insert(clauses, { field = field, direction = "ASC", nulls = nil })
      end
    end
  end

  return clauses
end

--- Parse a LIMIT line.
--- @param line string e.g. "LIMIT 10"
--- @return integer|nil
local function parse_limit(line)
  local n = line:match("^LIMIT%s+(%d+)$")
  return n and tonumber(n) or nil
end

--- Parse an OFFSET line.
--- @param line string e.g. "OFFSET 5"
--- @return integer|nil
local function parse_offset(line)
  local n = line:match("^OFFSET%s+(%d+)$")
  return n and tonumber(n) or nil
end

--- Parse a full compiled SOQL string into a QueryState-compatible table.
--- @param raw string The compiled SOQL text (multi-line or single-line)
--- @return table|nil Parsed data with sobject, selected_fields, where_clauses, etc.
function M.parse(raw)
  if not raw or raw == "" then
    return nil
  end

  local text = normalize_multiline(raw)
  local lines = split_lines(text)

  -- Merge lines that are continuations of multi-line subqueries
  -- (e.g. "FROM Contacts)" belongs with the SELECT line it continues).
  local merged = {}
  local pending = ""

  for _, line in ipairs(lines) do
    if pending ~= "" then
      pending = pending .. " " .. line

      -- If parens balanced, flush the merged line
      local open_count = select(2, pending:gsub("%(", ""))
      local close_count = select(2, pending:gsub("%)", ""))

      if open_count == close_count then
        merged[#merged + 1] = pending
        pending = ""
      end
    elseif line:match("^SELECT%s") then
      local open_count = select(2, line:gsub("%(", ""))
      local close_count = select(2, line:gsub("%)", ""))

      if open_count > close_count then
        -- SELECT has unbalanced parens — subquery spans next lines
        pending = line
      else
        merged[#merged + 1] = line
      end
    else
      merged[#merged + 1] = line
    end
  end

  -- Flush any remaining pending (shouldn't happen with valid SOQL)
  if pending ~= "" then
    merged[#merged + 1] = pending
  end

  local result = {
    sobject = "",
    selected_fields = {},
    where_clauses = {},
    order_by = {},
    limit = nil,
    offset = nil,
    subqueries = {},
    group_by = {},
    having_clauses = {},
    all_rows = false,
  }

  for _, line in ipairs(merged) do
    if line:match("^SELECT%s") then
      local parsed = parse_select(line)

      for _, f in ipairs(parsed.fields) do
        result.selected_fields[f] = true
      end

      -- Parse inline subqueries
      for _, sq_text in ipairs(parsed.subquery_texts) do
        local sq = parse_subquery(sq_text)
        if sq then
          -- The relationship name and parent are filled in by the builder/resume
          sq.is_subquery = true
          table.insert(result.subqueries, sq)
        end
      end
    elseif line:match("^FROM%s") then
      local name = line:match("^FROM%s+(%S+)")
      if name then
        result.sobject = name
      end
    elseif line:match("^WHERE%s") then
      result.where_clauses = parse_where(line)
    elseif line:match("^ORDER%s+BY%s") then
      result.order_by = parse_order_by(line)
    elseif line:match("^GROUP%s+BY%s") then
      result.group_by = parse_group_by(line)
    elseif line:match("^HAVING%s") then
      result.having_clauses = parse_having(line)
    elseif line:match("^LIMIT%s") then
      result.limit = parse_limit(line)
    elseif line:match("^OFFSET%s") then
      result.offset = parse_offset(line)
    elseif line:match("^ALL%s+ROWS$") then
      result.all_rows = true
    end
  end

  -- Must have at least an sObject
  if result.sobject == "" then
    return nil
  end

  return result
end

return M
