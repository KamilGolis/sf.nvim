--- Apply basic analysis highlights to sflog filetype buffers
-- @license MIT

local Analyze = require("sf.log.analyze")
Analyze.apply_highlights(vim.api.nvim_get_current_buf())
