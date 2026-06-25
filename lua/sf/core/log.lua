local Snacks = require("snacks")
local M = {}

local debug = false
local debug_inspect = false

--- Configure logging from Config options. Called once in Config:setup().
--- @param opts table options table
function M.configure(opts)
  debug = opts.debug or false
  debug_inspect = opts.debug_inspect or false
end

function M.deb(...)
  if not debug then
    return
  end
  if debug_inspect then
    Snacks.debug.inspect(...)
  end
  Snacks.debug.log(...)
end

function M.log(...)
  if not debug then
    return
  end
  Snacks.debug.log(...)
end

function M.trace()
  if not debug then
    return
  end
  Snacks.debug.backtrace()
end

function M.inspect(...)
  if not debug then
    return
  end
  if debug_inspect then
    Snacks.debug.inspect(...)
  end
end

return M
