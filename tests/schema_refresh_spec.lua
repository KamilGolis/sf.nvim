describe("schema-refresh", function()
  local Helper

  before_each(function()
    Helper = require("tests.helpers.init")
    Helper.setup({ fn_overrides = { exepath = function(n) return n == "sf" and "/usr/bin/sf" or "" end } })
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
      assert.are_equal("org", args[1])
      assert.are_equal("list", args[2])
      assert.are_equal("metadata-types", args[3])
      assert.are_equal("--json", args[4])
      assert.are_equal("-o", args[5])
      assert.are_equal("test-user@example.com", args[6])
      assert.are_equal(6, #args)
    end)

    it("get_org_list_metadata_types_args without target org", function()
      local args = Const.get_org_list_metadata_types_args(nil)
      assert.are_equal("org", args[1])
      assert.are_equal("list", args[2])
      assert.are_equal("metadata-types", args[3])
      assert.are_equal("--json", args[4])
      assert.is_false(vim.tbl_contains(args, "-o"))
      assert.are_equal(4, #args)
    end)

    it("get_org_list_metadata_args includes -m flag", function()
      local args = Const.get_org_list_metadata_args("ApexClass", nil)
      assert.are_equal("org", args[1])
      assert.are_equal("list", args[2])
      assert.are_equal("metadata", args[3])
      assert.are_equal("-m", args[4])
      assert.are_equal("ApexClass", args[5])
      assert.are_equal("--json", args[6])
      assert.is_false(vim.tbl_contains(args, "-o"))
      assert.are_equal(6, #args)
    end)
  end)

  describe("metadata-types fixture contract", function()
    -- The schema refresh module parses the metadata-types listing inline
    -- (no public parse function); this guards the fixture it consumes.
    it("metadata_types.json parses and exposes a result table", function()
      local json = Helper.load_fixture_text("schema-refresh", "metadata_types.json")
      assert.is_not_nil(json)
      local ok, parsed = pcall(vim.json.decode, json)
      assert.is_true(ok, "fixture should be valid JSON")
      assert.is_table(parsed.result)
    end)

    it("metadata_types_malformed.txt is not valid JSON", function()
      local json = Helper.load_fixture_text("schema-refresh", "metadata_types_malformed.txt")
      local ok = pcall(vim.json.decode, json)
      assert.is_false(ok)
    end)
  end)


end)
