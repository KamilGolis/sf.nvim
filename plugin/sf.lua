--- sf-nvim plugin for Neovim - Salesforce plugin
-- @license MIT

local Utils = require("sf.core.utils")
if not Utils.has_sfdx_project() then
  return
end

local Config = require("sf.config")
local Connector = require("sf.org.connect")
local Deployment = require("sf.deploy.metadata")
local Diagnostics = require("sf.core.diagnostics")
local TestRunner = require("sf.test.runner")
local LogList = require("sf.log.list")

local indexes = require("sf.core.indexes")

if vim.g.loaded_sf_nvim then
  return
end

vim.g.loaded_sf_nvim = true
vim.g.sf_cli_checked = false

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
  indexes.index_files("/force-app/main/default")
end

--- Define the sf command with subcommands
vim.api.nvim_create_user_command("Sf", function(opts)
  local module = opts.fargs[1]
  local action = opts.fargs[2]

  if module == "org" then
    if action == "set" then
      Connector:select_default_org()
    else
      vim.notify("Unknown subcommand: " .. (module or ""), vim.log.levels.ERROR)
    end
  end

  if module == "deploy" then
    local force_flag = false
    local third_arg = opts.fargs[3]

    -- Check if "force" is specified as third argument
    if third_arg == "force" then
      force_flag = true
    end

    if action == "metadata" then
      Deployment:deploy_metadata(force_flag)
    elseif action == "changed" then
      Deployment:deploy_changed_metadatas(force_flag)
    elseif action == "selected" then
      Deployment:deploy_selected_metadata(force_flag)
    else
      vim.notify("Unknown subcommand: " .. (action or ""), vim.log.levels.ERROR)
    end
  end

  if module == "test" then
    local options = {
      sf_cli_path = Config:get_options().sf_cli_path or "sf",
      debug = Config:get_options().debug or false,
    }

    if action == "class" then
      TestRunner.run_current_tests("class", options)
    elseif action == "method" then
      TestRunner.run_current_tests("method", options)
    elseif action == "result" then
      TestRunner.show_last_results(options)
    else
      vim.notify("Unknown test subcommand: " .. (action or ""), vim.log.levels.ERROR)
    end
  end

  if module == "coverage" then
    local options = {
      sf_cli_path = Config:get_options().sf_cli_path or "sf",
      debug = Config:get_options().debug or false,
    }

    if action == "class" then
      TestRunner.run_coverage_at_cursor("class", options)
    elseif action == "method" then
      TestRunner.run_coverage_at_cursor("method", options)
    elseif action == "result" then
      TestRunner.show_last_coverage_results(options)
    elseif action == "on" then
      local Coverage = require("sf.test.coverage")
      Coverage.enable()
    elseif action == "off" then
      local Coverage = require("sf.test.coverage")
      Coverage.disable()
    else
      vim.notify("Unknown coverage subcommand: " .. (action or ""), vim.log.levels.ERROR)
    end
  end

  if module == "log" then
    local options = {
      sf_cli_path = Config:get_options().sf_cli_path or "sf",
      debug = Config:get_options().debug or false,
    }

    if action == "list" then
      LogList.list_logs(options)
    else
      vim.notify("Unknown log subcommand: " .. (action or ""), vim.log.levels.ERROR)
    end
  end
end, {
  nargs = "+",
  complete = function(ArgLead, CmdLine, CursorPos)
    local commands = {
      org = { "set" },
      cli = {},
      deploy = { "metadata", "changed", "selected" },
      test = { "class", "method", "result" },
      coverage = { "class", "method", "result", "on", "off" },
      log = { "list" },
    }

    local args = vim.split(CmdLine, " ")

    if #args <= 2 then -- First argument
      return vim.tbl_filter(function(cmd)
        return cmd:match("^" .. ArgLead)
      end, vim.tbl_keys(commands))
    elseif #args == 3 and commands[args[2]] then -- Second argument
      return vim.tbl_filter(function(cmd)
        return cmd:match("^" .. ArgLead)
      end, commands[args[2]])
    elseif #args == 4 and args[2] == "deploy" and vim.tbl_contains(commands.deploy, args[3]) then -- Third argument for deploy commands
      return vim.tbl_filter(function(cmd)
        return cmd:match("^" .. ArgLead)
      end, { "force" })
    end

    return {}
  end,
  desc = "Salesforce CLI integration commands",
})
