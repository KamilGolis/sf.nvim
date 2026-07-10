--- Unit tests for debug level commands (Const/DebugUtils/Level).
-- @module test_debug_levels

local helpers = dofile("tests/helpers.lua")
local eq = helpers.expect.equality
local expect = helpers.expect

describe("debug-levels", function()
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

  describe("Const.DEBUG_LEVEL_FIELDS", function()
    local Const

    before_each(function()
      Const = require("sf.const")
    end)

    it("has 12 fields", function()
      eq(12, #Const.DEBUG_LEVEL_FIELDS)
    end)

    it("each field has name, label, default", function()
      for _, fd in ipairs(Const.DEBUG_LEVEL_FIELDS) do
        expect.no_equality(fd.name, nil)
        expect.no_equality(fd.label, nil)
        expect.no_equality(fd.default, nil)
      end
    end)

    it("fields with values have non-empty values table", function()
      for _, fd in ipairs(Const.DEBUG_LEVEL_FIELDS) do
        if fd.values ~= nil then
          eq(true, #fd.values > 0, "Field " .. fd.name .. " has empty values")
        end
      end
    end)

    it("DeveloperName has readonly_edit = true", function()
      local dev_name = Const.DEBUG_LEVEL_FIELDS[1]
      eq("DeveloperName", dev_name.name)
      eq(true, dev_name.readonly_edit)
    end)

    it("first field is DeveloperName, last is Workflow", function()
      eq("DeveloperName", Const.DEBUG_LEVEL_FIELDS[1].name)
      eq("Workflow", Const.DEBUG_LEVEL_FIELDS[#Const.DEBUG_LEVEL_FIELDS].name)
    end)
  end)

  describe("Const arg builders", function()
    local Const

    before_each(function()
      Const = require("sf.const")
    end)

    it("get_org_display_args", function()
      local args = Const.get_org_display_args("test@example.com")
      local s = table.concat(args, " ")

      expect.match(s, "org display")
      expect.match(s, "%-o test@example%.com")
      expect.match(s, "%-%-json")
    end)

    it("get_record_get_args", function()
      local args = Const.get_record_get_args("User", "Username='test@example.com'", "test@example.com")
      local s = table.concat(args, " ")

      expect.match(s, "data record get")
      expect.match(s, "%-s User")
      expect.match(s, "%-w Username='test@example%.com'")
      expect.match(s, "%-%-json")
    end)

    it("get_query_args includes -t (tooling API)", function()
      local args = Const.get_query_args("SELECT Id FROM DebugLevel", "test@example.com")
      local s = table.concat(args, " ")

      expect.match(s, "data query")
      expect.match(s, "%-q SELECT Id FROM DebugLevel")
      expect.match(s, "%-t")
      expect.match(s, "%-%-json")
    end)

    it("get_record_create_args builds DebugLevel record create", function()
      local args = Const.get_record_create_args("test@example.com", "DebugLevel", "ApexCode=FINE DeveloperName=Test", "65.0")
      local s = table.concat(args, " ")

      expect.match(s, "data create record")
      expect.match(s, "%-s DebugLevel")
      expect.match(s, "%-t")
      expect.match(s, "%-v ApexCode=FINE DeveloperName=Test")
      expect.match(s, "%-o test@example%.com")
      expect.match(s, "%-%-api%-version 65%.0")
      expect.match(s, "%-%-json")
    end)

    it("get_record_update_args includes record id", function()
      local args = Const.get_record_update_args("test@example.com", "DebugLevel", "ApexCode=FINE", "7dl00000001", "65.0")
      local s = table.concat(args, " ")

      expect.match(s, "data update record")
      expect.match(s, "%-s DebugLevel")
      expect.match(s, "%-t")
      expect.match(s, "%-v ApexCode=FINE")
      expect.match(s, "%-i 7dl00000001")
      expect.match(s, "%-o test@example%.com")
      expect.match(s, "%-%-api%-version 65%.0")
      expect.match(s, "%-%-json")
    end)

    it("get_record_delete_args builds delete command", function()
      local args = Const.get_record_delete_args("test@example.com", "DebugLevel", "7dl00000001", "65.0")
      local s = table.concat(args, " ")

      expect.match(s, "data delete record")
      expect.match(s, "%-s DebugLevel")
      expect.match(s, "%-t")
      expect.match(s, "%-i 7dl00000001")
      expect.match(s, "%-o test@example%.com")
      expect.match(s, "%-%-api%-version 65%.0")
      expect.match(s, "%-%-json")
    end)
  end)

  describe("DebugUtils.parse_org_data", function()
    local DebugUtils

    before_each(function()
      DebugUtils = require("sf.debug.utils")
    end)

    it("extracts username from valid org response", function()
      local json = Helper.load_fixture_text("debug-levels", "org.json")
      local username, err = DebugUtils.parse_org_data(json)
      expect.no_equality(username, nil)
      eq("test.user@example.com", username)
      eq(err, nil)
    end)

    it("returns error for malformed JSON", function()
      local username, err = DebugUtils.parse_org_data("not json")
      eq(username, nil)
      expect.no_equality(err, nil)
    end)

    it("returns error when status is non-zero", function()
      local username, err = DebugUtils.parse_org_data('{"status":1,"result":{}}')
      eq(username, nil)
      expect.no_equality(err, nil)
    end)

    it("returns error when username is missing", function()
      local username, err = DebugUtils.parse_org_data('{"status":0,"result":{"id":"123"}}')
      eq(username, nil)
      expect.no_equality(err, nil)
    end)
  end)

  describe("DebugUtils.parse_user_data", function()
    local DebugUtils

    before_each(function()
      DebugUtils = require("sf.debug.utils")
    end)

    it("extracts Id from valid user response", function()
      local json = Helper.load_fixture_text("debug-levels", "user.json")
      local user_id, user_name, err = DebugUtils.parse_user_data(json)
      eq("005000000000001", user_id)
      eq(err, nil)
    end)

    it("returns error for malformed JSON", function()
      local id, name, err = DebugUtils.parse_user_data("not json")
      eq(id, nil)
      expect.no_equality(err, nil)
    end)
  end)

  describe("DebugUtils.parse_debug_levels", function()
    local DebugUtils

    before_each(function()
      DebugUtils = require("sf.debug.utils")
    end)

    it("extracts debug level records from fixture", function()
      local json = Helper.load_fixture_text("debug-levels", "debug-level.json")
      local levels, err = DebugUtils.parse_debug_levels(json)
      expect.no_equality(levels, nil)
      eq(err, nil)
      eq(2, #levels)
      eq("Default_DevConsole", levels[1].DeveloperName)
      eq("My_Debug", levels[2].DeveloperName)
      eq("7dl000000000002", levels[2].Id)
      eq("FINE", levels[2].ApexCode)
    end)

    it("returns error for malformed JSON", function()
      local levels, err = DebugUtils.parse_debug_levels("not json")
      eq(levels, nil)
      expect.no_equality(err, nil)
    end)
  end)

  describe("DebugUtils.parse_trace_flags", function()
    local DebugUtils

    before_each(function()
      DebugUtils = require("sf.debug.utils")
    end)

    it("extracts single trace flag record from fixture", function()
      local json = Helper.load_fixture_text("debug-levels", "trace.json")
      local traces, err = DebugUtils.parse_trace_flags(json)
      expect.no_equality(traces, nil)
      eq(err, nil)
      eq(1, #traces)
      eq("7tf000000000001", traces[1].Id)
      eq("005000000000001", traces[1].TracedEntityId)
    end)
  end)

  describe("DebugUtils.fields_to_value_string", function()
    local DebugUtils
    local Const

    before_each(function()
      DebugUtils = require("sf.debug.utils")
      Const = require("sf.const")
    end)

    it("converts fields table to CLI value string", function()
      local fields = {}
      for _, fd in ipairs(Const.DEBUG_LEVEL_FIELDS) do
        fields[fd.name] = fd.default
      end
      fields.DeveloperName = "Test_Debug"

      local value_string = DebugUtils.fields_to_value_string(fields)
      expect.match(value_string, "DeveloperName=Test_Debug")
      expect.match(value_string, "ApexCode=DEBUG")
      expect.match(value_string, "ApexProfiling=INFO")
      expect.no_match(value_string, "MasterLabel=")
    end)

    it("includes all 12 fields in order", function()
      local fields = {}
      for _, fd in ipairs(Const.DEBUG_LEVEL_FIELDS) do
        fields[fd.name] = fd.default
      end
      fields.DeveloperName = "MyLevel"

      local value_string = DebugUtils.fields_to_value_string(fields)
      local parts = vim.split(value_string, " ")
      eq(12, #parts)
      eq("DeveloperName=MyLevel", parts[1])
      eq("Workflow=INFO", parts[#parts])
    end)
  end)

  describe("DebugUtils.debug_level_to_picker_item", function()
    local DebugUtils

    before_each(function()
      DebugUtils = require("sf.debug.utils")
    end)

    it("converts API record to picker item", function()
      local dl = {
        Id = "7dl000000000001",
        DeveloperName = "Test_Level",
        MasterLabel = "Test_Level",
        CreatedDate = "2026-01-01T12:00:00.000+0000",
      }

      local item = DebugUtils.debug_level_to_picker_item(dl)
      eq("7dl000000000001", item.id)
      eq("Test_Level", item.developer_name)
      eq("Test_Level", item.master_label)
      expect.match(item.text, "Test_Level")
      expect.match(item.description, "2026")
      eq(dl, item.details)
    end)

    it("handles missing CreatedDate gracefully", function()
      local dl = {
        Id = "7dl00000001",
        DeveloperName = "NoDate",
        MasterLabel = "NoDate",
      }

      local item = DebugUtils.debug_level_to_picker_item(dl)
      eq("NoDate", item.developer_name)
      expect.match(item.description, "unknown")
    end)
  end)

  describe("DebugUtils.save_debug_level_json", function()
    local DebugUtils
    local Config
    local PathUtils

    before_each(function()
      DebugUtils = require("sf.debug.utils")
      Config = require("sf.config")
      PathUtils = require("sf.core.path_utils")
    end)

    it("writes JSON to debug_levels_dir/<DeveloperName>.json", function()
      local fields = { DeveloperName = "Test_Level", ApexCode = "FINE", MasterLabel = "Test_Level" }
      DebugUtils.save_debug_level_json(fields)

      local dir = Config:get_options().debug_levels_dir
      local filepath = PathUtils.join(dir, "Test_Level.json")
      local ok, content = pcall(vim.fn.readfile, filepath)
      eq(true, ok, "File should exist: " .. filepath)

      if ok then
        local data = table.concat(content, "")
        local decoded = vim.json.decode(data)
        eq("Test_Level", decoded.DeveloperName)
        eq("FINE", decoded.ApexCode)
      end
    end)
  end)

  describe("Level buffer helpers", function()
    local Level

    before_each(function()
      Level = require("sf.debug.level")
    end)

    it("new_level function exists", function()
      eq("function", type(Level.new_level))
    end)

    it("delete_level function exists", function()
      eq("function", type(Level.delete_level))
    end)

    it("edit_level function exists", function()
      eq("function", type(Level.edit_level))
    end)
  end)

  describe("DebugUtils.run_workflow fixture contract", function()
    local DebugUtils

    before_each(function()
      DebugUtils = require("sf.debug.utils")
    end)

    it("parse_debug_levels can load the fixture", function()
      local json = Helper.load_fixture_text("debug-levels", "debug-level.json")
      local ok, parsed = pcall(vim.json.decode, json)
      eq(true, ok)
      eq(type(parsed.result), "table")
      eq(type(parsed.result.records), "table")
      eq(2, #parsed.result.records)
    end)

    it("create_success fixture has expected structure", function()
      local parsed = Helper.load_fixture_json("debug-levels", "create_success.json")
      eq(0, parsed.status)
      eq(true, parsed.result.success)
    end)

    it("create_failure fixture has error structure", function()
      local parsed = Helper.load_fixture_json("debug-levels", "create_failure.json")
      eq(1, parsed.status)
      eq("REQUIRED_FIELD_MISSING", parsed.name)
      expect.match(parsed.message, "MasterLabel")
    end)

    it("delete_success fixture has expected structure", function()
      local parsed = Helper.load_fixture_json("debug-levels", "delete_success.json")
      eq(0, parsed.status)
      eq(true, parsed.result.success)
    end)

    it("update_success fixture has expected structure", function()
      local parsed = Helper.load_fixture_json("debug-levels", "update_success.json")
      eq(0, parsed.status)
      eq(true, parsed.result.success)
    end)
  end)
end)
