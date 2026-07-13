local helpers = dofile("tests/helpers.lua")
local eq = helpers.expect.equality
local expect = helpers.expect

describe("dap-debug-log", function()
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

  describe("Config dap_log_dir", function()
    it("defaults to nil before setup", function()
      local Config = require("sf.config")
      local fresh = Config:new()
      eq(fresh:get_options().dap_log_dir, nil)
    end)

    it("resolves to log_dir/dap after default setup", function()
      local Config = require("sf.config")
      local path = Config:get_options().dap_log_dir
      expect.match(path, "logs[/\\]dap$")
    end)

    it("resolves custom dap_log_dir path", function()
      local Config = require("sf.config")
      Config:setup({ dap_log_dir = "/tmp/custom-dap-test" })
      expect.match(Config:get_options().dap_log_dir, "custom%-dap%-test$")
    end)
  end)

  describe("Dap.copy_log_for_debug", function()
    local temp_src

    after_each(function()
      if temp_src then
        vim.fn.delete(temp_src)
      end
    end)

    it("copies a log file to dap_log_dir/current.log", function()
      local Config = require("sf.config")
      local Dap = require("sf.dap")

      temp_src = vim.fn.tempname()
      vim.fn.writefile({ "line1", "line2" }, temp_src)

      local dap_dir = Config:get_options().dap_log_dir
      vim.fn.mkdir(dap_dir, "p")

      local result = Dap.copy_log_for_debug(temp_src)
      eq(result, true, "copy_log_for_debug should return true")

      local dest = dap_dir .. "/current.log"
      eq(vim.fn.filereadable(dest), 1)

      local dest_lines = vim.fn.readfile(dest)
      eq(#dest_lines, 2)
      eq(dest_lines[1], "line1")

      local found = Helper.mock_notify.find("DAP: log copied")
      expect.no_equality(found, nil)
    end)

    it("creates destination directory if missing", function()
      local Config = require("sf.config")
      local Dap = require("sf.dap")

      temp_src = vim.fn.tempname()
      vim.fn.writefile({ "test" }, temp_src)

      local dap_dir = Config:get_options().dap_log_dir
      vim.fn.delete(dap_dir, "rf")

      local result = Dap.copy_log_for_debug(temp_src)
      eq(result, true, "copy_log_for_debug should return true")
      eq(vim.fn.isdirectory(dap_dir), 1, "dap directory should exist")
    end)

    it("rejects empty log file and notifies", function()
      local Config = require("sf.config")
      local Dap = require("sf.dap")

      temp_src = vim.fn.tempname()
      vim.fn.writefile({}, temp_src)

      local dap_dir = Config:get_options().dap_log_dir
      vim.fn.mkdir(dap_dir, "p")

      local result = Dap.copy_log_for_debug(temp_src)
      eq(result, false, "copy_log_for_debug should return false for empty file")

      local found = Helper.mock_notify.find("DAP: log file is empty")
      expect.no_equality(found, nil)
    end)
  end)

  describe("LogList.debug_logs", function()
    it("is a function", function()
      local LogList = require("sf.log.list")
      eq(type(LogList.debug_logs), "function")
    end)
  end)
end)
