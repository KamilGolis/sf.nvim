--- Tests for Code Analyzer scan module
local helpers = dofile("tests/helpers.lua")
local eq = helpers.expect.equality
local expect = helpers.expect

describe("code-analyzer-scan", function()
  local Helper
  local MockVim
  local MockNotify
  local Const
  local _orig_io_open

  before_each(function()
    Helper = require("tests.helpers.init")
    MockVim = require("tests.helpers.mock_vim")
    MockNotify = require("tests.helpers.mock_notify")
    Const = require("sf.const")

    -- Save original io.open
    _orig_io_open = io.open

    Helper.setup({
      system = true,
      notify = true,
      diagnostic = true,
      fn_overrides = {
        fnamemodify = function(path, modifier)
          if modifier == ":t" then
            return "MyClass.cls"
          end
          return path
        end,
      },
    })

    vim.fn.expand = function(_)
      return "/home/test/project/force-app/main/default/classes/MyClass.cls"
    end
    vim.fn.isdirectory = function(_)
      return 1
    end
    vim.fn.bufnr = function()
      return 1
    end

    -- Mark CLI as checked so await_cli_check passes
    vim.g.sf_cli_checked = true
  end)

  after_each(function()
    -- Restore original io.open
    io.open = _orig_io_open or io.open
    Helper.teardown()
  end)

  describe("Const.get_code_analyzer_args", function()
    it("builds correct args", function()
      local args = Const.get_code_analyzer_args("/path/to/file.cls", "/output.json")
      eq(args[1], "code-analyzer")
      eq(args[2], "run")
      eq(args[3], "-v")
      eq(args[4], "detail")
      eq(args[5], "-f")
      eq(args[6], "/output.json")
      eq(args[7], "-t")
      eq(args[8], "/path/to/file.cls")
    end)
  end)

  describe("scan_current_file", function()
    it("busy guard prevents concurrent scans", function()
      local Scan = require("sf.code_analyzer.scan")
      local State = require("sf.core.state")

      State.start("scan")
      Scan.scan_current_file()

      MockNotify.assert_notified(Const.SF_CLI_MESSAGES.SCAN_ALREADY_RUNNING)
      State.finish("scan")
    end)

    it("empty buffer notifies and exits", function()
      vim.fn.expand = function(_)
        return ""
      end

      local Scan = require("sf.code_analyzer.scan")
      Scan.scan_current_file()

      MockNotify.assert_notified(Const.SF_CLI_MESSAGES.SCAN_NO_FILE)
    end)

    it("CLI non-zero exit notifies error, no diagnostics", function()
      -- Mock vim.system to return exit code 1 (using vim.schedule for coroutine compat)
      local orig_system = vim.system
      vim.system = function(cmd, opts, cb)
        cb = cb or (type(opts) == "function" and opts or nil)
        if cb then
          vim.schedule(function()
            cb({ stdout = "", code = 1 })
          end)
        end
        return { is_closing = function() return true end }
      end

      local Scan = require("sf.code_analyzer.scan")
      Scan.scan_current_file()

      -- Wait for async coroutine to complete (vim.schedule callbacks need event loop)
      vim.wait(500, function()
        return #MockNotify.get_messages() > 0
      end)

      MockNotify.assert_notified("exit code 1")

      -- Check no diagnostics set
      local diag_calls = MockVim.get_diagnostic_set_calls()
      eq(#diag_calls, 0)

      vim.system = orig_system
    end)

    it("successful scan sets warnings in scan namespace", function()
      -- Mock vim.system to exit 0
      local orig_system = vim.system
      vim.system = function(cmd, opts, cb)
        cb = cb or (type(opts) == "function" and opts or nil)
        if cb then
          vim.schedule(function()
            cb({ stdout = "", code = 0 })
          end)
        end
        return { is_closing = function() return true end }
      end

      -- Mock io.open to return the success fixture
      local fixture_data = Helper.load_fixture_text("code-analyzer-scan", "success.json")
      io.open = function(_path, _mode)
        local data = fixture_data
        return {
          read = function()
            return data
          end,
          close = function() end,
        }
      end

      local Config = require("sf.config")
      local options = Config:get_options()
      local Scan = require("sf.code_analyzer.scan")
      Scan.scan_current_file()

      -- Wait for async completion
      vim.wait(500, function()
        return #MockNotify.get_messages() > 0
      end)

      -- Check diagnostic reset called with scan namespace
      local reset_calls = MockVim.get_diagnostic_reset_calls()
      local reset_found = false
      for _, call in ipairs(reset_calls) do
        if call.ns == options.scan_namespace then
          reset_found = true
          break
        end
      end
      eq(reset_found, true)

      -- Check diagnostic set called with scan namespace and correct diagnostics
      local diag_calls = MockVim.get_diagnostic_set_calls()
      eq(#diag_calls, 1)
      eq(diag_calls[1].ns, options.scan_namespace)
      eq(#diag_calls[1].diagnostics, 3)

      -- Check first diagnostic properties
      local first = diag_calls[1].diagnostics[1]
      eq(first.severity, vim.diagnostic.severity.WARN or 2)
      eq(first.lnum, 10) -- startLine 11 - 1
      eq(first.col, 0)
      eq(first.end_lnum, 10)
      eq(first.end_col, 65535)

      -- Check violation count notification
      MockNotify.assert_notified("3 violations")

      vim.system = orig_system
    end)

    it("missing results file notifies error", function()
      local orig_system = vim.system
      vim.system = function(cmd, opts, cb)
        cb = cb or (type(opts) == "function" and opts or nil)
        if cb then
          vim.schedule(function()
            cb({ stdout = "", code = 0 })
          end)
        end
        return { is_closing = function() return true end }
      end

      -- Mock io.open to return nil (file not found)
      io.open = function(_path, _mode)
        return nil
      end

      local Scan = require("sf.code_analyzer.scan")
      Scan.scan_current_file()

      vim.wait(500, function()
        return #MockNotify.get_messages() > 0
      end)

      MockNotify.assert_notified("results file not found")
      vim.system = orig_system
    end)

    it("malformed JSON notifies error", function()
      local orig_system = vim.system
      vim.system = function(cmd, opts, cb)
        cb = cb or (type(opts) == "function" and opts or nil)
        if cb then
          vim.schedule(function()
            cb({ stdout = "", code = 0 })
          end)
        end
        return { is_closing = function() return true end }
      end

      -- Mock io.open to return invalid JSON
      io.open = function(_path, _mode)
        local data = "not valid json"
        return {
          read = function()
            return data
          end,
          close = function() end,
        }
      end

      local Scan = require("sf.code_analyzer.scan")
      Scan.scan_current_file()

      vim.wait(500, function()
        return #MockNotify.get_messages() > 0
      end)

      MockNotify.assert_notified(Const.SF_CLI_MESSAGES.SCAN_JSON_PARSE_FAILED)
      vim.system = orig_system
    end)

    it("empty violations notifies info with 0 count", function()
      local orig_system = vim.system
      vim.system = function(cmd, opts, cb)
        cb = cb or (type(opts) == "function" and opts or nil)
        if cb then
          vim.schedule(function()
            cb({ stdout = "", code = 0 })
          end)
        end
        return { is_closing = function() return true end }
      end

      -- Mock io.open to return empty fixture
      local fixture_data = Helper.load_fixture_text("code-analyzer-scan", "empty.json")
      io.open = function(_path, _mode)
        local data = fixture_data
        return {
          read = function()
            return data
          end,
          close = function() end,
        }
      end

      local Scan = require("sf.code_analyzer.scan")
      Scan.scan_current_file()

      vim.wait(500, function()
        return #MockNotify.get_messages() > 0
      end)

      MockNotify.assert_notified("0 violations")
      vim.system = orig_system
    end)

  describe("scan_resume", function()
    it("reuses cached results and recreates diagnostics", function()
      -- Mock io.open to return the success fixture (simulating cached file)
      local fixture_data = Helper.load_fixture_text("code-analyzer-scan", "success.json")
      io.open = function(_path, _mode)
        local data = fixture_data
        return {
          read = function()
            return data
          end,
          close = function() end,
        }
      end
      -- Mock filereadable to report file exists
      local orig_filereadable = vim.fn.filereadable
      vim.fn.filereadable = function(_path)
        return 1
      end

      local Scan = require("sf.code_analyzer.scan")
      Scan.scan_resume()

      local diag_calls = MockVim.get_diagnostic_set_calls()
      eq(#diag_calls, 1)
      eq(#diag_calls[1].diagnostics, 3)

      MockNotify.assert_notified("3 violations")

      vim.fn.filereadable = orig_filereadable
    end)

    it("notifies error when no cached results exist", function()
      vim.fn.filereadable = function(_path)
        return 0
      end

      local Scan = require("sf.code_analyzer.scan")
      Scan.scan_resume()

      MockNotify.assert_notified(Const.SF_CLI_MESSAGES.SCAN_NO_CACHED_RESULTS)

      -- Verify no diagnostics were set
      local diag_calls = MockVim.get_diagnostic_set_calls()
      eq(#diag_calls, 0)
    end)
  end)
  end)
end)
