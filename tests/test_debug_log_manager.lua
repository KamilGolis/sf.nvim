local helpers = dofile("tests/helpers.lua")
local eq = helpers.expect.equality
local expect = helpers.expect

describe("debug-log-manager", function()
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

  describe("LogUtils.process_log_list", function()
    local LogUtils

    before_each(function()
      LogUtils = require("sf.log.utils")
    end)

    it("parses valid log list JSON", function()
      local json = Helper.load_fixture_text("debug-log-manager", "log_list.json")
      expect.no_equality(json, nil)
      local ok, logs, err = LogUtils.process_log_list(json)
      eq(ok, true)
      expect.no_equality(logs, nil)
      eq(2, #logs)
    end)

    it("returns empty for empty result", function()
      local json = Helper.load_fixture_text("debug-log-manager", "log_list_empty.json")
      local ok, logs, err = LogUtils.process_log_list(json)
      eq(ok, true)
      eq(0, #logs)
    end)

    it("rejects malformed JSON", function()
      local json = Helper.load_fixture_text("debug-log-manager", "log_list_malformed.txt")
      local ok, logs, err = LogUtils.process_log_list(json)
      eq(ok, false)
      eq(logs, nil)
      expect.no_equality(err, nil)
    end)

    it("rejects JSON with non-zero status", function()
      local ok, logs, err = LogUtils.process_log_list('{"status":1,"result":[]}')
      eq(ok, false)
      eq(logs, nil)
      expect.no_equality(err, nil)
    end)
  end)

  describe("LogUtils.get_log_list_path", function()
    local LogUtils

    before_each(function()
      LogUtils = require("sf.log.utils")
    end)

    it("returns path rooted at cache path", function()
      local path = LogUtils.get_log_list_path()
      expect.match(path, "log%-list%.json$")
    end)
  end)
end)
