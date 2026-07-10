--- Unit tests for trace flag functionality (TraceUtils, parse_trace_flags).
-- @module test_trace_flags

local helpers = dofile("tests/helpers.lua")
local eq = helpers.expect.equality
local expect = helpers.expect

describe("trace-flags", function()
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

  describe("TraceUtils.format_datetime_local", function()
    local TraceUtils

    before_each(function()
      TraceUtils = require("sf.trace.utils")
    end)

    it("converts ISO string to local display format", function()
      local result = TraceUtils.format_datetime_local("2026-01-01T10:00:00.000+0000")
      eq("01.01.2026 10:00", result)
    end)

    it("returns empty string for nil input", function()
      eq("", TraceUtils.format_datetime_local(nil))
    end)

    it("returns empty string for empty input", function()
      eq("", TraceUtils.format_datetime_local(""))
    end)
  end)

  describe("TraceUtils.parse_datetime_local", function()
    local TraceUtils

    before_each(function()
      TraceUtils = require("sf.trace.utils")
    end)

    it("parses valid local datetime to ISO format", function()
      local iso, err = TraceUtils.parse_datetime_local("09.07.2026 12:45")

      expect.no_equality(iso, nil)
      expect.equality(err, nil)
      -- Should match ISO pattern
      expect.match(iso, "^%d%d%d%d%-%d%d%-%d%dT")
    end)

    it("returns error for invalid format", function()
      local iso, err = TraceUtils.parse_datetime_local("invalid")
      eq(iso, nil)
      expect.no_equality(err, nil)
    end)

    it("returns error for empty string", function()
      local iso, err = TraceUtils.parse_datetime_local("")
      eq(iso, nil)
      expect.no_equality(err, nil)
    end)
  end)

  describe("TraceUtils.required_trace_fields_from_debug_level", function()
    local TraceUtils

    before_each(function()
      TraceUtils = require("sf.trace.utils")
    end)

    it("extracts 8 picklist fields plus LogType", function()
      local dl = {
        ApexCode = "Debug",
        ApexProfiling = "Info",
        Callout = "Info",
        Database = "Fine",
        System = "Debug",
        Validation = "Info",
        Visualforce = "Fine",
        Workflow = "Info",
      }

      local fields = TraceUtils.required_trace_fields_from_debug_level(dl)

      eq("USER_DEBUG", fields.LogType)
      eq("Debug", fields.ApexCode)
      eq("Info", fields.ApexProfiling)
      eq("Info", fields.Callout)
      eq("Fine", fields.Database)
      eq("Debug", fields.System)
      eq("Info", fields.Validation)
      eq("Fine", fields.Visualforce)
      eq("Info", fields.Workflow)
    end)

    it("defaults missing fields to NONE", function()
      local dl = {}

      local fields = TraceUtils.required_trace_fields_from_debug_level(dl)

      eq("USER_DEBUG", fields.LogType)
      eq("NONE", fields.ApexCode)
      eq("NONE", fields.Database)
    end)
  end)

  describe("TraceUtils.build_trace_value_string", function()
    local TraceUtils

    before_each(function()
      TraceUtils = require("sf.trace.utils")
    end)

    it("builds CLI value string with all required fields", function()
      local dl = { Id = "7dl000000000001" }
      local fields = {
        LogType = "USER_DEBUG",
        ApexCode = "Debug",
        ApexProfiling = "Info",
        Callout = "Info",
        Database = "Fine",
        System = "Debug",
        Validation = "Info",
        Visualforce = "Fine",
        Workflow = "Info",
      }

      local result = TraceUtils.build_trace_value_string(
        fields,
        dl,
        "005000000000001",
        "2026-01-01T10:00:00.000+0000",
        "2026-01-01T11:00:00.000+0000"
      )

      expect.match(result, "DebugLevelId=7dl000000000001")
      expect.match(result, "StartDate=2026%-01%-01")
      expect.match(result, "ExpirationDate=2026%-01%-01")
      expect.match(result, "LogType=USER_DEBUG")
      expect.match(result, "TracedEntityId=005000000000001")
      expect.match(result, "ApexCode=Debug")
      expect.match(result, "Workflow=Info")
    end)
  end)

  describe("TraceUtils.is_overlap_error", function()
    local TraceUtils

    before_each(function()
      TraceUtils = require("sf.trace.utils")
    end)

    it("returns true for already being traced", function()
      eq(true, TraceUtils.is_overlap_error("already being traced by a trace flag"))
    end)

    it("returns true for overlap", function()
      eq(true, TraceUtils.is_overlap_error("expiration date that overlap this"))
    end)

    it("returns true for full Salesforce error message", function()
      local msg =
        "This entity is already being traced by a trace flag with a start and expiration date that overlap this trace flag's start and expiration date.: Traced Entity ID"
      eq(true, TraceUtils.is_overlap_error(msg))
    end)

    it("returns false for unrelated error message", function()
      eq(false, TraceUtils.is_overlap_error("Some other error occurred"))
    end)

    it("returns false for nil input", function()
      eq(false, TraceUtils.is_overlap_error(nil))
    end)
  end)

  describe("DebugUtils.parse_trace_flags", function()
    local DebugUtils

    before_each(function()
      DebugUtils = require("sf.debug.utils")
    end)

    it("wraps single record in array", function()
      local json = Helper.load_fixture_text("debug-levels", "trace.json")
      local flags, err = DebugUtils.parse_trace_flags(json)

      expect.no_equality(flags, nil)
      expect.equality(err, nil)
      eq("table", type(flags))
      eq(1, #flags)
      eq("7tf000000000001", flags[1].Id)
      eq("005000000000001", flags[1].TracedEntityId)
    end)

    it("returns empty array for null result", function()
      local json = Helper.load_fixture_text("debug-levels", "trace-empty.json")
      local flags, err = DebugUtils.parse_trace_flags(json)

      expect.equality(err, nil)
      eq("table", type(flags))
      eq(0, #flags)
    end)

    it("returns error for malformed JSON", function()
      local flags, err = DebugUtils.parse_trace_flags("not json")
      eq(flags, nil)
      expect.no_equality(err, nil)
    end)
  end)

  describe("Const tooling arg builders", function()
    local Const

    before_each(function()
      Const = require("sf.const")
    end)

    it("get_tooling_record_delete_args builds delete for TraceFlag", function()
      local args = Const.get_tooling_record_delete_args("test@example.com", "TraceFlag", "7tf00001", "65.0")
      local s = table.concat(args, " ")

      expect.match(s, "data delete record")
      expect.match(s, "%-s TraceFlag")
      expect.match(s, "%-t")
      expect.match(s, "%-i 7tf00001")
      expect.match(s, "%-%-json")
    end)

    it("get_tooling_record_get_args includes -t flag", function()
      local args = Const.get_tooling_record_get_args("TraceFlag", "TracedEntityId='005'", "test@example.com")
      local s = table.concat(args, " ")

      expect.match(s, "data record get")
      expect.match(s, "%-s TraceFlag")
      expect.match(s, "%-t")
      expect.match(s, "%-w TracedEntityId='005'")
      expect.match(s, "%-%-json")
    end)

    it("get_tooling_record_create_args builds create for TraceFlag", function()
      local args = Const.get_tooling_record_create_args("test@example.com", "TraceFlag", "ApexCode=Debug", "65.0")
      local s = table.concat(args, " ")

      expect.match(s, "data create record")
      expect.match(s, "%-s TraceFlag")
      expect.match(s, "%-t")
      expect.match(s, "%-v ApexCode=Debug")
      expect.match(s, "%-%-json")
    end)
  end)
end)
