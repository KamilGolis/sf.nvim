--- Shared buffer rendering utilities
-- @license MIT

local M = {}

--- Write formatted lines to a buffer with an associated line map for interactive navigation.
--- @param buf number Buffer handle
--- @param lines table Array of strings to render
--- @param line_map table Map of line numbers (1-indexed) to navigation keys
--- @param line_map_var string Buffer-local variable name to store the line map (e.g. "debug_level_line_map")
function M.render_accordion(buf, lines, line_map, line_map_var)
  vim.bo[buf].modifiable = true
  vim.bo[buf].readonly = false
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.b[buf][line_map_var] = line_map
  vim.bo[buf].modified = false
  vim.bo[buf].readonly = true
  vim.bo[buf].modifiable = false
end

return M
