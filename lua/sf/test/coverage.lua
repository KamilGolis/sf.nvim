--- sf-nvim coverage display module
-- @license MIT

local Coverage = {}

-- Global variable to track coverage display state
vim.g.sf_coverage_enabled = false

--- Define coverage signs
local function setup_coverage_signs()
  vim.fn.sign_define("SfCovered", {
    text = "●",
    texthl = "DiffAdd",
    linehl = "",
    numhl = "DiffAdd",
  })

  vim.fn.sign_define("SfUncovered", {
    text = "●",
    texthl = "DiffDelete",
    linehl = "",
    numhl = "DiffDelete",
  })
end

--- Get the coverage results file path
--- @return string The path to coverage results file
local function get_coverage_file_path()
  local config = require("sf.config")
  return config:get_options().coverage_results_file
end

--- Parse coverage data from coverage.json file
--- @return table|nil The parsed coverage data or nil if failed
local function parse_coverage_data()
  local coverage_file = get_coverage_file_path()

  -- Check if coverage file exists
  if vim.fn.filereadable(coverage_file) ~= 1 then
    return nil
  end

  -- Read and parse the coverage file
  local file_content = vim.fn.readfile(coverage_file)
  if not file_content or #file_content == 0 then
    return nil
  end

  local json_string = table.concat(file_content, "\n")
  deb("Coverage file content:", json_string)
  
  local ok, result = pcall(vim.json.decode, json_string)

  if not ok then
    deb("Failed to parse coverage JSON")
    return nil
  end
  
  deb("Parsed coverage result:", result)

  if not result or not result.result or not result.result.coverage then
    deb("Coverage result missing expected structure")
    return nil
  end

  deb("Coverage data:", result.result.coverage.coverage)
  return result.result.coverage.coverage
end

--- Find coverage data for a specific class
--- @param coverage_data table The coverage data from JSON
--- @param class_name string The name of the class to find
--- @return table|nil The coverage data for the class or nil if not found
local function find_class_coverage(coverage_data, class_name)
  if not coverage_data then
    return nil
  end

  for _, class_coverage in ipairs(coverage_data) do
    if class_coverage.name == class_name then
      return class_coverage
    end
  end

  return nil
end

--- Clear all coverage signs from a buffer
--- @param bufnr number The buffer number
local function clear_coverage_signs(bufnr)
  vim.fn.sign_unplace("sf_coverage", { buffer = bufnr })
end

--- Display coverage signs for a buffer
--- @param bufnr number The buffer number
--- @param class_coverage table The coverage data for the class
local function display_coverage_signs(bufnr, class_coverage)
  if not class_coverage or not class_coverage.lines then
    return
  end

  -- Clear existing signs first
  clear_coverage_signs(bufnr)

  -- Place signs for each line with coverage data
  for line_str, coverage_value in pairs(class_coverage.lines) do
    local line_num = tonumber(line_str)
    if line_num then
      local sign_name = coverage_value == 1 and "SfCovered" or "SfUncovered"
      vim.fn.sign_place(0, "sf_coverage", sign_name, bufnr, { lnum = line_num })
    end
  end
end

--- Get class name from file path
--- @param file_path string The file path
--- @return string|nil The class name or nil if not found
local function get_class_name_from_path(file_path)
  if not file_path or file_path == "" then
    return nil
  end

  -- Extract filename without extension
  local filename = vim.fn.fnamemodify(file_path, ":t:r")

  -- Check if it's an Apex class file
  if vim.fn.fnamemodify(file_path, ":e") == "cls" then
    return filename
  end

  return nil
end

--- Enable coverage display
function Coverage.enable()
  vim.g.sf_coverage_enabled = true
  setup_coverage_signs()

  -- Apply coverage to all currently open Apex files
  for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_loaded(bufnr) then
      local file_path = vim.api.nvim_buf_get_name(bufnr)
      local class_name = get_class_name_from_path(file_path)
      if class_name then
        Coverage.show_coverage_for_buffer(bufnr, class_name)
      end
    end
  end

  vim.notify("Coverage display enabled", vim.log.levels.INFO)
end

--- Disable coverage display
function Coverage.disable()
  vim.g.sf_coverage_enabled = false

  -- Clear coverage signs from all buffers
  for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_loaded(bufnr) then
      clear_coverage_signs(bufnr)
    end
  end

  vim.notify("Coverage display disabled", vim.log.levels.INFO)
end

--- Show coverage for a specific buffer
--- @param bufnr number The buffer number
--- @param class_name string The class name
function Coverage.show_coverage_for_buffer(bufnr, class_name)
  if not vim.g.sf_coverage_enabled then
    return
  end

  local coverage_data = parse_coverage_data()
  if not coverage_data then
    return
  end

  local class_coverage = find_class_coverage(coverage_data, class_name)
  if class_coverage then
    display_coverage_signs(bufnr, class_coverage)
  end
end

--- Handle buffer enter event for coverage display
--- @param bufnr number The buffer number
function Coverage.on_buffer_enter(bufnr)
  if not vim.g.sf_coverage_enabled then
    return
  end

  local file_path = vim.api.nvim_buf_get_name(bufnr)
  local class_name = get_class_name_from_path(file_path)

  if class_name then
    Coverage.show_coverage_for_buffer(bufnr, class_name)
  end
end

return Coverage

