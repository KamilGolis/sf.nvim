local Snacks = require("snacks")
local M = {}

local debug = false
local debug_inspect = false
local logger_scope = {}

--- Configure logging from Config options. Called once in Config:setup().
--- @param opts table options table
function M.configure(opts)
  debug = opts.debug or false
  debug_inspect = opts.debug_inspect or false
  logger_scope = opts.logger_scope or {}
end

--- vim.notify wrapper that also debugs the message.
--- @param msg string
--- @param level number|nil vim.log.levels (defaults to INFO)
function M.notify(msg, level)
  level = level or vim.log.levels.INFO
  vim.notify(msg, level)
  M.deb("Notify:", msg)
end

function M.deb(...)
  if not debug then
    return
  end
  if logger_scope and #logger_scope > 0 then
    local caller = debug.getinfo(2, "S")
    local src = caller and caller.source or ""
    local matched = false
    for _, pattern in ipairs(logger_scope) do
      if src:find(pattern, 1, true) then
        matched = true
        break
      end
    end
    if not matched then
      return
    end
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
  if logger_scope and #logger_scope > 0 then
    local caller = debug.getinfo(2, "S")
    local src = caller and caller.source or ""
    local matched = false
    for _, pattern in ipairs(logger_scope) do
      if src:find(pattern, 1, true) then
        matched = true
        break
      end
    end
    if not matched then
      return
    end
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
