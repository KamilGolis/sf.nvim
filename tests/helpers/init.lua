--- Test helper initialization module.
-- Re-exports all mocks and provides shared setup/teardown
-- utilities used across all test specs.

local M = {}

-- Re-export mock modules
M.mock_vim = require("tests.helpers.mock_vim")
M.mock_snacks = require("tests.helpers.mock_snacks")
M.mock_notify = require("tests.helpers.mock_notify")
M.fixtures = require("tests.helpers.fixtures")

--- State: track which modules have been fully set up to avoid double-setup.
local setup_state = {
  mocks_initialized = false,
}

--- Reset module-level singletons that accumulate state across tests.
-- Clears State.busy map, re-requires Config to get fresh options.
-- Does NOT affect mock state (mock call records are reset separately).
function M.reset_module_state()
  -- Reset State busy registry
  local State = require("sf.core.state")
  if State._test_reset then
    State._test_reset()
  else
    -- Directly clear the module-local busy table via debug access
    -- This is a test-only escape hatch.
    for _, kind in ipairs({ "deploy", "test", "retrieve", "diff" }) do
      State.finish(kind)
    end
  end

  -- Re-require Config to get fresh options (cache paths etc.)
  -- vusted's require cache is per-test-run, so this returns a fresh object.
  local Config = require("sf.config")
  Config:setup({}) -- setup with defaults, no user overrides in tests
end

--- Full test setup: install mocks and reset module state.
-- Call in before_each.
-- @param opts table Optional overrides passed to mock_vim.setup
--   - fn_overrides: table of vim.fn stubs
--   - system: boolean (default true)
--   - notify: boolean (default true)
--   - uv: table of uv overrides
function M.setup(opts)
  opts = opts or {}
  M.mock_vim.setup({
    system = opts.system ~= false,
    notify = opts.notify ~= false,
    fn_overrides = opts.fn_overrides,
    uv = opts.uv,
  })
  M.mock_snacks.setup()
  M.mock_notify.setup()
  M.reset_module_state()
  setup_state.mocks_initialized = true
end

--- Standard per-test teardown.
function M.teardown()
  -- Drain pending scheduled vim.system callbacks (the system mock fires
  -- callbacks via vim.schedule) so they don't leak into the next test.
  pcall(vim.wait, 30, function()
    return false
  end)
  M.mock_vim.restore()
  M.mock_snacks.restore()
  M.mock_notify.restore()
  setup_state.mocks_initialized = false
end

--- Wait for a condition to become true (for async/scheduled callbacks).
-- Polls with vim.wait inside the headless nvim event loop.
-- @param fn function Condition to evaluate
-- @param timeout number Max wait in ms (default 1000)
-- @return boolean True if condition was met
function M.wait_for(fn, timeout)
  timeout = timeout or 1000
  local ok = pcall(vim.wait, timeout, fn, 10)
  return ok
end

--- Run a function inside vim.schedule and wait for it to complete.
-- Useful when a module uses vim.schedule internally and tests
-- need to wait for the scheduled callback.
-- @param fn function Function to schedule
function M.scheduled(fn)
  vim.schedule(fn)
  M.wait_for(function()
    return true
  end, 100) -- yield to let the event loop run
end

--- Read a fixture file as JSON (convenience).
-- @param capability string
-- @param filename string
-- @return table|nil
function M.load_fixture_json(capability, filename)
  return M.fixtures.load_json(capability, filename)
end

--- Read a fixture file as text (convenience).
-- @param capability string
-- @param filename string
-- @return string|nil
function M.load_fixture_text(capability, filename)
  return M.fixtures.load_text(capability, filename)
end

return M
