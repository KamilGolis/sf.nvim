local helpers = dofile("tests/helpers.lua")
local eq = helpers.expect.equality
local expect = helpers.expect

describe("metadata-retrieve", function()
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
    -- Directly set cache_path instead of calling Config:setup a second time,
    -- whose eager path-joining would corrupt retrieve_file with a nested path.
    local tmpdir = "/tmp/_sf_retrieve_test_" .. vim.fn.localtime() .. "_" .. vim.fn.rand()
    vim.fn.mkdir(tmpdir, "p")
    _G._sf_retrieve_tmpdir = tmpdir
    local config = require("sf.config")
    local opts = config:get_options()
    opts.cache_path = vim.fn.fnamemodify(tmpdir, ":p")
    opts.retrieve_file = opts.cache_path .. "/retrieve.json"
  end)

  after_each(function()
    if _G._sf_retrieve_tmpdir then
      vim.fn.delete(_G._sf_retrieve_tmpdir, "rf")
      _G._sf_retrieve_tmpdir = nil
    end
    Helper.teardown()
  end)

  describe("RetrieveUtils.build_manifest_xml", function()
    local Utils

    before_each(function()
      Utils = require("sf.retrieve.utils")
    end)

    it("builds XML for multiple items", function()
      local xml = Utils.build_manifest_xml({ { fullName = "FakeClass" }, { fullName = "OtherClass" } }, "ApexClass")
      eq(type(xml), "string")
      expect.match(xml, "FakeClass")
      expect.match(xml, "OtherClass")
      expect.match(xml, "ApexClass")
      expect.match(xml, '<?xml version="1.0"')
    end)

    it("handles empty items", function()
      local xml = Utils.build_manifest_xml({}, "ApexClass")
      eq(type(xml), "string")
      expect.match(xml, "ApexClass")
    end)
  end)

  describe("RetrieveUtils.format_retrieve_messages", function()
    local Utils

    before_each(function()
      Utils = require("sf.retrieve.utils")
    end)

    it("formats messages with fileName and problem", function()
      local result = Utils.format_retrieve_messages({
        { fileName = "classes/FakeClass.cls", problem = "Missing field" },
      })
      expect.no_equality(result, nil)
      expect.match(result, "classes/FakeClass.cls")
      expect.match(result, "Missing field")
    end)

    it("returns nil for empty messages", function()
      eq(Utils.format_retrieve_messages({}), nil)
    end)

    it("returns nil for nil messages", function()
      eq(Utils.format_retrieve_messages(nil), nil)
    end)
  end)

  describe("handle_retrieve_result", function()
    local Utils

    before_each(function()
      Utils = require("sf.retrieve.utils")
    end)

    it("returns error for empty result", function()
      local status = Utils.handle_retrieve_result("", {})
      eq("error", status)
    end)

    it("returns success for a Succeeded retrieve", function()
      local json = Helper.load_fixture_text("metadata-retrieve", "retrieve_success.json")
      expect.no_equality(json, nil)
      local status = Utils.handle_retrieve_result(json, {})
      eq("success", status)
    end)

    it("returns warning when messages are present", function()
      local json = Helper.load_fixture_text("metadata-retrieve", "retrieve_with_warnings.json")
      expect.no_equality(json, nil)
      local status, msg = Utils.handle_retrieve_result(json, {})
      eq("warning", status)
      expect.no_equality(msg, nil)
      expect.match(msg, "Missing field X")
    end)

    it("returns error for a failed retrieve", function()
      local json = Helper.load_fixture_text("metadata-retrieve", "retrieve_failure.json")
      expect.no_equality(json, nil)
      local status, msg = Utils.handle_retrieve_result(json, {})
      eq("error", status)
      expect.no_equality(msg, nil)
    end)
  end)

  describe("Const retrieve arg builders", function()
    local Const

    before_each(function()
      Const = require("sf.const")
    end)

    it("get_project_retrieve_args builds full vector for items", function()
      local args = Const.get_project_retrieve_args({ { fullName = "FakeClass", type_name = "ApexClass" } }, "65.0", nil)
      eq("project", args[1])
      eq("retrieve", args[2])
      eq("start", args[3])
      eq(vim.tbl_contains(args, "-m"), true)
      eq(vim.tbl_contains(args, "ApexClass:FakeClass"), true)
      eq(vim.tbl_contains(args, "--json"), true)
      eq(vim.tbl_contains(args, "-a"), true)
      eq(vim.tbl_contains(args, "65.0"), true)
      eq(vim.tbl_contains(args, "-c"), true)
      eq(vim.tbl_contains(args, "-o"), false)
    end)

    it("get_project_retrieve_type_args builds full vector", function()
      local args = Const.get_project_retrieve_type_args("ApexClass", "65.0", nil)
      eq("project", args[1])
      eq("retrieve", args[2])
      eq("start", args[3])
      eq(vim.tbl_contains(args, "-m"), true)
      eq(vim.tbl_contains(args, "ApexClass"), true)
      eq(vim.tbl_contains(args, "--json"), true)
      eq(vim.tbl_contains(args, "-a"), true)
      eq(vim.tbl_contains(args, "65.0"), true)
      eq(vim.tbl_contains(args, "-c"), true)
      eq(vim.tbl_contains(args, "-o"), false)
    end)

    it("get_project_retrieve_manifest_args builds full vector", function()
      local args = Const.get_project_retrieve_manifest_args("/p/manifest.xml", "65.0", nil)
      eq("project", args[1])
      eq("retrieve", args[2])
      eq("start", args[3])
      eq(vim.tbl_contains(args, "-x"), true)
      eq(vim.tbl_contains(args, "/p/manifest.xml"), true)
      eq(vim.tbl_contains(args, "--json"), true)
      eq(vim.tbl_contains(args, "-a"), true)
      eq(vim.tbl_contains(args, "65.0"), true)
      eq(vim.tbl_contains(args, "-c"), true)
      eq(vim.tbl_contains(args, "-o"), false)
    end)
  end)
end)
