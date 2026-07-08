local helpers = dofile("tests/helpers.lua")
local eq = helpers.expect.equality
local expect = helpers.expect

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
      eq("SfLogNoise", hl)
    end)

    it("classifies error tags (exact match in ERROR_TAGS)", function()
      local hl = Analyze.tag_category("FATAL_ERROR")
      eq("SfLogError", hl)
    end)

    it("classifies signal prefix tags (prefix match)", function()
      local hl = Analyze.tag_category("CODE_UNIT_STARTED")
      eq("SfLogSignal", hl)
    end)

    it("classifies unknown tags as info", function()
      local hl = Analyze.tag_category("UNKNOWN_TAG_XYZ")
      eq("SfLogInfo", hl)
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
      eq(vim.api.nvim_buf_is_valid(buf), true)
      local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
      eq(2, #lines)
      eq("line1", lines[1])
      eq("line2", lines[2])
    end)
  end)
end)
