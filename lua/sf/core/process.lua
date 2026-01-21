local M = {}

--- Helper function to create a progress handle using fidget.progress or a dummy handle
--- @param params table The parameters for the progress handle containing title field
--- @return table Progress handle with report() and finish() methods
--- @usage local handle = process.create_progress_handle({ title = "Processing..." })
function M.create_progress_handle(params)
  local ok, progress = pcall(require, "fidget.progress")
  if not ok then
    -- If fidget is not available, return a dummy handle
    return {
      report = function() end,
      finish = function() end,
    }
  end
  return progress.handle.create({
    title = params.title,
    lsp_client = { name = "sf" },
    percentage = 0,
  })
end

return M
