describe("core-utilities", function()
  local Helper

  before_each(function()
    Helper = require("tests.helpers.init")
    Helper.setup({ fn_overrides = { exepath = function(name) return name == "sf" and "/usr/bin/sf" or "" end } })
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
      assert.is_not_nil(text)
      local ok, info, err = JobUtils.parse_version_info(text)
      assert.is_true(ok, "parse_version_info should succeed")
      assert.is_not_nil(info)
      assert.are_equal("2.15.9", info.current_version)
      assert.are_equal("linux-x64", info.platform)
      assert.are_equal("node-v20.10.0", info.node_version)
      assert.is_false(info.has_update)
      assert.is_nil(err)
    end)

    it("detects update warnings", function()
      local text = Helper.load_fixture_text("core-utilities", "version_with_update.txt")
      assert.is_not_nil(text)
      local ok, info, err = JobUtils.parse_version_info(text)
      assert.is_true(ok, "parse_version_info should succeed")
      assert.is_true(info.has_update)
      assert.are_equal("2.16.0", info.available_version)
      assert.are_equal("2.15.9", info.current_version)
    end)

    it("returns nil for unparseable output", function()
      local ok, info, err = JobUtils.parse_version_info("garbage output")
      assert.is_false(ok)
      assert.is_nil(info)
      assert.is_not_nil(err)
    end)

    it("returns nil for nil input", function()
      local ok, info, err = JobUtils.parse_version_info(nil)
      assert.is_false(ok)
      assert.is_nil(info)
      assert.is_not_nil(err)
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
      assert.is_true(type(msg) == "string")
      assert.is_true(#msg > 0)
      -- Should contain key pieces
      assert.is_true(msg:find("2.15.9") ~= nil, "message should contain version")
      assert.is_true(msg:find("linux%-x64") ~= nil, "message should contain platform")
      assert.is_true(msg:find("/usr/bin/sf") ~= nil, "message should contain path")
    end)

    it("returns fallback for nil version info", function()
      local msg = JobUtils.format_version_message(nil, "/usr/bin/sf")
      assert.is_true(type(msg) == "string")
      assert.is_true(#msg > 0)
    end)

    it("returns fallback when current_version is nil", function()
      local msg = JobUtils.format_version_message({}, "/usr/bin/sf")
      assert.is_true(type(msg) == "string")
      assert.is_true(#msg > 0)
    end)
  end)

  describe("JobUtils.validate_json_response", function()
    local JobUtils

    before_each(function()
      JobUtils = require("sf.core.job_utils")
    end)

    it("accepts valid JSON matching expected structure", function()
      local ok, parsed, err = JobUtils.validate_json_response(
        '{"status":0,"result":[]}',
        { result = "table" }
      )
      assert.is_true(ok)
      assert.is_not_nil(parsed)
      assert.are_equal(0, parsed.status)
      assert.is_nil(err)
    end)

    it("rejects JSON missing expected keys", function()
      local ok, parsed, err = JobUtils.validate_json_response(
        '{"status":0}',
        { result = "table" }
      )
      assert.is_false(ok)
      assert.is_nil(parsed)
      assert.is_not_nil(err, "should give error message")
    end)

    it("rejects malformed JSON", function()
      local ok, parsed, err = JobUtils.validate_json_response(
        "not json at all",
        nil
      )
      assert.is_false(ok)
      assert.is_nil(parsed)
      assert.is_not_nil(err, "should give error message")
    end)

    it("accepts valid JSON with no expected structure", function()
      local ok, parsed, err = JobUtils.validate_json_response(
        '{"status":0,"result":[]}',
        nil
      )
      assert.is_true(ok)
      assert.is_not_nil(parsed)
    end)
  end)

  describe("JobUtils.validate_cli_installation", function()
    local JobUtils

    before_each(function()
      JobUtils = require("sf.core.job_utils")
      -- Reset: restore vim.fn.exepath first, then override for this test
      Helper.mock_vim.setup_fn_mocks({ exepath = function(name) return name == "sf" and "/usr/bin/sf" or "" end })
    end)

    it("returns path when CLI is on PATH", function()
      local ok, path, err = JobUtils.validate_cli_installation("sf")
      assert.is_true(ok)
      assert.is_not_nil(path)
      assert.is_nil(err)
    end)

    it("returns error when CLI not found", function()
      -- Mock BOTH exepath AND fnamemodify: exepath returns "" for CLI name,
      -- fnamemodify("", ":p") returns "" to prevent cwd fallback.
      local orig_exepath = vim.fn.exepath
      local orig_modify = vim.fn.fnamemodify
      vim.fn.exepath = function() return "" end
      vim.fn.fnamemodify = function(path, mod)
        if path == "" then return "" end
        return orig_modify(path, mod)
      end
      local ok, path, err = JobUtils.validate_cli_installation("sf")
      vim.fn.exepath = orig_exepath
      vim.fn.fnamemodify = orig_modify
      assert.is_false(ok)
      assert.is_nil(path)
      assert.is_not_nil(err)
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
      assert.is_not_nil(found, "should notify custom error")
      assert.are_equal("Custom error", found.message)
    end)

    it("notifies with default failure message", function()
      JobUtils.handle_cli_error(1, ctx, nil)
      local notify = require("tests.helpers.mock_notify")
      local found = notify.find("Default failure message")
      assert.is_not_nil(found, "should show default message")
    end)
  end)

  describe("State registry", function()
    local State

    before_each(function()
      State = require("sf.core.state")
    end)

    it("start sets busy true", function()
      State.start("deploy")
      assert.is_true(State.is_busy("deploy"))
    end)

    it("finish sets busy false", function()
      State.start("test")
      assert.is_true(State.is_busy("test"))
      State.finish("test")
      assert.is_false(State.is_busy("test"))
    end)

    it("is_busy returns false for unknown kind", function()
      assert.is_false(State.is_busy("nonexistent"))
    end)

    it("multiple kinds are independent", function()
      State.start("deploy")
      State.start("test")
      assert.is_true(State.is_busy("deploy"))
      assert.is_true(State.is_busy("test"))
      State.finish("deploy")
      assert.is_false(State.is_busy("deploy"))
      assert.is_true(State.is_busy("test"))
      State.finish("test")
      assert.is_false(State.is_busy("test"))
    end)
  end)

  describe("Utils.get_sf_root", function()
    local Utils

    before_each(function()
      Utils = require("sf.core.utils")
      -- Create temp dir with sfdx-project.json (the real repo has none)
      local tmpdir = "/tmp/_sf_root_test_" .. vim.fn.localtime()
      vim.fn.mkdir(tmpdir, "p")
      _G._sf_test_tmpdir = tmpdir  -- set early to prevent leak on failure
      local f = io.open(tmpdir .. "/sfdx-project.json", "w")
      if f then f:write("{}"); f:close() end
      Helper.mock_vim.setup_fn_mocks({
        getcwd = function() return tmpdir end,
        fnamemodify = function(path, mod)
          if path == "" then return tmpdir end
          return path
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
      assert.is_true(last_char == "/" or last_char == "\\")
    end)
  end)

  describe("Utils.get_file_name", function()
    local Utils

    before_each(function()
      Utils = require("sf.core.utils")
    end)

    it("extracts class name from path", function()
      local name = Utils.get_file_name("classes/FakeClass.cls")
      assert.are_equal("FakeClass.cls", name)
    end)

    it("extracts trigger name from path", function()
      local name = Utils.get_file_name("triggers/FakeTrigger.trigger")
      assert.are_equal("FakeTrigger.trigger", name)
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
        getcwd = function() return tmpdir end,
        fnamemodify = function(path, mod)
          if path == "" or not path then return tmpdir end
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
      assert.is_not_nil(path)
      assert.is_true(path:find("force%-app/main/default") ~= nil)
    end)

    it("falls back to the first package directory when none is default", function()
      local content = Helper.load_fixture_text("core-utilities", "sfdx-project_no_default.json")
      local f = io.open(tmpdir .. "/sfdx-project.json", "w")
      f:write(content)
      f:close()
      local path = Utils.get_default_package_path()
      assert.is_not_nil(path)
      assert.is_true(path:find("some%-app/main/default") ~= nil)
    end)

    it("returns nil when no sfdx-project.json exists", function()
      local path = Utils.get_default_package_path()
      assert.is_nil(path)
    end)
  end)

  describe("PathUtils", function()
    local PathUtils

    before_each(function()
      PathUtils = require("sf.core.path_utils")
    end)

    it("join combines segments with separator", function()
      local result = PathUtils.join("a", "b", "c")
      assert.are_equal("a/b/c", result)
    end)

    it("get_filename handles Unix paths", function()
      local name = PathUtils.get_filename("classes/FakeClass.cls")
      assert.are_equal("FakeClass.cls", name)
    end)

    it("ensure_trailing_separator adds slash", function()
      local result = PathUtils.ensure_trailing_separator("/proj")
      assert.are_equal("/proj/", result)
    end)

    it("ensure_trailing_separator does not double", function()
      local result = PathUtils.ensure_trailing_separator("/proj/")
      assert.are_equal("/proj/", result)
    end)

    it("to_forward_slashes converts backslashes", function()
      local result = PathUtils.to_forward_slashes("a\\b\\c")
      assert.are_equal("a/b/c", result)
    end)
  end)

  describe("Progress.create_handle", function()
    local Progress

    before_each(function()
      Progress = require("sf.core.progress")
    end)

    it("returns a handle with report and finish methods", function()
      local handle = Progress.create_handle({ title = "Test" })
      assert.is_not_nil(handle)
      assert.is_not_nil(handle.report)
      assert.is_not_nil(handle.finish)
    end)

    it("report and finish execute without throwing", function()
      local handle = Progress.create_handle({ title = "Test" })
      local ok = pcall(function()
        handle.report({ message = "working", percentage = 50 })
        handle.finish()
      end)
      assert.is_true(ok, "report/finish should not throw")
    end)
  end)
end)
