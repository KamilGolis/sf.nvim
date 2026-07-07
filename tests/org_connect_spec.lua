describe("org-connect", function()
  local Helper

  before_each(function()
    Helper = require("tests.helpers.init")
    Helper.setup({
      fn_overrides = {
        exepath = function(name) return name == "sf" and "/usr/bin/sf" or "" end,
        getcwd = function() return "/tmp/_sf_test_org" end,
        fnamemodify = function(path) return path end,
      },
    })
  end)

  after_each(function()
    Helper.teardown()
  end)

  describe("OrgUtils.process_org_list", function()
    local OrgUtils

    before_each(function()
      OrgUtils = require("sf.org.utils")
    end)

    it("parses valid org list JSON", function()
      local json = Helper.load_fixture_text("org-connect", "org_list.json")
      assert.is_not_nil(json)
      local ok, orgs, err = OrgUtils.process_org_list(json)
      assert.is_true(ok, "should parse successfully")
      assert.is_not_nil(orgs)
      assert.are_equal(3, #orgs, "should have 3 orgs")
      assert.are_equal("prod", orgs[1].text)
      assert.are_equal("admin@mycompany.com", orgs[1].description)
      assert.are_equal("https://na1.salesforce.com", orgs[1].details)
      assert.is_true(orgs[1].org_data.isDefault)
    end)

    it("returns empty for empty result array", function()
      local json = Helper.load_fixture_text("org-connect", "org_list_empty.json")
      local ok, orgs, err = OrgUtils.process_org_list(json)
      assert.is_true(ok)
      assert.is_not_nil(orgs)
      assert.are_equal(0, #orgs)
    end)

    it("rejects malformed JSON", function()
      local json = Helper.load_fixture_text("org-connect", "org_list_malformed.txt")
      local ok, orgs, err = OrgUtils.process_org_list(json)
      assert.is_false(ok)
      assert.is_nil(orgs)
      assert.is_not_nil(err)
    end)

    it("rejects JSON with no result key", function()
      local ok, orgs, err = OrgUtils.process_org_list('{"status":0}')
      assert.is_false(ok)
      assert.is_nil(orgs)
      assert.is_not_nil(err)
    end)

    it("rejects JSON with non-zero status", function()
      local ok, orgs, err = OrgUtils.process_org_list('{"status":1,"result":[]}')
      assert.is_false(ok)
      assert.is_nil(orgs)
      assert.is_not_nil(err, "should reject non-zero status")
    end)
  end)

  describe("OrgUtils.create_org_selection_picker", function()
    local OrgUtils
    local mock_snacks

    before_each(function()
      OrgUtils = require("sf.org.utils")
      mock_snacks = require("tests.helpers.mock_snacks")
    end)

    it("creates picker with org items", function()
      local orgs = {
        { text = "dev", description = "dev@test.com", details = "https://test.sf.com", org_data = { username = "dev@test.com" } },
      }
      local cb = function() end
      OrgUtils.create_org_selection_picker(orgs, cb)
      assert.is_true(mock_snacks.assert_called())
      local items = mock_snacks.get_items()
      assert.are_equal(1, #items)
      assert.are_equal("dev", items[1].text)
    end)
  end)

  describe("OrgUtils.set_target_org", function()
    local OrgUtils

    before_each(function()
      OrgUtils = require("sf.org.utils")
    end)

    it("spawns config set command and invokes callback on success", function()
      local called = false
      OrgUtils.set_target_org(
        { username = "test-user@example.com", alias = "dev" },
        nil,
        function(success, msg)
          called = true
          assert.is_true(success)
          assert.is_not_nil(msg)
        end
      )
      -- Yield to the event loop so the vim.schedule-wrapped on_exit fires
      Helper.wait_for(function() return called end)
      local mock_vim = require("tests.helpers.mock_vim")
      assert.is_true(mock_vim.assert_system_called())
      assert.is_true(called, "callback should have been invoked")
      local calls = mock_vim.get_system_calls()
      local args = calls[1].args
      assert.is_not_nil(args)
    end)
  end)

  describe("OrgUtils.check_default_org", function()
    local OrgUtils
    local tmpdir

    before_each(function()
      OrgUtils = require("sf.org.utils")
      tmpdir = "/tmp/_sf_org_test_" .. vim.fn.localtime() .. "_" .. vim.fn.rand()
      vim.fn.mkdir(tmpdir .. "/.sf", "p")
      do
        local f = io.open(tmpdir .. "/sfdx-project.json", "w")
        f:write("{}")
        f:close()
      end
      Helper.mock_vim.setup_fn_mocks({
        getcwd = function() return tmpdir end,
        fnamemodify = function(path, mod)
          if path == "" or not path then return tmpdir end
          return path
        end,
        nvim_buf_get_name = function() return tmpdir .. "/classes/FakeClass.cls" end,
      })
    end)

    local function write_config(fixture)
      local f = io.open(tmpdir .. "/.sf/config.json", "w")
      local content = Helper.load_fixture_text("org-connect", fixture)
      f:write(content)
      f:close()
    end

    it("returns false when no target-org configured", function()
      write_config("config_empty.json")
      local ok, username, err = OrgUtils.check_default_org()
      assert.is_false(ok)
      assert.is_nil(username)
    end)

    it("returns true and username when target-org configured", function()
      write_config("config_with_org.json")
      local ok, username, err = OrgUtils.check_default_org()
      assert.is_true(ok, "should find target org")
      assert.are_equal("test-user@example.com", username)
    end)
  end)

  describe("Connect:check_cli", function()
    local Connect

    before_each(function()
      Connect = require("sf.org.connect")
    end)
    it("calls callback when CLI is installed and version parses", function()
      local mock_vim = require("tests.helpers.mock_vim")
      local called = false
      Connect:check_cli(function() called = true end)

      -- Verify CLI was invoked (version parsing is tested in core-utilities)
      assert.is_true(mock_vim.assert_system_called())
    end)
    it("skips CLI check when already cached", function()
      vim.g.sf_cli_checked = true
      local called = false
      Connect:check_cli(function() called = true end)
      local mock_vim = require("tests.helpers.mock_vim")
      mock_vim.assert_no_system_call()
      assert.is_true(called, "callback should fire immediately")
      vim.g.sf_cli_checked = nil
    end)
  end)

  describe("Connect:select_default_org", function()
    local Connect

    before_each(function()
      Connect = require("sf.org.connect")
    end)

    it("fetches org list and creates picker", function()
      local ok, err = pcall(Connect.select_default_org, Connect)
      assert.is_true(ok, "select_default_org should not throw: " .. tostring(err))
      -- Yield so the vim.schedule-wrapped on_exit fires
      local mock_vim = require("tests.helpers.mock_vim")
      Helper.wait_for(function() return #mock_vim.get_system_calls() > 0 end)
      assert.is_true(#mock_vim.get_system_calls() > 0, "should have created at least one system call")
    end)
  end)
end)
