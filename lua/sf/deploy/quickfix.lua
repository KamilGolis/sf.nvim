--- Quickfix list validation for selected-files deployment.
--- Validates files from the Neovim quickfix list against the
--- SFDX project index for deployability.

local Log = require("sf.core.log").scoped("deploy/quickfix")

local M = {}

--- Validates and processes quickfix list files for selected metadata deployment
--- @param indexes table The indexes instance for file lookups
--- @param utils table The utils instance for file name extraction
--- @return boolean success Whether validation passed
--- @return table|nil found_files List of valid files found in quickfix list
--- @return table|nil missing_files List of files not found in index
--- @return string|nil error_message Error message if validation failed
function M.validate_quickfix_files(indexes, utils)
  local items = vim.fn.getqflist()

  if #items == 0 then
    return false, nil, nil, "Quickfix list is empty"
  end

  Log.deb("Quickfix List Items", items)

  local indexed_files = indexes.get_file_index()
  local found = {}
  local missing_files = {}

  for _, item in ipairs(items) do
    -- Ensure item has bufnr and it's valid before proceeding
    if item.bufnr and vim.fn.bufexists(item.bufnr) == 1 then
      local file = vim.fn.bufname(item.bufnr)
      local file_name = utils.get_file_name(file)
      local full_path = indexed_files[file_name]

      if full_path and full_path ~= "" then
        -- Avoid duplicates
        if not vim.tbl_contains(found, full_path) then
          table.insert(found, full_path)
        end
      else
        if not vim.tbl_contains(missing_files, file_name) then
          table.insert(missing_files, file_name)
        end
      end
    else
      Log.deb("Skipping invalid quickfix item", item)
    end
  end

  if #found == 0 then
    local error_msg = "No valid, indexed files found in the quickfix list."

    if #missing_files > 0 then
      error_msg = error_msg .. " Missing indexed files: " .. table.concat(missing_files, ", ")
    end

    return false, nil, missing_files, error_msg
  end

  if #missing_files > 0 then
    vim.schedule(function()
      Log.notify("Could not find index entry for: " .. table.concat(missing_files, ", "), vim.log.levels.WARN)
    end)
  end

  Log.deb("Found Files to Deploy", found)
  Log.deb("Missing Files", missing_files)

  return true, found, missing_files, nil
end

return M
