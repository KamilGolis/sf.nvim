--- sf-nvim log cleanup module
-- @license MIT

local Config = require("sf.config")
local PathUtils = require("sf.core.path_utils")
local Snacks = require("snacks")
local Utils = require("sf.log.utils")

local Cleanup = {}

--- Clean up cached log files and log list
--- Prompts for confirmation before deleting
function Cleanup.cleanup_logs()
  local log_dir = Config:get_options().log_dir
  local log_list_file = Utils.get_log_list_path()

  Snacks.input({
    prompt = "Delete all cached debug logs? [y/N]: ",
    default = "N",
  }, function(value)
    if not value or not value:lower():match("^y") then
      vim.notify("Log cleanup cancelled", vim.log.levels.INFO)
      return
    end

    -- Delete log files from logs directory
    local deleted_count = 0
    local log_pattern = PathUtils.join(log_dir, "*.log")
    local log_files = vim.fn.glob(log_pattern, false, true)

    for _, f in ipairs(log_files) do
      local ok = pcall(vim.fn.delete, f)
      if ok then
        deleted_count = deleted_count + 1
      end
    end

    -- Delete logList.json
    local list_deleted = false
    if vim.fn.filereadable(log_list_file) == 1 then
      list_deleted = pcall(vim.fn.delete, log_list_file)
    end

    local message_parts = {}
    table.insert(message_parts, string.format("%d log file(s) removed", deleted_count))

    if list_deleted then
      table.insert(message_parts, "log list removed")
    end

    vim.notify("Log cleanup complete: " .. table.concat(message_parts, ", "), vim.log.levels.INFO)
  end)
end

return Cleanup
