--- sf-nvim schema cleanup module
-- @license MIT

local Config = require("sf.config")
local Log = require("sf.core.log")
local PathUtils = require("sf.core.path_utils")
local Snacks = require("snacks")

local Cleanup = {}

--- Clean up cached schema data: deletes `metadata-types.json` and all `.json`
--- files under the `metadatas/` directory.
--- Does NOT delete `retrieve.json` or the `metadatas/` directory itself.
--- Prompts for confirmation before deleting.
function Cleanup.cleanup_schema()
  local metadata_types_file = Config:get_options().metadata_types_file
  local metadatas_dir = Config:get_options().metadatas_dir

  Snacks.input({
    prompt = "Delete all cached schema data? [y/N]: ",
    default = "N",
  }, function(value)
    if not value or not value:lower():match("^y") then
      Log.notify("Schema cleanup cancelled", vim.log.levels.INFO)
      return
    end

    local deleted_count = 0
    local types_deleted = false

    if vim.fn.filereadable(metadata_types_file) == 1 then
      types_deleted = pcall(vim.fn.delete, metadata_types_file)
      if types_deleted then
        deleted_count = deleted_count + 1
      end
    end

    local metadata_pattern = PathUtils.join(metadatas_dir, "*.json")
    local metadata_files = vim.fn.glob(metadata_pattern, false, true)

    for _, f in ipairs(metadata_files) do
      local ok = pcall(vim.fn.delete, f)

      if ok then
        deleted_count = deleted_count + 1
      end
    end

    local message_parts = {}
    table.insert(message_parts, string.format("%d cached file(s) removed", deleted_count))

    Log.notify("Schema cleanup complete: " .. table.concat(message_parts, ", "), vim.log.levels.INFO)
  end)
end

return Cleanup
