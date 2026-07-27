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
    -- Insert newlines before major keywords for uniform parsing
    local parts = {}
    local remaining = raw

    -- Split on SELECT/FROM/WHERE/ORDER BY/LIMIT/OFFSET
    for keyword in remaining:gmatch("(%u+%s+)[%(%u]") do
      -- This is tricky. Let's use a simpler approach.
    end

    -- Simpler: just return as a single line
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
      current = current .. ch
    elseif ch == ")" then
      paren_depth = paren_depth - 1
      current = current .. ch

      if paren_depth == 0 and in_subquery then
        -- End of subquery
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

--- Parse a WHERE clause line into individual conditions.
--- @param line string e.g. "WHERE Name = 'Test' AND Industry != 'Technology'"
--- @return table[] where_clauses
local function parse_where(line)
  local rest = line:match("^WHERE%s+(.*)$")
  if not rest then
    return {}
  end

  local clauses = {}
  -- Split on " AND " (case-insensitive, whole word)
  local conditions = vim.split(rest, "%s+AND%s+", { plain = false })

  for _, cond in ipairs(conditions) do
    -- Match: field op value pattern
    -- Operators: =, !=, <, >, <=, >=, <>, LIKE, IN, NOT IN, INCLUDES, EXCLUDES
    local field, op, value =
      cond:match("^%s*([%w_.]+)%s+(=|!=|<>|<=|>=|<|>|LIKE|IN|NOT%s+IN|INCLUDES|EXCLUDES)%s+(.+)$")

    if field and op and value then
      -- Unquote string values
      value = value:match("^'(.*)'$") or value

      table.insert(clauses, { field = field, op = op, value = value })
    end
  end

  return clauses
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

    local field, direction, nulls = part:match("^([%w_.]+)%s+(ASC|DESC)%s+(NULLS%s+(FIRST|LAST))$")

    if not field then
      field, direction = part:match("^([%w_.]+)%s+(ASC|DESC)$")
    end

    if not field then
      field = part:match("^([%w_.]+)%s*$")
      direction = "ASC"
    end

    if field then
      table.insert(clauses, {
        field = field,
        direction = direction or "ASC",
        nulls = nulls and nulls:match("(FIRST|LAST)$") or nil,
      })
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

  local result = {
    sobject = "",
    selected_fields = {},
    where_clauses = {},
    order_by = {},
    limit = nil,
    offset = nil,
    subqueries = {},
  }

  for _, line in ipairs(lines) do
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
    elseif line:match("^LIMIT%s") then
      result.limit = parse_limit(line)
    elseif line:match("^OFFSET%s") then
      result.offset = parse_offset(line)
    end
  end

  -- Must have at least an sObject
  if result.sobject == "" then
    return nil
  end

  return result
end

return M
