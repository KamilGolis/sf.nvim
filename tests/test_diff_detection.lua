local helpers = dofile("tests/helpers.lua")
local eq = helpers.expect.equality
local expect = helpers.expect

describe("diff-detection", function()
  local Helper

  before_each(function()
    Helper = require("tests.helpers.init")
    Helper.setup({ system = false, notify = true })
  end)

  after_each(function()
    Helper.teardown()
  end)

  describe("Detect.parse_meta_xml_type", function()
    local Detect

    before_each(function()
      Detect = require("sf.diff.detect")
      require("tests.helpers.mock_notify").reset()
    end)

    it("parses plain root element", function()
      local fixture = Helper.fixtures.path("diff-detection", "FakeClass.cls-meta.xml")
      local type_name, err = Detect.parse_meta_xml_type(fixture)
      expect.no_equality(type_name, nil)
      eq("ApexClass", type_name)
      eq(err, nil)
    end)

    it("parses namespaced root element", function()
      local fixture = Helper.fixtures.path("diff-detection", "NamespacedTrigger.trigger-meta.xml")
      local type_name, err = Detect.parse_meta_xml_type(fixture)
      expect.no_equality(type_name, nil)
      eq("ApexTrigger", type_name)
    end)

    it("returns nil for missing file", function()
      local type_name, err = Detect.parse_meta_xml_type("/nonexistent/file-meta.xml")
      eq(type_name, nil)
      expect.no_equality(err, nil)
    end)
  end)

  describe("Detect.find_companion_meta_xml", function()
    local Detect

    before_each(function()
      Detect = require("sf.diff.detect")
      require("tests.helpers.mock_notify").reset()
    end)

    it("finds companion for split-file metadata", function()
      local fixture_cls = Helper.fixtures.path("diff-detection", "FakeClass.cls")
      local meta_path = Detect.find_companion_meta_xml(fixture_cls)
      expect.no_equality(meta_path, nil)
      expect.match(meta_path, "%-meta%.xml$")
    end)

    it("returns nil when no companion exists", function()
      local result = Detect.find_companion_meta_xml("/tmp/nonexistent.cls")
      eq(result, nil)
    end)

    it("returns path unchanged for -meta.xml files", function()
      local fixture = Helper.fixtures.path("diff-detection", "FakeClass.cls-meta.xml")
      local result = Detect.find_companion_meta_xml(fixture)
      eq(fixture, result)
    end)
  end)

  describe("Detect.get_member_name", function()
    local Detect

    before_each(function()
      Detect = require("sf.diff.detect")
    end)

    it("extracts name from .cls path", function()
      eq("FakeClass", Detect.get_member_name("/p/classes/FakeClass.cls"))
    end)

    it("extracts name from .object-meta.xml path", function()
      eq("MyObject.object", Detect.get_member_name("/p/objects/MyObject.object-meta.xml"))
    end)
  end)
end)
