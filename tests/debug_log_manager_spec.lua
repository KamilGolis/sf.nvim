describe("debug-log-manager", function()
  local Helper

  before_each(function()
    Helper = require("tests.helpers.init")
    Helper.setup({ fn_overrides = {
      exepath = function(n)
        return n == "sf" and "/usr/bin/sf" or ""
      end,
    } })
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
      assert.is_not_nil(json)
      local ok, logs, err = LogUtils.process_log_list(json)
      assert.is_true(ok)
      assert.is_not_nil(logs)
      assert.are_equal(2, #logs)
    end)

    it("returns empty for empty result", function()
      local json = Helper.load_fixture_text("debug-log-manager", "log_list_empty.json")
      local ok, logs, err = LogUtils.process_log_list(json)
      assert.is_true(ok)
      assert.are_equal(0, #logs)
    end)

    it("rejects malformed JSON", function()
      local json = Helper.load_fixture_text("debug-log-manager", "log_list_malformed.txt")
      local ok, logs, err = LogUtils.process_log_list(json)
      assert.is_false(ok)
      assert.is_nil(logs)
      assert.is_not_nil(err)
    end)

    it("rejects JSON with non-zero status", function()
      local ok, logs, err = LogUtils.process_log_list('{"status":1,"result":[]}')
      assert.is_false(ok)
      assert.is_nil(logs)
      assert.is_not_nil(err)
    end)
  end)

  describe("LogUtils.get_log_list_path", function()
    local LogUtils

    before_each(function()
      LogUtils = require("sf.log.utils")
    end)

    it("returns path rooted at cache path", function()
      local path = LogUtils.get_log_list_path()
      assert.is_true(path:find("logList.json") ~= nil, "path should contain logList.json")
    end)
  end)
end)
