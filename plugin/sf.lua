--- sf-nvim plugin for Neovim - Salesforce plugin
-- @license MIT

local PathUtils = require("sf.core.path_utils")
local Utils = require("sf.core.utils")
if not Utils.has_sfdx_project() then
  return
end

local Analyze = require("sf.log.analyze")
local ApexExecute = require("sf.apex.execute")
local Cleanup = require("sf.log.cleanup")
local Config = require("sf.config")
local Connector = require("sf.org.connect")
local Deployment = require("sf.deploy.metadata")
local Diagnostics = require("sf.core.diagnostics")
local Diff = require("sf.diff.runner")
local Log = require("sf.core.log").scoped("plugin")
local LogList = require("sf.log.list")
local RetrieveMetadata = require("sf.retrieve.metadata")
local SchemaCleanup = require("sf.schema.cleanup")
local SchemaRefresh = require("sf.schema.refresh")
local SchemaRetrieve = require("sf.schema.retrieve")
local TestCodeActions = require("sf.core.code_actions")
local TestRunner = require("sf.test.runner")

local indexes = require("sf.core.indexes")

if vim.g.loaded_sf_nvim then
  return
end

vim.g.loaded_sf_nvim = true
vim.g.sf_cli_checked = false

-- Ensure cache directory exists on startup
local cache_path = Config:get_options().cache_path
if vim.fn.isdirectory(cache_path) == 0 then
  vim.fn.mkdir(cache_path, "p")
end

--- Set autocommand for opening buffer and attaching diagnostics from store
vim.api.nvim_create_autocmd("BufEnter", {
  callback = function(args)
    local buf_name = vim.fn.bufname(args.buf)
    local file_name = vim.fn.fnamemodify(buf_name, ":t")

    if Diagnostics.diagnostic_store[file_name] then
      vim.diagnostic.set(Config:get_options().namespace, args.buf, Diagnostics.diagnostic_store[file_name])
    end

    -- Handle coverage display for Apex files
    local Coverage = require("sf.test.coverage")
    Coverage.on_buffer_enter(args.buf)
  end,
})

-- Get the default package directory from sfdx-project.json
local default_path = Utils.get_default_package_path()
if default_path then
  indexes.index_files(default_path)
else
  -- Fallback to hardcoded path if sfdx-project.json parsing fails
  indexes.index_files(PathUtils.join(PathUtils.get_separator(), "force-app", "main", "default"))
end

local function make_test_options()
  return {
    sf_cli_path = Config:get_options().sf_cli_path or "sf",
    debug = Config:get_options().debug or false,
  }
end

local COMMANDS = {
  org = {
    set = function()
      Connector:select_default_org()
    end,
  },
  schema = {
    refresh = function()
      SchemaRefresh.refresh()
    end,
    retrieve = function()
      SchemaRetrieve.retrieve()
    end,
    cleanup = function()
      SchemaCleanup.cleanup_schema()
    end,
  },
  deploy = {
    metadata = function(force)
      Deployment:deploy_metadata(force)
    end,
    changed = function(force)
      Deployment:deploy_changed_metadatas(force)
    end,
    selected = function(force)
      Deployment:deploy_selected_metadata(force)
    end,
  },
  test = {
    class = function()
      TestRunner.run_current_tests("class", make_test_options())
    end,
    method = function()
      TestRunner.run_current_tests("method", make_test_options())
    end,
    result = function()
      TestRunner.show_last_results(make_test_options())
    end,
    action = function()
      TestCodeActions.show_actions()
    end,
  },
  coverage = {
    class = function()
      TestRunner.run_coverage_at_cursor("class", make_test_options())
    end,
    method = function()
      TestRunner.run_coverage_at_cursor("method", make_test_options())
    end,
    result = function()
      TestRunner.show_last_coverage_results(make_test_options())
    end,
    on = function()
      require("sf.test.coverage").enable()
    end,
    off = function()
      require("sf.test.coverage").disable()
    end,
  },
  log = {
    list = function()
      LogList.list_logs(make_test_options())
    end,
    resume = function()
      LogList.resume_logs()
    end,
    debug = function()
      LogList.debug_logs()
    end,
    cleanup = function()
      Cleanup.cleanup_logs()
    end,
    analysis = {
      basic = function()
        Analyze.basic()
      end,
    },
  },
  apex = {
    execute = {
      file = function()
        ApexExecute:execute_file()
      end,
      new = function()
        ApexExecute:execute_new()
      end,
      cleanup = function()
        ApexExecute:execute_cleanup()
      end,
      list = function()
        ApexExecute:execute_list()
      end,
    },
    cache = {
      rebuild = function()
        require("sf.faux.runner"):rebuild()
      end,
      clear = function()
        require("sf.faux.runner"):clear()
      end,
      status = function()
        require("sf.faux.runner"):status()
      end,
    },
  },
  debug = {
    level = {
      new = function()
        require("sf.debug.level").new_level()
      end,
      delete = function()
        require("sf.debug.level").delete_level()
      end,
      edit = function()
        require("sf.debug.level").edit_level()
      end,
    },
    trace = {
      new = function()
        require("sf.trace.flag").new_trace_flag()
      end,
      delete = function()
        require("sf.trace.flag").delete_trace_flag()
      end,
    },
  },
  retrieve = {
    metadata = function()
      RetrieveMetadata.retrieve_selected()
    end,
    type = function()
      RetrieveMetadata.retrieve_all_of_type()
    end,
    refresh = function()
      RetrieveMetadata.retrieve_current_buffer()
    end,
    diff = function()
      Diff.diff_current_buffer()
    end,
  },
}
vim.api.nvim_create_user_command("Sf", function(opts)
  Log.log("Sf command:", opts.fargs)
  local module = opts.fargs[1]
  local action = opts.fargs[2]

  if not module or not COMMANDS[module] then
    Log.notify("Unknown subcommand: " .. (module or ""), vim.log.levels.ERROR)
    return
  end

  local actions = COMMANDS[module]
  if not action or not actions[action] then
    Log.notify("Unknown subcommand: " .. (action or ""), vim.log.levels.ERROR)
    return
  end

  local handler = actions[action]
  if type(handler) == "table" then
    local sub = opts.fargs[3]
    if not sub or not handler[sub] then
      Log.notify("Unknown subcommand: " .. (sub or ""), vim.log.levels.ERROR)
      return
    end
    handler[sub]()
  else
    local force_flag = opts.fargs[3] == "force"
    handler(force_flag)
  end
end, {
  nargs = "+",
  complete = function(ArgLead, CmdLine)
    local commands = COMMANDS
    local args = vim.split(CmdLine, " ")

    if #args <= 2 then
      return vim.tbl_filter(function(cmd)
        return cmd:match("^" .. ArgLead)
      end, vim.tbl_keys(commands))
    elseif #args == 3 and commands[args[2]] then
      return vim.tbl_filter(function(cmd)
        return cmd:match("^" .. ArgLead)
      end, vim.tbl_keys(commands[args[2]]))
    elseif #args == 4 and commands[args[2]] and type(commands[args[2]][args[3]]) == "table" then
      return vim.tbl_filter(function(cmd)
        return cmd:match("^" .. ArgLead)
      end, vim.tbl_keys(commands[args[2]][args[3]]))
    elseif #args == 4 and args[2] == "deploy" and vim.tbl_contains(vim.tbl_keys(commands.deploy), args[3]) then
      return vim.tbl_filter(function(cmd)
        return cmd:match("^" .. ArgLead)
      end, { "force" })
    end

    return {}
  end,
  desc = "Salesforce CLI integration commands",
})
TestCodeActions.setup()
