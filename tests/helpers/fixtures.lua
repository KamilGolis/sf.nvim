--- Test fixture loader.
-- Provides helper functions to load JSON and text fixtures
-- from the tests/fixtures/<capability>/ directory.

local M = {}

--- Determine the fixtures root path relative to the Neovim CWD.
-- Assumes tests are run from the project root.
local function fixtures_root()
  return "tests/fixtures"
end

--- Load a fixture file (raw text).
-- @param capability string The capability subdirectory name
-- @param filename string The fixture file name
-- @return string|nil File content, or nil with error
function M.load_text(capability, filename)
  local path = fixtures_root() .. "/" .. capability .. "/" .. filename
  local file = io.open(path, "r")
  if not file then
    return nil, "Fixture not found: " .. path
  end
  local content = file:read("*a")
  file:close()
  return content, nil
end

--- Load a JSON fixture file and decode it.
-- @param capability string The capability subdirectory name
-- @param filename string The fixture file name
-- @return table|nil Decoded JSON table, or nil with error
function M.load_json(capability, filename)
  local content, err = M.load_text(capability, filename)
  if not content then
    return nil, err
  end
  local ok, parsed = pcall(vim.json.decode, content)
  if not ok then
    return nil, "Failed to decode JSON from " .. capability .. "/" .. filename .. ": " .. tostring(parsed)
  end
  return parsed, nil
end

--- Load a fixture and return its full path (for file I/O tests).
-- @param capability string
-- @param filename string
-- @return string Absolute path to the fixture file
function M.path(capability, filename)
  local cwd = vim.fn.getcwd()
  return cwd .. "/" .. fixtures_root() .. "/" .. capability .. "/" .. filename
end

--- Check if a fixture file exists.
-- @param capability string
-- @param filename string
-- @return boolean
function M.exists(capability, filename)
  local path = fixtures_root() .. "/" .. capability .. "/" .. filename
  local file = io.open(path, "r")
  if file then
    file:close()
    return true
  end
  return false
end

return M
