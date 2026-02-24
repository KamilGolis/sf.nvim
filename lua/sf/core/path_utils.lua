--- Cross-platform path utilities for sf.nvim
--- Provides OS-aware path operations to ensure compatibility on Windows and Unix-like systems
--- @class PathUtils
local M = {}

--- Detect the operating system
--- @return string "windows" or "unix"
local function get_os()
  if jit then
    return jit.os == "Windows" and "windows" or "unix"
  end
  -- Fallback detection
  local separator = package.config:sub(1, 1)
  return separator == "\\" and "windows" or "unix"
end

local os_type = get_os()

--- Get the OS-appropriate path separator
--- @return string Path separator ("/" for Unix, "\\" for Windows)
--- @usage local sep = path_utils.get_separator()
function M.get_separator()
  return os_type == "windows" and "\\" or "/"
end

--- Normalize a path to use OS-appropriate separators
--- Converts all path separators to the current OS format and removes double separators
--- @param path string The path to normalize
--- @return string Normalized path with OS-appropriate separators
--- @usage local norm_path = path_utils.normalize("some/path\\to/file")
function M.normalize(path)
  if not path or path == "" then
    return path
  end

  if os_type == "windows" then
    -- Convert forward slashes to backslashes on Windows
    path = path:gsub("/", "\\")
    -- Remove duplicate backslashes (but preserve UNC paths \\server\share)
    -- First, check if it's a UNC path
    local is_unc = path:match("^\\\\")
    if is_unc then
      -- Keep the leading \\ and remove other duplicates
      path = "\\\\" .. path:sub(3):gsub("\\+", "\\")
    else
      -- Remove all duplicate backslashes
      path = path:gsub("\\+", "\\")
    end
  else
    -- Convert backslashes to forward slashes on Unix
    path = path:gsub("\\", "/")
    -- Remove duplicate forward slashes (but preserve leading // for network paths)
    local is_network = path:match("^//")
    if is_network then
      path = "//" .. path:sub(3):gsub("/+", "/")
    else
      path = path:gsub("/+", "/")
    end
  end

  return path
end

--- Join path segments using OS-appropriate separator
--- @vararg string Path segments to join
--- @return string Joined path with OS-appropriate separators
--- @usage local path = path_utils.join("path", "to", "file.txt")
function M.join(...)
  local parts = { ... }
  local separator = M.get_separator()

  -- Filter out empty parts and strip trailing separators to avoid doubles
  local filtered = {}
  for _, part in ipairs(parts) do
    if part and part ~= "" then
      table.insert(filtered, M.remove_trailing_separator(part))
    end
  end

  if #filtered == 0 then
    return ""
  end

  -- Join with separator and normalize
  local joined = table.concat(filtered, separator)
  return M.normalize(joined)
end

--- Ensure a path ends with a trailing separator
--- @param path string The path to check
--- @return string Path with trailing separator
--- @usage local path = path_utils.ensure_trailing_separator("/path/to/dir")
function M.ensure_trailing_separator(path)
  if not path or path == "" then
    return path
  end

  local separator = M.get_separator()
  if path:sub(-1) ~= separator then
    return path .. separator
  end
  return path
end

--- Extract the filename from a path (OS-aware)
--- @param path string The full path
--- @return string The filename extracted from the path
--- @usage local filename = path_utils.get_filename("path/to/file.txt") -- returns "file.txt"
function M.get_filename(path)
  if not path or path == "" then
    return path
  end

  -- Normalize first to ensure consistent separators
  path = M.normalize(path)
  local separator = M.get_separator()

  -- Escape separator for pattern matching
  local pattern = separator == "\\" and "\\([^\\]+)$" or "/([^/]+)$"
  local filename = path:match(pattern)

  return filename or path
end

--- Check if a path is absolute (cross-platform)
--- @param path string The path to check
--- @return boolean True if the path is absolute
--- @usage local is_abs = path_utils.is_absolute("/path/to/file")
function M.is_absolute(path)
  if not path or path == "" then
    return false
  end

  if os_type == "windows" then
    -- Windows: check for drive letter (C:\) or UNC path (\\server\)
    return path:match("^[A-Za-z]:[\\/]") ~= nil or path:match("^\\\\") ~= nil
  else
    -- Unix: check if starts with /
    return path:sub(1, 1) == "/"
  end
end

--- Remove trailing separator from a path if present
--- @param path string The path to process
--- @return string Path without trailing separator
--- @usage local path = path_utils.remove_trailing_separator("/path/to/dir/")
function M.remove_trailing_separator(path)
  if not path or path == "" then
    return path
  end

  local separator = M.get_separator()
  if path:sub(-1) == separator then
    return path:sub(1, -2)
  end
  return path
end

--- Convert a relative path to use forward slashes (for SF CLI compatibility)
--- SF CLI expects Unix-style paths even on Windows for some arguments
--- @param path string The path to convert
--- @return string Path with forward slashes
--- @usage local cli_path = path_utils.to_forward_slashes("path\\to\\file")
function M.to_forward_slashes(path)
  if not path or path == "" then
    return path
  end
  return path:gsub("\\", "/")
end

return M
