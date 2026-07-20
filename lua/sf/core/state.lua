local M = {}
--- Central job busy-state registry.
--- Known job kinds (used by modules): "deploy", "test", "retrieve", "diff", "debug", "apex", "scan"

local busy = {}

--- Mark a job kind as in-flight. Call before job:start().
function M.start(kind)
  busy[kind] = true
end

--- Mark a job kind as idle. Call in the job's cleanup_callback.
function M.finish(kind)
  busy[kind] = false
end

--- Returns true if a job of the given kind is in-flight.
function M.is_busy(kind)
  return busy[kind] == true
end

return M
