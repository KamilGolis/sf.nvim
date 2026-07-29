--- Tests for Anonymous Apex execution module
local helpers = dofile("tests/helpers.lua")
local eq = helpers.expect.equality
local expect = helpers.expect

describe("apex-execute", function()
  local Helper

  before_each(function()
    Helper = require("tests.helpers.init")
    local tmpdir = "/tmp/_sf_apex_" .. vim.fn.localtime() .. "_" .. vim.fn.rand()
    vim.fn.mkdir(tmpdir, "p")
    _G._sf_apex_tmpdir = tmpdir

    Helper.setup({
      fn_overrides = {
        exepath = function(name)
          return name == "sf" and "/usr/bin/sf" or ""
        end,
        fnamemodify = function(path)
          return path
        end,
        nvim_buf_get_name = function()
          return tmpdir .. "/test.apex"
        end,
        getcwd = function()
          return tmpdir
        end,
      },
    })
  end)

  after_each(function()
    if _G._sf_apex_tmpdir then
      pcall(vim.fn.delete, _G._sf_apex_tmpdir, "rf")
      _G._sf_apex_tmpdir = nil
    end
    Helper.teardown()
  end)

  describe("Const.get_apex_run_args", function()
    local Const

    before_each(function()
      Const = require("sf.const")
    end)

    it("returns apex run command with file and api version", function()
      local args = Const.get_apex_run_args("/tmp/test.apex", "65.0")
      eq("apex", args[1])
      eq("run", args[2])
      eq("--file", args[3])
      eq("/tmp/test.apex", args[4])
      eq("--api-version", args[5])
      eq("65.0", args[6])
      eq("--json", args[7])
    end)

    it("includes --target-org when provided", function()
      local args = Const.get_apex_run_args("/tmp/test.apex", "65.0", "user@example.com")
      -- Find the target-org flag
      local found_idx = nil
      for i, v in ipairs(args) do
        if v == "--target-org" then
          found_idx = i
          break
        end
      end
      expect.no_equality(found_idx, nil)
      eq("user@example.com", args[found_idx + 1])
    end)

    it("omits --target-org when nil", function()
      local args = Const.get_apex_run_args("/tmp/test.apex", "65.0")
      for _, v in ipairs(args) do
        if v == "--target-org" then
          error("should not contain --target-org")
        end
      end
      -- If we get here, the test passes
      eq(true, true)
    end)
  end)

  describe("Execute:_parse_response", function()
    local Execute

    before_each(function()
      Execute = require("sf.apex.execute")
    end)

    it("parses success JSON", function()
      local json = Helper.load_fixture_text("apex-execute", "apex_run_success.json")
      expect.no_equality(json, nil)
      local result = Execute:_parse_response(json)
      eq(result.success, true)
      expect.match(result.logs, "USER_DEBUG")
    end)

    it("parses compile error JSON", function()
      local json = Helper.load_fixture_text("apex-execute", "apex_run_compile_error.json")
      expect.no_equality(json, nil)
      local result = Execute:_parse_response(json)
      eq(result.success, false)
      expect.no_equality(result.error, nil)
      expect.match(result.error.message, "Extra '<EOF>'")
      eq(result.error.line, 1)
      eq(result.error.column, 20)
    end)

    it("parses runtime error JSON", function()
      local json = Helper.load_fixture_text("apex-execute", "apex_run_runtime_error.json")
      expect.no_equality(json, nil)
      local result = Execute:_parse_response(json)
      eq(result.success, false)
      expect.no_equality(result.error, nil)
      expect.match(result.error.message, "NullPointerException")
      eq(result.error.line, 5)
      eq(result.error.column, 1)
    end)

    it("handles malformed JSON", function()
      local json = "not json at all"
      local result = Execute:_parse_response(json)
      eq(result.success, false)
      eq(result.error.message, "Failed to parse response")
    end)

    it("handles unexpected structure", function()
      local json = '{"status":0,"result":{"success":false}}'
      local result = Execute:_parse_response(json)
      eq(result.success, false)
      eq(result.error.message, "Unexpected response from apex run")
    end)
  end)

  describe("Execute:execute_file", function()
    local Execute
    local MockNotify
    local MockVim

    before_each(function()
      -- Create the temp dir structure for org config
      local tmpdir = _G._sf_apex_tmpdir
      vim.fn.mkdir(tmpdir .. "/.sf", "p")

      -- Write sfdx-project.json for get_sf_root()
      local proj_file = io.open(tmpdir .. "/sfdx-project.json", "w")
      if proj_file then
        proj_file:write(Helper.load_fixture_text("apex-execute", "sfdx-project.json") or "{}")
        proj_file:close()
      end

      -- Write .sf/config.json for check_default_org
      local config = io.open(tmpdir .. "/.sf/config.json", "w")
      if config then
        config:write('{"target-org": "test-org@example.com"}')
        config:close()
      end

      vim.g.sf_cli_checked = true

      Execute = require("sf.apex.execute")
      MockNotify = require("tests.helpers.mock_notify")
      MockVim = require("tests.helpers.mock_vim")
    end)

    it("rejects non-.apex files", function()
      Execute:execute_file("/tmp/test.cls")
      local messages = MockNotify.get_messages()
      local found = false
      for _, msg in ipairs(messages) do
        if msg:match("Not an %.apex file") then
          found = true
          break
        end
      end
      eq(found, true, "Should notify 'Not an .apex file'")
    end)

    it("prevents concurrent execution", function()
      local State = require("sf.core.state")
      State.start("apex")
      Execute:execute_file("/tmp/test.apex")
      local messages = MockNotify.get_messages()
      local found = false
      for _, msg in ipairs(messages) do
        if msg:match("already in progress") then
          found = true
          break
        end
      end
      eq(found, true, "Should notify 'already in progress'")
      State.finish("apex")
    end)

    it("uses scripts dir file directly when file_path is in scripts_dir", function()
      local tmpdir = _G._sf_apex_tmpdir
      local scripts_dir = tmpdir .. "/scripts"
      vim.fn.mkdir(scripts_dir, "p")

      -- Write sfdx-project.json (needed for get_sf_root)
      -- Scripts dir detection: get_sf_root() returns tmpdir, so scripts_dir = tmpdir/scripts
      local file_path = scripts_dir .. "/test.apex"
      local f = io.open(file_path, "w")
      if f then
        f:write("System.debug('test');")
        f:close()
      end

      Execute:execute_file(file_path)
      Helper.wait_for(function()
        return #MockVim.calls.system > 0
      end)

      local call = MockVim.calls.system[1]
      expect.no_equality(call, nil)
      local args_str = table.concat(call.args, " ")
      expect.match(args_str, "apex run")
      -- Should reference the original file, not a temp file
      expect.match(args_str, file_path)
    end)

    it("copies non-scripts file to temp", function()
      local tmpdir = _G._sf_apex_tmpdir
      local scripts_dir = tmpdir .. "/scripts"
      vim.fn.mkdir(scripts_dir, "p")
      local file_path = tmpdir .. "/random.apex"
      local f = io.open(file_path, "w")
      if f then
        f:write("System.debug('outside');")
        f:close()
      end
      -- Also set current buffer to return this file's content
      vim.bo[0].swapfile = false
      vim.api.nvim_buf_set_lines(0, 0, -1, false, { "System.debug('outside');" })

      Execute:execute_file(file_path)
      Helper.wait_for(function()
        return #MockVim.calls.system > 0
      end)

      local call = MockVim.calls.system[1]
      expect.no_equality(call, nil)
      local args_str = table.concat(call.args, " ")
      -- Should reference a temp file (under apex_temp_dir)
      local apex_temp = Config and Config:get_options() and Config:get_options().apex_temp_dir or ""
      if apex_temp and apex_temp ~= "" then
        -- If config resolves, check for the temp dir
        expect.match(args_str, ".apex")
      else
        -- Fallback: just check it's not the original file
        expect.no_match(args_str, file_path)
      end
    end)
  end)

  describe("Execute:execute_new", function()
    local Execute
    local MockNotify

    before_each(function()
      local tmpdir = _G._sf_apex_tmpdir
      local proj_file = io.open(tmpdir .. "/sfdx-project.json", "w")
      if proj_file then
        proj_file:write("{}")
        proj_file:close()
      end
      Execute = require("sf.apex.execute")
      MockNotify = require("tests.helpers.mock_notify")
    end)

    it("creates a new apex file in scripts directory", function()
      local tmpdir = _G._sf_apex_tmpdir
      Execute:execute_new()

      -- Check that a .apex file was created in scripts/
      local scripts_dir = tmpdir .. "/scripts"
      local entries = vim.fn.readdir(scripts_dir) or {}
      local apex_files = {}
      for _, entry in ipairs(entries) do
        if entry:match("%.apex$") then
          table.insert(apex_files, entry)
        end
      end
      eq(#apex_files, 1, "Should create one .apex file")
      local messages = MockNotify.get_messages()
      local found_create = false
      for _, msg in ipairs(messages) do
        if msg:match("Created:") then
          found_create = true
          break
        end
      end
      eq(found_create, true, "Should notify 'Created:'")
    end)

    it("creates scripts directory when missing", function()
      local tmpdir = _G._sf_apex_tmpdir
      local scripts_dir = tmpdir .. "/scripts"
      if vim.fn.isdirectory(scripts_dir) == 1 then
        vim.fn.delete(scripts_dir, "rf")
      end
      -- Ensure scripts dir doesn't exist
      eq(vim.fn.isdirectory(scripts_dir), 0, "scripts dir should not exist initially")
      Execute:execute_new()
      eq(vim.fn.isdirectory(scripts_dir), 1, "scripts dir should be created")
    end)
  end)

  describe("Execute:execute_cleanup", function()
    local Execute
    local MockNotify

    before_each(function()
      Execute = require("sf.apex.execute")
      Config = require("sf.config")
      MockNotify = require("tests.helpers.mock_notify")
    end)

    it("deletes apex_temp_dir and recreates it", function()
      local apex_temp = Config:get_options().apex_temp_dir
      vim.fn.mkdir(apex_temp, "p")
      local test_file = apex_temp .. "/test.apex"
      local f = io.open(test_file, "w")
      if f then
        f:write("test")
        f:close()
      end
      eq(vim.fn.filereadable(test_file), 1, "test file should exist before cleanup")
      Execute:execute_cleanup()
      eq(vim.fn.isdirectory(apex_temp), 1, "apex_temp_dir should exist after cleanup")
      eq(vim.fn.filereadable(test_file), 0, "test file should be deleted")
    end)

    it("does nothing when apex_temp_dir does not exist", function()
      local apex_temp = Config:get_options().apex_temp_dir
      if vim.fn.isdirectory(apex_temp) == 1 then
        vim.fn.delete(apex_temp, "rf")
      end
      Execute:execute_cleanup()
      local messages = MockNotify.get_messages()
      local found_cleanup = false
      for _, msg in ipairs(messages) do
        if msg:match("Nothing to clean") then
          found_cleanup = true
          break
        end
      end
      eq(found_cleanup, true, "Should notify 'Nothing to clean'")
    end)
  end)

  describe("Picker.create_scripts_picker", function()
    local Picker

    before_each(function()
      local snacks = require("tests.helpers.mock_snacks")
      snacks.setup()
      Picker = require("sf.apex.picker")
    end)

    it("creates picker with correct title", function()
      local MockSnacks = require("tests.helpers.mock_snacks")
      local items = {
        { file_path = "/tmp/test.apex", file_name = "test.apex", content = "System.debug('x');" },
      }
      Picker.create_scripts_picker(items, function() end)
      local calls = MockSnacks.calls
      eq(#calls, 1)
      eq(calls[1].title, "Apex Scripts")
    end)

    it("passes items to picker", function()
      local MockSnacks = require("tests.helpers.mock_snacks")
      local items = {
        { file_path = "/tmp/a.apex", file_name = "a.apex", content = "test1" },
        { file_path = "/tmp/b.apex", file_name = "b.apex", content = "test2" },
      }
      Picker.create_scripts_picker(items, function() end)
      local calls = MockSnacks.calls
      eq(#calls, 1)
      eq(#calls[1].items, 2)
      eq(calls[1].items[1].file_name, "a.apex")
      eq(calls[1].items[2].file_name, "b.apex")
    end)

    it("format returns icon and filename", function()
      local MockSnacks = require("tests.helpers.mock_snacks")
      local items = {
        { file_path = "/tmp/t.apex", file_name = "t.apex", content = "" },
      }
      Picker.create_scripts_picker(items, function() end)
      local calls = MockSnacks.calls
      local format_fn = calls[1].format
      expect.no_equality(format_fn, nil)
      local display = format_fn(items[1])
      eq(#display, 1)
      expect.match(display[1][1], "t.apex")
    end)

    it("confirm closes picker and calls callback", function()
      local MockSnacks = require("tests.helpers.mock_snacks")
      local callback_called = false
      local callback_item = nil
      local items = {
        { file_path = "/tmp/t.apex", file_name = "t.apex", content = "" },
      }
      Picker.create_scripts_picker(items, function(item)
        callback_called = true
        callback_item = item
      end)
      local confirm_fn = MockSnacks.confirm_callbacks[1]
      expect.no_equality(confirm_fn, nil)
      confirm_fn({ close = function() end }, items[1])
      eq(callback_called, true)
      eq(callback_item.file_name, "t.apex")
    end)

    it("shows notification for empty items", function()
      local MockNotify = require("tests.helpers.mock_notify")
      Picker.create_scripts_picker({}, function() end)
      local messages = MockNotify.get_messages()
      local found = false
      for _, msg in ipairs(messages) do
        if msg:match("No scripts available") then
          found = true
          break
        end
      end
      eq(found, true, "Should notify 'No scripts available'")
    end)

    it("preview writes content to ctx.buf", function()
      local MockSnacks = require("tests.helpers.mock_snacks")
      local items = {
        { file_path = "/tmp/t.apex", file_name = "t.apex", content = "hello\nworld" },
      }
      Picker.create_scripts_picker(items, function() end)
      local preview_fn = MockSnacks.preview_callbacks[1]
      expect.no_equality(preview_fn, nil)

      local test_buf = vim.api.nvim_create_buf(false, true)
      local ctx = { buf = test_buf, item = items[1], items = items, idx = 1 }
      local result = preview_fn(ctx)
      eq(result, true, "preview should return true")

      local lines = vim.api.nvim_buf_get_lines(test_buf, 0, -1, false)
      eq(#lines, 2)
      eq(lines[1], "hello")
      eq(lines[2], "world")

      vim.api.nvim_buf_delete(test_buf, { force = true })
    end)
  end)
end)
