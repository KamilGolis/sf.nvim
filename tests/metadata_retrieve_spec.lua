describe("metadata-retrieve", function()
  local Helper

  before_each(function()
    Helper = require("tests.helpers.init")
    Helper.setup({ fn_overrides = {
      exepath = function(n)
        return n == "sf" and "/usr/bin/sf" or ""
      end,
    } })
    -- Route retrieve.json writes to a temp dir so the suite doesn't pollute the repo.
    local tmpdir = "/tmp/_sf_retrieve_test_" .. vim.fn.localtime() .. "_" .. vim.fn.rand()
    vim.fn.mkdir(tmpdir, "p")
    _G._sf_retrieve_tmpdir = tmpdir
    require("sf.config"):setup({ cache_path = tmpdir })
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
      assert.is_true(type(xml) == "string")
      assert.is_true(xml:find("FakeClass") ~= nil)
      assert.is_true(xml:find("OtherClass") ~= nil)
      assert.is_true(xml:find("ApexClass") ~= nil)
      assert.is_true(xml:find('<?xml version="1.0"') ~= nil)
    end)

    it("handles empty items", function()
      local xml = Utils.build_manifest_xml({}, "ApexClass")
      assert.is_true(type(xml) == "string")
      assert.is_true(xml:find("ApexClass") ~= nil)
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
      assert.is_not_nil(result)
      assert.is_true(result:find("classes/FakeClass.cls") ~= nil)
      assert.is_true(result:find("Missing field") ~= nil)
    end)

    it("returns nil for empty messages", function()
      assert.is_nil(Utils.format_retrieve_messages({}))
    end)

    it("returns nil for nil messages", function()
      assert.is_nil(Utils.format_retrieve_messages(nil))
    end)
  end)

  describe("handle_retrieve_result", function()
    local Utils

    before_each(function()
      Utils = require("sf.retrieve.utils")
    end)

    it("returns error for empty result", function()
      local status = Utils.handle_retrieve_result("", {})
      assert.are_equal("error", status)
    end)

    it("returns success for a Succeeded retrieve", function()
      local json = Helper.load_fixture_text("metadata-retrieve", "retrieve_success.json")
      assert.is_not_nil(json)
      local status = Utils.handle_retrieve_result(json, {})
      assert.are_equal("success", status)
    end)

    it("returns warning when messages are present", function()
      local json = Helper.load_fixture_text("metadata-retrieve", "retrieve_with_warnings.json")
      assert.is_not_nil(json)
      local status, msg = Utils.handle_retrieve_result(json, {})
      assert.are_equal("warning", status)
      assert.is_not_nil(msg)
      assert.is_true(msg:find("Missing field X") ~= nil)
    end)

    it("returns error for a failed retrieve", function()
      local json = Helper.load_fixture_text("metadata-retrieve", "retrieve_failure.json")
      assert.is_not_nil(json)
      local status, msg = Utils.handle_retrieve_result(json, {})
      assert.are_equal("error", status)
      assert.is_not_nil(msg)
    end)
  end)

  describe("Const retrieve arg builders", function()
    local Const

    before_each(function()
      Const = require("sf.const")
    end)

    it("get_project_retrieve_args builds full vector for items", function()
      local args = Const.get_project_retrieve_args({ { fullName = "FakeClass", type_name = "ApexClass" } }, "65.0", nil)
      assert.are_equal("project", args[1])
      assert.are_equal("retrieve", args[2])
      assert.are_equal("start", args[3])
      assert.is_true(vim.tbl_contains(args, "-m"))
      assert.is_true(vim.tbl_contains(args, "ApexClass:FakeClass"))
      assert.is_true(vim.tbl_contains(args, "--json"))
      assert.is_true(vim.tbl_contains(args, "-a"))
      assert.is_true(vim.tbl_contains(args, "65.0"))
      assert.is_true(vim.tbl_contains(args, "-c"))
      assert.is_false(vim.tbl_contains(args, "-o"))
    end)

    it("get_project_retrieve_type_args builds full vector", function()
      local args = Const.get_project_retrieve_type_args("ApexClass", "65.0", nil)
      assert.are_equal("project", args[1])
      assert.are_equal("retrieve", args[2])
      assert.are_equal("start", args[3])
      assert.is_true(vim.tbl_contains(args, "-m"))
      assert.is_true(vim.tbl_contains(args, "ApexClass"))
      assert.is_true(vim.tbl_contains(args, "--json"))
      assert.is_true(vim.tbl_contains(args, "-a"))
      assert.is_true(vim.tbl_contains(args, "65.0"))
      assert.is_true(vim.tbl_contains(args, "-c"))
      assert.is_false(vim.tbl_contains(args, "-o"))
    end)

    it("get_project_retrieve_manifest_args builds full vector", function()
      local args = Const.get_project_retrieve_manifest_args("/p/manifest.xml", "65.0", nil)
      assert.are_equal("project", args[1])
      assert.are_equal("retrieve", args[2])
      assert.are_equal("start", args[3])
      assert.is_true(vim.tbl_contains(args, "-x"))
      assert.is_true(vim.tbl_contains(args, "/p/manifest.xml"))
      assert.is_true(vim.tbl_contains(args, "--json"))
      assert.is_true(vim.tbl_contains(args, "-a"))
      assert.is_true(vim.tbl_contains(args, "65.0"))
      assert.is_true(vim.tbl_contains(args, "-c"))
      assert.is_false(vim.tbl_contains(args, "-o"))
    end)
  end)
end)
