describe("log-analysis", function()
  local Helper

  before_each(function()
    Helper = require("tests.helpers.init")
    Helper.setup({ system = false, notify = true })
  end)

  after_each(function()
    Helper.teardown()
  end)

  describe("Analyze.tag_category", function()
    local Analyze

    before_each(function()
      Analyze = require("sf.log.analyze")
      require("tests.helpers.mock_notify").reset()
    end)

    it("classifies noise tags (exact match in NOISE_TAGS)", function()
      local hl = Analyze.tag_category("VARIABLE_ASSIGNMENT")
      assert.are_equal("SfLogNoise", hl)
    end)

    it("classifies error tags (exact match in ERROR_TAGS)", function()
      local hl = Analyze.tag_category("FATAL_ERROR")
      assert.are_equal("SfLogError", hl)
    end)

    it("classifies signal prefix tags (prefix match)", function()
      local hl = Analyze.tag_category("CODE_UNIT_STARTED")
      assert.are_equal("SfLogSignal", hl)
    end)

    it("classifies unknown tags as info", function()
      local hl = Analyze.tag_category("UNKNOWN_TAG_XYZ")
      assert.are_equal("SfLogInfo", hl)
    end)
  end)

  describe("Analyze.display_buffer", function()
    local Analyze

    before_each(function()
      Analyze = require("sf.log.analyze")
      require("tests.helpers.mock_notify").reset()
    end)

    it("creates a scratch buffer populated with the given lines", function()
      Analyze.display_buffer("test-log-id", { "line1", "line2" })
      local buf = vim.api.nvim_get_current_buf()
      assert.is_true(vim.api.nvim_buf_is_valid(buf))
      local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
      assert.are_equal(2, #lines)
      assert.are_equal("line1", lines[1])
      assert.are_equal("line2", lines[2])
    end)
  end)
end)
