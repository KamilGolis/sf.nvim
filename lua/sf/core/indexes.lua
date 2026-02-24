--- Module for indexing files in a project directory
--- @class Indexes
local PathUtils = require("sf.core.path_utils")
local M = {}

--- Table to store the file index
--- @type table<string, string>
local file_index = {}

--- Get the file index containing all indexed files
--- @return table<string, string> A table containing the file index, where keys are file names and values are their full paths
--- @usage local index = indexes.get_file_index()
function M.get_file_index()
  return file_index
end

--- Index all files in the project directory recursively
--- Recursively scans the specified directory and its subdirectories to build an index of files.
--- The index maps file names to their full paths for quick lookup.
--- @param path string The relative path to the project directory
--- @usage indexes.index_files("/force-app")
function M.index_files(path)
  local cwd = PathUtils.normalize(PathUtils.join(vim.loop.cwd(), path))

  local function scan_directory(dir_path)
    local handle = vim.loop.fs_scandir(dir_path)
    if not handle then
      vim.notify("Failed to scan directory: " .. dir_path, vim.log.levels.ERROR)
      return
    end

    while true do
      local name, type = vim.loop.fs_scandir_next(handle)
      if not name then
        break
      end

      local full_path = PathUtils.normalize(PathUtils.join(dir_path, name))
      if type == "file" then
        file_index[name] = full_path
      elseif type == "directory" then
        -- Recursively scan subdirectories
        scan_directory(full_path)
      end
    end
  end

  scan_directory(cwd)
  vim.notify(
    "Indexed " .. vim.tbl_count(file_index) .. " files in project directory: " .. cwd,
    vim.log.levels.INFO
  )
end

return M
