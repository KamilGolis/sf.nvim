--- Mock vim.notify and vim.notify_once for testing.
-- Captures all notifications so tests can assert on
-- message content and log levels without showing UI.

local M = {}

-- Captured notifications: { message, level, once? }
M.calls = {}

M._orig = {}
M._orig_once = {}

--- Override vim.notify (and vim.notify_once) with a capture mock.
function M.setup()
  M._orig.vim_notify = vim.notify
  if vim.notify_once then
    M._orig.vim_notify_once = vim.notify_once
  end
  M.calls = {}

  vim.notify = function(message, level)
    table.insert(M.calls, { message = message, level = level, once = false })
  end

  if vim.notify_once then
    vim.notify_once = function(message, level)
      table.insert(M.calls, { message = message, level = level, once = true })
    end
  end
end

--- Restore original notify functions.
function M.restore()
  if M._orig.vim_notify then
    vim.notify = M._orig.vim_notify
  end
  if M._orig.vim_notify_once then
    vim.notify_once = M._orig.vim_notify_once
  end
  M.calls = {}
end

--- Get all notification messages (strings only, stripped of levels).
-- @return table Array of message strings
function M.get_messages()
  local msgs = {}
  for _, call in ipairs(M.calls) do
    table.insert(msgs, call.message)
  end
  return msgs
end

--- Find the first notification whose message contains `substr`.
-- @param substr string Substring to search for
-- @return table|nil The notification call record, or nil
function M.find(substr)
  for _, call in ipairs(M.calls) do
    if type(call.message) == "string" and call.message:find(substr, 1, true) then
      return call
    end
  end
  return nil
end

--- Assert that a notification was sent with message containing `substr`.
-- @param substr string Substring to search for
-- @param level number|nil Optional log level to match
function M.assert_notified(substr, level)
  for _, call in ipairs(M.calls) do
    if type(call.message) == "string" and call.message:find(substr, 1, true) then
      if level == nil or call.level == level then
        return true
      end
    end
  end
  error("Expected notification containing: " .. tostring(substr)
    .. "\nGot: " .. vim.inspect(M.calls), 2)
end

--- Assert no notification was sent.
function M.assert_no_notification()
  assert.are_equal(0, #M.calls, "Expected no notifications, got " .. #M.calls)
end

--- Get the count of captured notifications.
function M.count()
  return #M.calls
end

--- Reset captured calls without restoring.
function M.reset()
  M.calls = {}
end

return M
