local Log = require("sf.core.log").scoped("core/utils")
local PathUtils = require("sf.core.path_utils")

local M = {}

--- Get the file name from a full path, extract file name from paths like "classes/myClass.cls"
--- @param full_path string The full path of the file
--- @return string The file name extracted from the full path
--- @usage local filename = utils.get_file_name("classes/myClass.cls") -- returns "myClass.cls"
function M.get_file_name(full_path)
  return PathUtils.get_filename(full_path)
end

--- Get sf project root directory by searching for .forceignore or sfdx-project.json files
--- @return string The root directory of the sf project
--- @usage local root = utils.get_sf_root() -- returns "/path/to/project/"
--- @error Throws error if file is not in a sf project folder
function M.get_sf_root()
  local root_patterns = { ".forceignore", "sfdx-project.json" }

  local start_path = vim.fs.dirname(vim.api.nvim_buf_get_name(0))

  -- If start_path is '.', use the current working directory instead
  if start_path == "." then
    start_path = vim.fn.getcwd()
  end

  local root = vim.fs.dirname(vim.fs.find(root_patterns, {
    upward = true,
    stop = vim.uv.os_homedir(),
    path = start_path,
  })[1])

  if root == nil then
    error("File not in a sf project folder")
  end

  root = PathUtils.ensure_trailing_separator(root)

  return root
end

--- Check if sfdx-project.json exists in the current working directory
--- @return boolean True if sfdx-project.json exists, false otherwise
--- @usage local has_project = utils.has_sfdx_project()
function M.has_sfdx_project()
  local project_file = PathUtils.join(vim.fn.getcwd(), "sfdx-project.json")
  return vim.fn.filereadable(project_file) == 1
end

--- Find a file in a directory and its subdirectories recursively
--- @param path string The directory path to search in
--- @param target string The target filename to find
--- @return string|nil The full path to the found file, or nil if not found
--- @usage local found_path = utils.find_file("/path/to/search", "target.txt")
function M.find_file(path, target)
  local scanner = vim.uv.fs_scandir(path)

  -- if scanner is nil, then path is not a valid dir
  if scanner then
    local file, type = vim.uv.fs_scandir_next(scanner)
    path = PathUtils.ensure_trailing_separator(path)

    while file do
      if type == "directory" then
        local found = M.find_file(PathUtils.join(path, file), target)
        if found then
          return found
        end
      elseif file == target then
        return PathUtils.join(path, file)
      end
      -- get the next file and type
      file, type = vim.uv.fs_scandir_next(scanner)
    end
  end
end

--- Get the default package directory path from sfdx-project.json
--- @return string|nil The path to the default package directory with /main/default appended, or nil if not found
--- @usage local default_path = utils.get_default_package_path()
function M.get_default_package_path()
  local project_file = PathUtils.join(vim.fn.getcwd(), "sfdx-project.json")

  if vim.fn.filereadable(project_file) ~= 1 then
    return nil
  end

  local file_content = vim.fn.readfile(project_file)

  if not file_content or #file_content == 0 then
    return nil
  end

  local json_string = table.concat(file_content, "\n")
  Log.deb("sfdx-project.json content:", json_string)

  local ok, project_config = pcall(vim.json.decode, json_string)

  if not ok then
    Log.deb("Failed to parse sfdx-project.json")
    return nil
  end

  Log.deb("Parsed sfdx-project.json:", project_config)

  if not project_config or not project_config.packageDirectories then
    Log.deb("No packageDirectories found in sfdx-project.json")
    return nil
  end

  -- Find the default package directory
  for _, package_dir in ipairs(project_config.packageDirectories) do
    if package_dir.default and package_dir.path then
      return PathUtils.join(PathUtils.get_separator(), package_dir.path, "main", "default")
    end
  end

  -- If no default found, use the first package directory
  if #project_config.packageDirectories > 0 and project_config.packageDirectories[1].path then
    return PathUtils.join(PathUtils.get_separator(), project_config.packageDirectories[1].path, "main", "default")
  end

  return nil
end

--- Gets changed files from git diff HEAD (excluding deletions).
--- Filters to files inside the default package directory.
--- Must be called inside an async.async() block.
--- @return table|nil paths List of changed file paths, or nil on error
--- @return string|nil err Error message if git command failed
function M.get_changed_files()
  local Config = require("sf.config")
  local Async = require("sf.core.async")
  local git = Config:get_options().git_path or "git"
  local stdout, code = Async.await_system(git, { "diff", "--name-only", "--diff-filter=d", "HEAD" })

  if code ~= 0 then
    return nil, "Git diff failed: " .. stdout
  end

  -- Resolve the default package path to use as a filter prefix
  local package_path = M.get_default_package_path()
  if not package_path then
    return nil, "Could not determine default package directory from sfdx-project.json"
  end

  -- Strip leading separator and add trailing / for prefix matching
  local prefix = package_path:gsub("^[/\\]+", "") .. "/"

  local paths = {}
  for line in stdout:gmatch("[^\r\n]+") do
    if line:sub(1, #prefix) == prefix then
      table.insert(paths, line)
    end
  end

  return paths, nil
end

return M
