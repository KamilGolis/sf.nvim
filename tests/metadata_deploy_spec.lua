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
      assert.are_equal("current_file", ctx.deployment_type)
      assert.are_equal("/p/FakeClass.cls", ctx.current_file)
      assert.is_nil(ctx.files)
      assert.is_not_nil(ctx.handle)
      assert.are_equal("65.0", ctx.options.api_version)
    end)

    it("creates context for multi-file deploy", function()
      local ctx = DeployUtils.create_deployment_context(
        "changed_files",
        nil,
        { "a.cls", "b.cls" },
        { api_version = "65.0" }
      )
      assert.are_equal("changed_files", ctx.deployment_type)
      assert.is_nil(ctx.current_file)
      assert.are_equal(2, #ctx.files)
    end)

    it("raises error for invalid deployment type", function()
      local ok, err = pcall(DeployUtils.create_deployment_context, nil, nil, nil, {})
      assert.is_false(ok)
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
      assert.is_true(is_conflict)
      assert.are_equal("Conflict on FakeClass", msg)
    end)

    it("returns false for non-conflict error", function()
      local is_conflict, msg = DeployUtils.detect_source_conflict({
        name = "GenericError",
        message = "Something went wrong",
      })
      assert.is_false(is_conflict)
      assert.is_nil(msg)
    end)

    it("returns false for empty result", function()
      local is_conflict, msg = DeployUtils.detect_source_conflict({})
      assert.is_false(is_conflict)
      assert.is_nil(msg)
    end)
  end)

  describe("DeployUtils.process_deployment_result", function()
    local DeployUtils

    before_each(function()
      DeployUtils = require("sf.deploy.utils")
    end)

    it("parses success result and returns true", function()
      local json = Helper.load_fixture_text("metadata-deploy", "deploy_success.json")
      assert.is_not_nil(json)
      local ctx = DeployUtils.create_deployment_context("current_file", "/p/FakeClass.cls", nil, ctx_opts)
      local ok = DeployUtils.process_deployment_result(json, ctx, 0)
      assert.is_true(ok)
    end)

    it("parses failure result and returns false", function()
      local json = Helper.load_fixture_text("metadata-deploy", "deploy_failure.json")
      assert.is_not_nil(json)
      local ctx = DeployUtils.create_deployment_context("current_file", "/p/FakeClass.cls", nil, ctx_opts)
      local ok = DeployUtils.process_deployment_result(json, ctx, 1)
      assert.is_false(ok)
    end)

    it("handles malformed JSON without crashing", function()
      local json = Helper.load_fixture_text("metadata-deploy", "deploy_malformed.txt")
      local ctx = DeployUtils.create_deployment_context("current_file", "/p/FakeClass.cls", nil, ctx_opts)
      local ok = DeployUtils.process_deployment_result(json, ctx, 0)
      assert.is_false(ok)
    end)

    it("returns false on malformed JSON with a nonzero exit code", function()
      -- Exercises the `elseif return_val ~= 0` branch (CLI failure path).
      local json = Helper.load_fixture_text("metadata-deploy", "deploy_malformed.txt")
      local ctx = DeployUtils.create_deployment_context("current_file", "/p/FakeClass.cls", nil, ctx_opts)
      local ok = DeployUtils.process_deployment_result(json, ctx, 1)
      assert.is_false(ok)
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
      assert.is_not_nil(results["FakeClass"])
      assert.are_equal(42, results["FakeClass"].error_line_number)
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
      assert.is_not_nil(results["FakeClass"])
      assert.is_nil(results["FakeClass"].error_line_number)
    end)

    it("returns empty table for no failures", function()
      local deploy_result = { result = { details = { componentFailures = {} }, files = {} } }
      local results = DeployUtils.extract_component_failures(deploy_result)
      assert.are_equal(0, vim.tbl_count(results))
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
      assert.is_true(ok)
      assert.is_nil(err)
    end)

    it("fails when deploy already running", function()
      State.start("deploy")
      local ok, err = DeployUtils.validate_deployment_preconditions()
      assert.is_false(ok)
      assert.is_not_nil(err)
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
      assert.are_equal("project", args[1])
      assert.are_equal("deploy", args[2])
      assert.are_equal("start", args[3])
      assert.are_equal("-d", args[4])
      assert.are_equal("/p/FakeClass.cls", args[5])
      assert.are_equal("--json", args[6])
      assert.are_equal("-a", args[7])
      assert.are_equal("65.0", args[8])
      assert.are_equal("-c", args[9])
      assert.are_equal(9, #args)
    end)

    it("get_manifest_deploy_args builds full vector without force flag", function()
      local args = Const.get_manifest_deploy_args("/p/manifest.xml", "65.0", nil)
      assert.are_equal("project", args[1])
      assert.are_equal("deploy", args[2])
      assert.are_equal("start", args[3])
      assert.are_equal("-x", args[4])
      assert.are_equal("/p/manifest.xml", args[5])
      assert.are_equal("--json", args[6])
      assert.are_equal("-a", args[7])
      assert.are_equal("65.0", args[8])
      assert.is_false(vim.tbl_contains(args, "-c"))
      assert.are_equal(8, #args)
    end)
  end)
end)
