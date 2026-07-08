local helpers = dofile("tests/helpers.lua")
local eq = helpers.expect.equality
local expect = helpers.expect

describe("schema-refresh", function()
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

  describe("Const metadata list arg builders", function()
    local Const

    before_each(function()
      Const = require("sf.const")
    end)

    it("get_org_list_metadata_types_args with target org", function()
      local args = Const.get_org_list_metadata_types_args("test-user@example.com")
      eq("org", args[1])
      eq("list", args[2])
      eq("metadata-types", args[3])
      eq("--json", args[4])
      eq("-o", args[5])
      eq("test-user@example.com", args[6])
      eq(6, #args)
    end)

    it("get_org_list_metadata_types_args without target org", function()
      local args = Const.get_org_list_metadata_types_args(nil)
      eq("org", args[1])
      eq("list", args[2])
      eq("metadata-types", args[3])
      eq("--json", args[4])
      eq(vim.tbl_contains(args, "-o"), false)
      eq(4, #args)
    end)

    it("get_org_list_metadata_args includes -m flag", function()
      local args = Const.get_org_list_metadata_args("ApexClass", nil)
      eq("org", args[1])
      eq("list", args[2])
      eq("metadata", args[3])
      eq("-m", args[4])
      eq("ApexClass", args[5])
      eq("--json", args[6])
      eq(vim.tbl_contains(args, "-o"), false)
      eq(6, #args)
    end)
  end)

  describe("metadata-types fixture contract", function()
    -- The schema refresh module parses the metadata-types listing inline
    -- (no public parse function); this guards the fixture it consumes.
    it("metadata_types.json parses and exposes a result table", function()
      local json = Helper.load_fixture_text("schema-refresh", "metadata_types.json")
      expect.no_equality(json, nil)
      local ok, parsed = pcall(vim.json.decode, json)
      eq(ok, true)
      eq(type(parsed.result), "table")
    end)

    it("metadata_types_malformed.txt is not valid JSON", function()
      local json = Helper.load_fixture_text("schema-refresh", "metadata_types_malformed.txt")
      local ok = pcall(vim.json.decode, json)
      eq(ok, false)
    end)
  end)
end)
