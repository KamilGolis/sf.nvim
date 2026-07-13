local helpers = dofile("tests/helpers.lua")
local eq = helpers.expect.equality
local expect = helpers.expect

describe("core-utilities", function()
  local Helper

  before_each(function()
    Helper = require("tests.helpers.init")
    Helper.setup({
      fn_overrides = {
        exepath = function(name)
          return name == "sf" and "/usr/bin/sf" or ""
        end,
      },
    })
  end)

  after_each(function()
    Helper.teardown()
  end)

  describe("JobUtils.parse_version_info", function()
    local JobUtils

    before_each(function()
      JobUtils = require("sf.core.job_utils")
      Const = require("sf.const")
    end)

    it("parses plain version output", function()
      local text = Helper.load_fixture_text("core-utilities", "version_output.txt")
      expect.no_equality(text, nil)
      local ok, info, err = JobUtils.parse_version_info(text)
      eq(ok, true, "parse_version_info should succeed")
      expect.no_equality(info, nil)
      eq("2.15.9", info.current_version)
      eq("linux-x64", info.platform)
      eq("node-v20.10.0", info.node_version)
      eq(info.has_update, false)
      eq(err, nil)
    end)

    it("detects update warnings", function()
      local text = Helper.load_fixture_text("core-utilities", "version_with_update.txt")
      expect.no_equality(text, nil)
      local ok, info, err = JobUtils.parse_version_info(text)
      eq(ok, true, "parse_version_info should succeed")
      eq(info.has_update, true)
      eq("2.16.0", info.available_version)
      eq("2.15.9", info.current_version)
    end)

    it("returns nil for unparseable output", function()
      local ok, info, err = JobUtils.parse_version_info("garbage output")
      eq(ok, false)
      eq(info, nil)
      expect.no_equality(err, nil)
    end)

    it("returns nil for nil input", function()
      local ok, info, err = JobUtils.parse_version_info(nil)
      eq(ok, false)
      eq(info, nil)
      expect.no_equality(err, nil)
    end)
  end)

  describe("JobUtils.format_version_message", function()
    local JobUtils

    before_each(function()
      JobUtils = require("sf.core.job_utils")
    end)

    it("formats a valid version info", function()
      local msg = JobUtils.format_version_message(
        { current_version = "2.15.9", platform = "linux-x64", node_version = "node-v20.10.0" },
        "/usr/bin/sf"
      )
      eq(type(msg), "string")
      eq(#msg > 0, true)
      -- Should contain key pieces
      expect.match(msg, "2.15.9", "message should contain version")
      expect.match(msg, "linux%-x64", "message should contain platform")
      expect.match(msg, "/usr/bin/sf", "message should contain path")
    end)

    it("returns fallback for nil version info", function()
      local msg = JobUtils.format_version_message(nil, "/usr/bin/sf")
      eq(type(msg), "string")
      eq(#msg > 0, true)
    end)

    it("returns fallback when current_version is nil", function()
      local msg = JobUtils.format_version_message({}, "/usr/bin/sf")
      eq(type(msg), "string")
      eq(#msg > 0, true)
    end)
  end)

  describe("JobUtils.validate_json_response", function()
    local JobUtils

    before_each(function()
      JobUtils = require("sf.core.job_utils")
    end)

    it("accepts valid JSON matching expected structure", function()
      local ok, parsed, err = JobUtils.validate_json_response('{"status":0,"result":[]}', { result = "table" })
      eq(ok, true)
      expect.no_equality(parsed, nil)
      eq(0, parsed.status)
      eq(err, nil)
    end)

    it("rejects JSON missing expected keys", function()
      local ok, parsed, err = JobUtils.validate_json_response('{"status":0}', { result = "table" })
      eq(ok, false)
      eq(parsed, nil)
      expect.no_equality(err, nil, "should give error message")
    end)

    it("rejects malformed JSON", function()
      local ok, parsed, err = JobUtils.validate_json_response("not json at all", nil)
      eq(ok, false)
      eq(parsed, nil)
      expect.no_equality(err, nil, "should give error message")
    end)

    it("accepts valid JSON with no expected structure", function()
      local ok, parsed, err = JobUtils.validate_json_response('{"status":0,"result":[]}', nil)
      eq(ok, true)
      expect.no_equality(parsed, nil)
    end)
  end)

  describe("JobUtils.validate_cli_installation", function()
    local JobUtils

    before_each(function()
      JobUtils = require("sf.core.job_utils")
      -- Reset: restore vim.fn.exepath first, then override for this test
      Helper.mock_vim.setup_fn_mocks({
        exepath = function(name)
          return name == "sf" and "/usr/bin/sf" or ""
        end,
      })
    end)

    it("returns path when CLI is on PATH", function()
      local ok, path, err = JobUtils.validate_cli_installation("sf")
      eq(ok, true)
      expect.no_equality(path, nil)
      eq(err, nil)
    end)

    it("returns error when CLI not found", function()
      -- Mock BOTH exepath AND fnamemodify: exepath returns "" for CLI name,
      -- fnamemodify("", ":p") returns "" to prevent cwd fallback.
      local orig_exepath = vim.fn.exepath
      local orig_modify = vim.fn.fnamemodify
      vim.fn.exepath = function()
        return ""
      end
      vim.fn.fnamemodify = function(path, mod)
        if path == "" then
          return ""
        end
        return orig_modify(path, mod)
      end
      local ok, path, err = JobUtils.validate_cli_installation("sf")
      vim.fn.exepath = orig_exepath
      vim.fn.fnamemodify = orig_modify
      eq(ok, false)
      eq(path, nil)
      expect.no_equality(err, nil)
    end)
  end)

  describe("JobUtils.handle_cli_error", function()
    local JobUtils
    local ctx

    before_each(function()
      JobUtils = require("sf.core.job_utils")
      ctx = {
        failure_message = "Default failure message",
        handle = {
          report = function() end,
          finish = function() end,
        },
      }
    end)

    it("notifies with custom message", function()
      JobUtils.handle_cli_error(1, ctx, "Custom error")
      local notify = require("tests.helpers.mock_notify")
      local found = notify.find("Custom error")
      expect.no_equality(found, nil, "should notify custom error")
      eq("Custom error", found.message)
    end)

    it("notifies with default failure message", function()
      JobUtils.handle_cli_error(1, ctx, nil)
      local notify = require("tests.helpers.mock_notify")
      local found = notify.find("Default failure message")
      expect.no_equality(found, nil, "should show default message")
    end)
  end)

  describe("State registry", function()
    local State

    before_each(function()
      State = require("sf.core.state")
    end)

    it("start sets busy true", function()
      State.start("deploy")
      eq(State.is_busy("deploy"), true)
    end)

    it("finish sets busy false", function()
      State.start("test")
      eq(State.is_busy("test"), true)
      State.finish("test")
      eq(State.is_busy("test"), false)
    end)

    it("is_busy returns false for unknown kind", function()
      eq(State.is_busy("nonexistent"), false)
    end)

    it("multiple kinds are independent", function()
      State.start("deploy")
      State.start("test")
      eq(State.is_busy("deploy"), true)
      eq(State.is_busy("test"), true)
      State.finish("deploy")
      eq(State.is_busy("deploy"), false)
      eq(State.is_busy("test"), true)
      State.finish("test")
      eq(State.is_busy("test"), false)
    end)
  end)

  describe("Utils.get_sf_root", function()
    local Utils

    before_each(function()
      Utils = require("sf.core.utils")
      -- Create temp dir with sfdx-project.json (the real repo has none)
      local tmpdir = "/tmp/_sf_root_test_" .. vim.fn.localtime()
      vim.fn.mkdir(tmpdir, "p")
      _G._sf_test_tmpdir = tmpdir -- set early to prevent leak on failure
      local f = io.open(tmpdir .. "/sfdx-project.json", "w")
      if f then
        f:write("{}")
        f:close()
      end
      Helper.mock_vim.setup_fn_mocks({
        getcwd = function()
          return tmpdir
        end,
        fnamemodify = function(path, mod)
          if path == "" then
            return tmpdir
          end
          return path
        end,
        nvim_buf_get_name = function()
          return tmpdir .. "/force-app/main/default/classes/FakeClass.cls"
        end,
      })
      _G._sf_test_tmpdir = tmpdir
    end)
    after_each(function()
      if _G._sf_test_tmpdir then
        vim.fn.delete(_G._sf_test_tmpdir, "rf")
        _G._sf_test_tmpdir = nil
      end
    end)

    it("returns path with trailing separator", function()
      local root = Utils.get_sf_root()
      local last_char = root:sub(-1)
      eq(last_char == "/" or last_char == "\\", true)
    end)
  end)

  describe("Utils.get_file_name", function()
    local Utils

    before_each(function()
      Utils = require("sf.core.utils")
    end)

    it("extracts class name from path", function()
      local name = Utils.get_file_name("classes/FakeClass.cls")
      eq("FakeClass.cls", name)
    end)

    it("extracts trigger name from path", function()
      local name = Utils.get_file_name("triggers/FakeTrigger.trigger")
      eq("FakeTrigger.trigger", name)
    end)
  end)

  describe("Utils.get_default_package_path", function()
    local Utils
    local tmpdir

    before_each(function()
      Utils = require("sf.core.utils")
      tmpdir = "/tmp/_sf_pkg_test_" .. vim.fn.localtime() .. "_" .. vim.fn.rand()
      vim.fn.mkdir(tmpdir, "p")
      _G._sf_pkg_tmpdir = tmpdir
      Helper.mock_vim.setup_fn_mocks({
        getcwd = function()
          return tmpdir
        end,
        fnamemodify = function(path, mod)
          if path == "" or not path then
            return tmpdir
          end
          return path
        end,
      })
    end)

    after_each(function()
      if _G._sf_pkg_tmpdir then
        vim.fn.delete(_G._sf_pkg_tmpdir, "rf")
        _G._sf_pkg_tmpdir = nil
      end
    end)

    it("returns the default package directory path when sfdx-project.json present", function()
      local content = Helper.load_fixture_text("core-utilities", "sfdx-project.json")
      local f = io.open(tmpdir .. "/sfdx-project.json", "w")
      f:write(content)
      f:close()
      local path = Utils.get_default_package_path()
      expect.no_equality(path, nil)
      expect.match(path, "force%-app/main/default")
    end)

    it("falls back to the first package directory when none is default", function()
      local content = Helper.load_fixture_text("core-utilities", "sfdx-project_no_default.json")
      local f = io.open(tmpdir .. "/sfdx-project.json", "w")
      f:write(content)
      f:close()
      local path = Utils.get_default_package_path()
      expect.no_equality(path, nil)
      expect.match(path, "some%-app/main/default")
    end)

    it("returns nil when no sfdx-project.json exists", function()
      local path = Utils.get_default_package_path()
      eq(path, nil)
    end)
  end)

  describe("PathUtils", function()
    local PathUtils

    before_each(function()
      PathUtils = require("sf.core.path_utils")
    end)

    it("join combines segments with separator", function()
      local result = PathUtils.join("a", "b", "c")
      eq("a/b/c", result)
    end)

    it("get_filename handles Unix paths", function()
      local name = PathUtils.get_filename("classes/FakeClass.cls")
      eq("FakeClass.cls", name)
    end)

    it("ensure_trailing_separator adds slash", function()
      local result = PathUtils.ensure_trailing_separator("/proj")
      eq("/proj/", result)
    end)

    it("ensure_trailing_separator does not double", function()
      local result = PathUtils.ensure_trailing_separator("/proj/")
      eq("/proj/", result)
    end)

    it("to_forward_slashes converts backslashes", function()
      local result = PathUtils.to_forward_slashes("a\\b\\c")
      eq("a/b/c", result)
    end)
  end)

  describe("Progress.create_handle", function()
    local Progress

    before_each(function()
      Progress = require("sf.core.progress")
    end)

    it("returns a handle with report and finish methods", function()
      local handle = Progress.create_handle({ title = "Test" })
      expect.no_equality(handle, nil)
      expect.no_equality(handle.report, nil)
      expect.no_equality(handle.finish, nil)
    end)

    it("report and finish execute without throwing", function()
      local handle = Progress.create_handle({ title = "Test" })
      local ok = pcall(function()
        handle.report({ message = "working", percentage = 50 })
        handle.finish()
      end)
      eq(ok, true, "report/finish should not throw")
    end)
  end)
end)
