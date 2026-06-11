local M = {}

--- Helper function to create a progress handle using Neovim's built-in
--- LSP $/progress mechanism, or a no-op handle when unavailable.
--- @param params table The parameters for the progress handle containing title field
--- @return table Progress handle with report() and finish() methods
--- @usage local handle = process.create_progress_handle({ title = "Processing..." })
function M.create_progress_handle(params)
  return require("sf.core.progress").create_handle({
    title = params.title,
  })
end

return M
