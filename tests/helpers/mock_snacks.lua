--- Mock Snacks.nvim picker for testing.
-- Captures the picker config (items, callbacks) so tests can
-- assert what was passed to the picker and manually invoke
-- the confirm callback to simulate user selection.

local M = {}

-- Captured picker invocations
M.calls = {}    -- { items, config } per Snacks.picker call

-- Callbacks stored by index so tests can invoke them
M.confirm_callbacks = {}  -- index -> function(picker, item)
M.preview_callbacks = {}  -- index -> function(ctx)

M._orig = {}

--- Ensure the snacks module is loaded with a stub table.
-- Patching via package.loaded ensures any module that did
-- `local Snacks = require("snacks")` sees the same table.
local function ensure_snacks()
  if not package.loaded.snacks then
    package.loaded.snacks = {
      debug = {
        inspect = function() end,
        log = function() end,
        backtrace = function() end,
      },
    }
  end
  _G.Snacks = package.loaded.snacks
end

--- Override Snacks.picker with a capture mock.
-- The mock stores the entire config and makes confirm/preview
-- callbacks accessible via M.confirm_callbacks and M.preview_callbacks.
-- If Snacks is not yet loaded (e.g. headless test runner), a stub
-- table is created so the original require path remains clean.
function M.setup()
  ensure_snacks()
  if Snacks.picker then
    M._orig.Snacks_picker = Snacks.picker
  else
    M._orig.Snacks_picker = nil
  end
  M.calls = {}
  M.confirm_callbacks = {}
  M.preview_callbacks = {}

  Snacks.picker = function(config)
    table.insert(M.calls, config or {})
    local idx = #M.calls

    -- Store confirm callback if present
    if config and config.confirm then
      M.confirm_callbacks[idx] = config.confirm
    end

    -- Store preview callback if present
    if config and config.preview then
      M.preview_callbacks[idx] = config.preview
    end

    -- Execute on_done or source if provided (simulates picker setup)
    if config and config.on_done then
      config.on_done()
    end
  end
end

--- Restore original Snacks.picker.
function M.restore()
  if M._orig.Snacks_picker then
    Snacks.picker = M._orig.Snacks_picker
  end
  M.calls = {}
  M.confirm_callbacks = {}
  M.preview_callbacks = {}
end

--- Get the items passed to the Nth picker call (default 1).
-- @param idx number Picker call index (1-based)
-- @return table|nil The items array, or nil if not found
function M.get_items(idx)
  idx = idx or 1
  local config = M.calls[idx]
  if config and config.items then
    return config.items
  end
  return nil
end

--- Invoke the confirm callback for the Nth picker call.
-- @param item table The item to "select"
-- @param idx number Picker call index (1-based, default 1)
function M.confirm(item, idx)
  idx = idx or 1
  local cb = M.confirm_callbacks[idx]
  if cb then
    -- Create a mock picker handle with a close method
    local mock_picker = { close = function() end }
    cb(mock_picker, item)
  end
end

--- Assert that Snacks.picker was called exactly `count` times.
function M.assert_called(count)
  if count ~= nil and #M.calls ~= count then
    error("Expected " .. tostring(count) .. " Snacks.picker call(s), got " .. #M.calls)
  end
  return #M.calls > 0
end

--- Assert that Snacks.picker was NOT called.
function M.assert_not_called()
  if #M.calls ~= 0 then
    error("Expected no Snacks.picker calls, got " .. #M.calls)
  end
end

--- Reset calls without restoring.
function M.reset()
  M.calls = {}
  M.confirm_callbacks = {}
  M.preview_callbacks = {}
end

return M
