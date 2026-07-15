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

--- Check whether a module name matches the configured logger_scope filter.
--- @param module_name string
--- @return boolean
local function should_log(module_name)
  if not logger_scope or #logger_scope == 0 then
    return true
  end
  for _, pattern in ipairs(logger_scope) do
    if module_name:find(pattern, 1, true) then
      return true
    end
  end
  return false
end

--- Check whether an unscoped caller passes the getinfo-based scope filter.
--- @return boolean
local function should_log_unscoped()
  if not logger_scope or #logger_scope == 0 then
    return true
  end
  local caller = debug.getinfo(2, "S")
  local src = caller and caller.source or ""
  for _, pattern in ipairs(logger_scope) do
    if src:find(pattern, 1, true) then
      return true
    end
  end
  return false
end

--- Create a scoped logger for a specific module.
--- Every call to deb / log / inspect / trace on the returned object will
--- emit log output prefixed with `[module_name]` and filter through
--- logger_scope using the module_name string directly (no debug.getinfo).
--- @param module_name string e.g. "core/job_utils"
--- @return table { deb, log, inspect, trace, notify }
function M.scoped(module_name)
  local self = {}

  function self.deb(...)
    if not debug then
      return
    end
    if not should_log(module_name) then
      return
    end
    if debug_inspect then
      Snacks.debug.inspect(...)
    end
    local args = { "[" .. module_name .. "]", ... }
    Snacks.debug.log(unpack(args))
  end

  function self.log(...)
    if not debug then
      return
    end
    if not should_log(module_name) then
      return
    end
    local args = { "[" .. module_name .. "]", ... }
    Snacks.debug.log(unpack(args))
  end

  function self.inspect(...)
    if not debug then
      return
    end
    if not should_log(module_name) then
      return
    end
    if debug_inspect then
      Snacks.debug.inspect(...)
    end
    local args = { "[" .. module_name .. "]", ... }
    Snacks.debug.log(unpack(args))
  end

  function self.trace()
    if not debug then
      return
    end
    if not should_log(module_name) then
      return
    end
    Snacks.debug.backtrace()
  end

  function self.notify(msg, level)
    level = level or vim.log.levels.INFO
    vim.notify(msg, level)
    if not debug then
      return
    end
    if not should_log(module_name) then
      return
    end
    local args = { "[" .. module_name .. "]", "Notify:", msg }
    Snacks.debug.log(unpack(args))
  end

  return self
end

--- vim.notify wrapper that also debugs the message.
--- @param msg string
--- @param level number|nil vim.log.levels (defaults to INFO)
--- @param module_name string|nil optional module name for scoped debug prefix
function M.notify(msg, level, module_name)
  level = level or vim.log.levels.INFO
  vim.notify(msg, level)
  if module_name then
    M.scoped(module_name).deb("Notify:", msg)
  else
    M.deb("Notify:", msg)
  end
end

function M.deb(...)
  if not debug then
    return
  end
  if not should_log_unscoped() then
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
  if not should_log_unscoped() then
    return
  end
  Snacks.debug.log(...)
end

function M.trace()
  if not debug then
    return
  end
  if not should_log_unscoped() then
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
