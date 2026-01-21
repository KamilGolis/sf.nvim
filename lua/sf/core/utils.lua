local M = {}

--- Check if a job is running
--- @param self table The job instance to check
--- @return boolean True if the job is running, false otherwise
--- @usage local is_running = utils.is_job_running(my_job)
function M.is_job_running(self)
  if self.handle and not vim.loop.is_closing(self.handle) and vim.loop.is_active(self.handle) then
    return true
  else
    return false
  end
end

--- Get the file name from a full path, extract file name from paths like "classes/myClass.cls"
--- @param full_path string The full path of the file
--- @return string The file name extracted from the full path
--- @usage local filename = utils.get_file_name("classes/myClass.cls") -- returns "myClass.cls"
function M.get_file_name(full_path)
  return full_path:match("[^/]+$")
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

  if root:sub(-1) ~= "/" then
    root = root .. "/"
  end

  return root
end

--- Check if sfdx-project.json exists in the current working directory
--- @return boolean True if sfdx-project.json exists, false otherwise
--- @usage local has_project = utils.has_sfdx_project()
function M.has_sfdx_project()
  return vim.fn.filereadable(vim.fn.getcwd() .. "/sfdx-project.json") == 1
end

--- Find a file in a directory and its subdirectories recursively
--- @param path string The directory path to search in
--- @param target string The target filename to find
--- @return string|nil The full path to the found file, or nil if not found
--- @usage local found_path = utils.find_file("/path/to/search", "target.txt")
function M.find_file(path, target)
  local scanner = vim.loop.fs_scandir(path)
  -- if scanner is nil, then path is not a valid dir
  if scanner then
    local file, type = vim.loop.fs_scandir_next(scanner)
    if path:sub(-1) ~= "/" then
      path = path .. "/"
    end
    while file do
      if type == "directory" then
        local found = M.find_file(path .. file, target)
        if found then
          return found
        end
      elseif file == target then
        return path .. file
      end
      -- get the next file and type
      file, type = vim.loop.fs_scandir_next(scanner)
    end
  end
end

--- Get the default package directory path from sfdx-project.json
--- @return string|nil The path to the default package directory with /main/default appended, or nil if not found
--- @usage local default_path = utils.get_default_package_path()
function M.get_default_package_path()
  local project_file = vim.fn.getcwd() .. "/sfdx-project.json"

  if vim.fn.filereadable(project_file) ~= 1 then
    return nil
  end

  local file_content = vim.fn.readfile(project_file)
  if not file_content or #file_content == 0 then
    return nil
  end

  local json_string = table.concat(file_content, "\n")
  local ok, project_config = pcall(vim.json.decode, json_string)

  if not ok or not project_config or not project_config.packageDirectories then
    return nil
  end

  -- Find the default package directory
  for _, package_dir in ipairs(project_config.packageDirectories) do
    if package_dir.default and package_dir.path then
      return "/" .. package_dir.path .. "/main/default"
    end
  end

  -- If no default found, use the first package directory
  if #project_config.packageDirectories > 0 and project_config.packageDirectories[1].path then
    return "/" .. project_config.packageDirectories[1].path .. "/main/default"
  end

  return nil
end

return M
