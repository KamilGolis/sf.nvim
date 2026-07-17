local helpers = dofile("tests/helpers.lua")
local eq = helpers.expect.equality
local expect = helpers.expect

describe("metadata-deploy", function()
  local Helper
  local ctx_opts

  before_each(function()
    Helper = require("tests.helpers.init")
    local tmpdir = "/tmp/_sf_deploy_" .. vim.fn.localtime() .. "_" .. vim.fn.rand()
    vim.fn.mkdir(tmpdir, "p")
    ctx_opts = { api_version = "65.0", deploy_file = tmpdir .. "/deploy.json", cache_path = tmpdir }
    _G._sf_deploy_tmpdir = tmpdir
    Helper.setup({
      fn_overrides = {
        exepath = function(name)
          return name == "sf" and "/usr/bin/sf" or ""
        end,
        getcwd = function()
          return tmpdir
        end,
        fnamemodify = function(path)
          return path
        end,
      },
    })
  end)
  after_each(function()
    if _G._sf_deploy_tmpdir then
      vim.fn.delete(_G._sf_deploy_tmpdir, "rf")
      _G._sf_deploy_tmpdir = nil
    end
    Helper.teardown()
  end)

  describe("DeployUtils.create_deployment_context", function()
    local DeployUtils

    before_each(function()
      DeployUtils = require("sf.deploy.utils")
    end)

    it("creates context for current file deploy", function()
      local ctx =
        DeployUtils.create_deployment_context("current_file", "/p/FakeClass.cls", nil, { api_version = "65.0" })
      eq("current_file", ctx.deployment_type)
      eq("/p/FakeClass.cls", ctx.current_file)
      eq(ctx.files, nil)
      expect.no_equality(ctx.handle, nil)
      eq("65.0", ctx.options.api_version)
    end)

    it("creates context for multi-file deploy", function()
      local ctx = DeployUtils.create_deployment_context(
        "changed_files",
        nil,
        { "a.cls", "b.cls" },
        { api_version = "65.0" }
      )
      eq("changed_files", ctx.deployment_type)
      eq(ctx.current_file, nil)
      eq(2, #ctx.files)
    end)

    it("raises error for invalid deployment type", function()
      local ok, err = pcall(DeployUtils.create_deployment_context, nil, nil, nil, {})
      eq(ok, false)
    end)
  end)

  describe("DeployUtils.detect_source_conflict", function()
    local DeployUtils

    before_each(function()
      DeployUtils = require("sf.deploy.utils")
    end)

    it("detects SourceConflictError", function()
      local is_conflict, msg = DeployUtils.detect_source_conflict({
        name = "SourceConflictError",
        message = "Conflict on FakeClass",
      })
      eq(is_conflict, true)
      eq("Conflict on FakeClass", msg)
    end)

    it("returns false for non-conflict error", function()
      local is_conflict, msg = DeployUtils.detect_source_conflict({
        name = "GenericError",
        message = "Something went wrong",
      })
      eq(is_conflict, false)
      eq(msg, nil)
    end)

    it("returns false for empty result", function()
      local is_conflict, msg = DeployUtils.detect_source_conflict({})
      eq(is_conflict, false)
      eq(msg, nil)
    end)
  end)

  describe("DeployUtils.process_deployment_result", function()
    local DeployUtils

    before_each(function()
      DeployUtils = require("sf.deploy.utils")
    end)

    it("parses success result and returns true", function()
      local json = Helper.load_fixture_text("metadata-deploy", "deploy_success.json")
      expect.no_equality(json, nil)
      local ctx = DeployUtils.create_deployment_context("current_file", "/p/FakeClass.cls", nil, ctx_opts)
      local ok = DeployUtils.process_deployment_result(json, ctx, 0)
      eq(ok, true)
    end)

    it("parses failure result and returns false", function()
      local json = Helper.load_fixture_text("metadata-deploy", "deploy_failure.json")
      expect.no_equality(json, nil)
      local ctx = DeployUtils.create_deployment_context("current_file", "/p/FakeClass.cls", nil, ctx_opts)
      local ok = DeployUtils.process_deployment_result(json, ctx, 1)
      eq(ok, false)
    end)

    it("handles malformed JSON without crashing", function()
      local json = Helper.load_fixture_text("metadata-deploy", "deploy_malformed.txt")
      local ctx = DeployUtils.create_deployment_context("current_file", "/p/FakeClass.cls", nil, ctx_opts)
      local ok = DeployUtils.process_deployment_result(json, ctx, 0)
      eq(ok, false)
    end)

    it("returns false on malformed JSON with a nonzero exit code", function()
      -- Exercises the `elseif return_val ~= 0` branch (CLI failure path).
      local json = Helper.load_fixture_text("metadata-deploy", "deploy_malformed.txt")
      local ctx = DeployUtils.create_deployment_context("current_file", "/p/FakeClass.cls", nil, ctx_opts)
      local ok = DeployUtils.process_deployment_result(json, ctx, 1)
      eq(ok, false)
    end)
  end)

  describe("DeployUtils.extract_component_failures", function()
    local DeployUtils

    before_each(function()
      DeployUtils = require("sf.deploy.utils")
    end)

    it("extracts failures from deploy result", function()
      local deploy_result = {
        result = {
          details = {
            componentFailures = {
              {
                fullName = "FakeClass",
                fileName = "classes/FakeClass.cls",
                problemType = "Error",
                lineNumber = 42,
                columnNumber = 10,
                componentType = "ApexClass",
              },
            },
          },
          files = {},
        },
      }
      local results = DeployUtils.extract_component_failures(deploy_result)
      expect.no_equality(results["FakeClass"], nil)
      eq(42, results["FakeClass"].error_line_number)
    end)

    it("handles failures without line/column", function()
      local deploy_result = {
        result = {
          details = {
            componentFailures = {
              {
                fullName = "FakeClass",
                fileName = "classes/FakeClass.cls",
                problemType = "Error",
                componentType = "ApexClass",
              },
            },
          },
          files = {},
        },
      }
      local results = DeployUtils.extract_component_failures(deploy_result)
      expect.no_equality(results["FakeClass"], nil)
      eq(results["FakeClass"].error_line_number, nil)
    end)

    it("returns empty table for no failures", function()
      local deploy_result = { result = { details = { componentFailures = {} }, files = {} } }
      local results = DeployUtils.extract_component_failures(deploy_result)
      eq(0, vim.tbl_count(results))
    end)
  end)

  describe("DeployUtils.validate_deployment_preconditions", function()
    local DeployUtils
    local State

    before_each(function()
      DeployUtils = require("sf.deploy.utils")
      State = require("sf.core.state")
    end)

    it("passes when no deploy running", function()
      State.finish("deploy")
      local ok, err = DeployUtils.validate_deployment_preconditions()
      eq(ok, true)
      eq(err, nil)
    end)

    it("fails when deploy already running", function()
      State.start("deploy")
      local ok, err = DeployUtils.validate_deployment_preconditions()
      eq(ok, false)
      expect.no_equality(err, nil)
      State.finish("deploy")
    end)
  end)

  describe("Const deploy arg builders", function()
    local Const

    before_each(function()
      Const = require("sf.const")
    end)

    it("get_current_file_deploy_args builds full vector with force flag", function()
      local args = Const.get_current_file_deploy_args("/p/FakeClass.cls", "65.0", true)
      eq("project", args[1])
      eq("deploy", args[2])
      eq("start", args[3])
      eq("-d", args[4])
      eq("/p/FakeClass.cls", args[5])
      eq("--json", args[6])
      eq("-a", args[7])
      eq("65.0", args[8])
      eq("-c", args[9])
      eq(9, #args)
    end)

    it("get_source_dir_deploy_args builds args with multiple -d flags", function()
      local args = Const.get_source_dir_deploy_args({ "/p/MyClass.cls", "/p/MyClass.cls-meta.xml" }, "65.0", nil)
      eq("project", args[1])
      eq("deploy", args[2])
      eq("start", args[3])
      eq("-d", args[4])
      eq("/p/MyClass.cls", args[5])
      eq("-d", args[6])
      eq("/p/MyClass.cls-meta.xml", args[7])
      eq("--json", args[8])
      eq("-a", args[9])
      eq("65.0", args[10])
      eq(vim.tbl_contains(args, "-c"), false)
      eq(10, #args)
    end)

    it("get_source_dir_deploy_args includes -c when force is true", function()
      local args = Const.get_source_dir_deploy_args({ "/p/FakeClass.cls" }, "65.0", true)
      eq("project", args[1])
      eq("deploy", args[2])
      eq("start", args[3])
      eq("-d", args[4])
      eq("/p/FakeClass.cls", args[5])
      eq("--json", args[6])
      eq("-a", args[7])
      eq("65.0", args[8])
      eq("-c", args[9])
      eq(9, #args)
    end)
  end)
end)
