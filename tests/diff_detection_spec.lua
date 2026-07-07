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
      assert.is_not_nil(type_name)
      assert.are_equal("ApexClass", type_name)
      assert.is_nil(err)
    end)

    it("parses namespaced root element", function()
      local fixture = Helper.fixtures.path("diff-detection", "NamespacedTrigger.trigger-meta.xml")
      local type_name, err = Detect.parse_meta_xml_type(fixture)
      assert.is_not_nil(type_name)
      assert.are_equal("ApexTrigger", type_name)
    end)

    it("returns nil for missing file", function()
      local type_name, err = Detect.parse_meta_xml_type("/nonexistent/file-meta.xml")
      assert.is_nil(type_name)
      assert.is_not_nil(err)
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
      assert.is_not_nil(meta_path)
      assert.is_true(meta_path:match("%-meta%.xml$") ~= nil)
    end)

    it("returns nil when no companion exists", function()
      local result = Detect.find_companion_meta_xml("/tmp/nonexistent.cls")
      assert.is_nil(result)
    end)

    it("returns path unchanged for -meta.xml files", function()
      local fixture = Helper.fixtures.path("diff-detection", "FakeClass.cls-meta.xml")
      local result = Detect.find_companion_meta_xml(fixture)
      assert.are_equal(fixture, result)
    end)
  end)

  describe("Detect.get_member_name", function()
    local Detect

    before_each(function()
      Detect = require("sf.diff.detect")
    end)

    it("extracts name from .cls path", function()
      assert.are_equal("FakeClass", Detect.get_member_name("/p/classes/FakeClass.cls"))
    end)

    it("extracts name from .object-meta.xml path", function()
      assert.are_equal("MyObject.object", Detect.get_member_name("/p/objects/MyObject.object-meta.xml"))
    end)
  end)
end)
