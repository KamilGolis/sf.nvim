local helpers = dofile("tests/helpers.lua")
local eq = helpers.expect.equality
local expect = helpers.expect
local Helper

--- Helper: create a mock vim.system that captures stdout and exit code.
local function make_mock_system(mock_stdout, code)
  return function(cmd, opts, on_exit)
    opts = opts or {}
    local stdout_lines = type(mock_stdout) == "table" and mock_stdout or { mock_stdout or "" }
    local job_handle = {
      code = code or 0,
      _stdout = stdout_lines,
      result = function(self)
        return self._stdout
      end,
    }
    if on_exit then
      vim.schedule(function()
        on_exit(job_handle, code or 0)
      end)
    end
    return job_handle
  end
end

describe("async coroutine framework", function()
  before_each(function()
    Helper = require("tests.helpers.init")
    Helper.setup({
      fn_overrides = {
        exepath = function(cmd)
          return "/usr/local/bin/" .. cmd
        end,
      },
    })
  end)

  after_each(function()
    Helper.teardown()
  end)

  it("await_system returns stdout and exit code", function()
    local async = require("sf.core.async")

    local result = Helper.run_async(function()
      return async.await_system("sf", { "--version" })
    end)

    -- result = {stdout, exit_code}
    eq(type(result[1]), "string")
    eq(result[2], 0)
  end)

  it("await_json returns parsed table for valid JSON", function()
    local async = require("sf.core.async")
    vim.system = make_mock_system('{"status": 0, "result": "ok"}', 0)

    local result = Helper.run_async(function()
      return async.await_json("sf", { "org", "list", "--json" })
    end)

    eq(type(result[1]), "table")
    eq(result[1].status, 0)
    eq(result[1].result, "ok")
    eq(result[2], nil)
  end)

  it("await_json returns nil, error for invalid JSON", function()
    local async = require("sf.core.async")
    vim.system = make_mock_system("not valid json", 0)

    local result = Helper.run_async(function()
      return async.await_json("sf", { "org", "list", "--json" })
    end)

    eq(result[1], nil)
    eq(result[2], "Failed to parse JSON output")
  end)

  it("await_json returns nil, error for non-zero exit", function()
    local async = require("sf.core.async")
    vim.system = make_mock_system("Command failed", 1)

    local result = Helper.run_async(function()
      return async.await_json("sf", { "org", "list", "--json" })
    end)

    eq(result[1], nil)
    eq(result[2], "Command failed")
  end)

  it("await_cli_check returns true when sf is cached", function()
    local async = require("sf.core.async")

    vim.g.sf_cli_checked = true

    local result = Helper.run_async(function()
      return async.await_cli_check()
    end)

    eq(result[1], true)
  end)

  it("async wrapper catches errors gracefully", function()
    local async = require("sf.core.async")

    local notified_error = nil
    local orig_notify = vim.notify
    vim.notify = function(msg, level)
      if level == vim.log.levels.ERROR then
        notified_error = msg
      end
    end

    async.async(function()
      error("test crash inside coroutine")
    end)()

    vim.notify = orig_notify
    expect.no_equality(notified_error, nil)
    expect.match(notified_error, "test crash inside coroutine")
  end)
end)
