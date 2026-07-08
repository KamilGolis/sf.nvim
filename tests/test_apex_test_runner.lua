local helpers = dofile("tests/helpers.lua")
local eq = helpers.expect.equality
local expect = helpers.expect

describe("apex-test-runner", function()
  local Helper

  before_each(function()
    Helper = require("tests.helpers.init")
    Helper.setup({
      fn_overrides = {
        exepath = function(n)
          return n == "sf" and "/usr/bin/sf" or ""
        end,
      },
    })
  end)

  after_each(function()
    Helper.teardown()
  end)

  describe("test result fixture shapes", function()
    it("test_success.json has expected summary shape", function()
      local json = Helper.load_fixture_text("apex-test-runner", "test_success.json")
      local ok, parsed = pcall(vim.json.decode, json)
      eq(ok, true)
      eq(0, parsed.result.summary.failing)
      eq("Passed", parsed.result.summary.outcome)
    end)
    it("test_with_failures.json has expected summary shape", function()
      local json = Helper.load_fixture_text("apex-test-runner", "test_with_failures.json")
      local ok, parsed = pcall(vim.json.decode, json)
      eq(ok, true)
      eq(1, parsed.result.summary.failing)
      eq("Failed", parsed.result.summary.outcome)
    end)
  end)

  describe("Const apex test arg builders", function()
    local Const

    before_each(function()
      Const = require("sf.const")
    end)

    it("get_apex_test_class_args builds full vector with coverage flag", function()
      local args = Const.get_apex_test_class_args("FakeTestClass", true)
      eq("apex", args[1])
      eq("run", args[2])
      eq("test", args[3])
      eq("-y", args[4])
      eq("-n", args[5])
      eq("FakeTestClass", args[6])
      eq("--json", args[7])
      eq("-c", args[8])
      eq(8, #args)
    end)

    it("get_apex_test_class_args omits coverage flag when not requested", function()
      local args = Const.get_apex_test_class_args("FakeTestClass", false)
      eq("FakeTestClass", args[6])
      eq(vim.tbl_contains(args, "-c"), false)
      eq(7, #args)
    end)

    it("get_apex_test_method_args includes method name", function()
      local args = Const.get_apex_test_method_args("FakeTestClass.testMethod", false)
      eq("apex", args[1])
      eq("run", args[2])
      eq("test", args[3])
      eq("-y", args[4])
      eq("-t", args[5])
      eq("FakeTestClass.testMethod", args[6])
      eq("--json", args[7])
      eq(7, #args)
    end)

    it("get_apex_log_list_args appends target org", function()
      local args = Const.get_apex_log_list_args("test-user@example.com")
      eq("apex", args[1])
      eq("list", args[2])
      eq("log", args[3])
      eq("--json", args[4])
      eq("-o", args[5])
      eq("test-user@example.com", args[6])
      eq(6, #args)
    end)

    it("get_apex_log_get_args includes log dir and id", function()
      local args = Const.get_apex_log_get_args("/logs", "07LFAKE000001234")
      eq("apex", args[1])
      eq("get", args[2])
      eq("log", args[3])
      eq("-d", args[4])
      eq("/logs", args[5])
      eq("-i", args[6])
      eq("07LFAKE000001234", args[7])
      eq(7, #args)
    end)
  end)

  describe("Coverage.enable/disable", function()
    local Coverage

    before_each(function()
      Coverage = require("sf.test.coverage")
    end)

    it("enable sets flag and shows coverage", function()
      vim.g.sf_coverage_enabled = false
      Coverage.enable()
      eq(vim.g.sf_coverage_enabled, true)
    end)

    it("disable clears flag and clears signs", function()
      vim.g.sf_coverage_enabled = true
      Coverage.disable()
      eq(vim.g.sf_coverage_enabled, false)
    end)
  end)
end)
