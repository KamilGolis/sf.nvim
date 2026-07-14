--- sf-nvim DAP integration for Apex Replay Debugger
-- @license MIT

local Config = require("sf.config")
local Const = require("sf.const")
local PathUtils = require("sf.core.path_utils")

local Dap = {}

--- Setup nvim-dap adapter and configurations for Apex Replay Debugger
--- @param dap_opts table Options: { adapter_path, port }
function Dap.setup(dap_opts)
  dap_opts = dap_opts or {}
  -- "apex_ls" is the default LSP tho be used. It is required to run DAP.
  local lsp_name = dap_opts.lsp_client_name or "apex_ls"

  local ok, dap = pcall(require, "dap")
  if not ok then
    return
  end

  if not dap_opts.adapter_path then
    return
  end

  dap.adapters["apex-replay"] = {
    type = "server",
    host = "127.0.0.1",
    port = dap_opts.port or 4712,
    executable = {
      command = "node",
      args = {
        dap_opts.adapter_path,
        "--server=" .. (dap_opts.port or 4712),
      },
    },
  }

  dap.configurations.apex = {
    {
      name = "Launch Apex Replay Debugger",
      type = "apex-replay",
      request = "launch",
      logFile = function()
        return PathUtils.join(Config:get_options().dap_log_dir, "current.log")
      end,
      logFileContents = function()
        local path = PathUtils.join(Config:get_options().dap_log_dir, "current.log")
        local f = io.open(path, "r")
        if f then
          local content = f:read("*a")
          f:close()
          return content
        end
      end,
      stopOnEntry = true,
      trace = true,
      lineBreakpointInfo = function()
        for _, client in pairs(vim.lsp.get_clients({ name = lsp_name })) do
          local done = false
          local result = nil

          client.request("debugger/lineBreakpoints", {}, function(err, res)
            if err then
              vim.notify(Const.DAP_MESSAGES.LSP_BREAKPOINT_ERROR .. vim.inspect(err), vim.log.levels.ERROR)
            end
            done = true
            result = res
          end)

          vim.wait(5000, function()
            return done
          end, 100)

          return result
        end

        vim.notify(Const.DAP_MESSAGES.LSP_NOT_AVAILABLE, vim.log.levels.WARN)
      end,
      projectPath = function()
        return vim.fn.getcwd()
      end,
    },
  }
end

--- Check if nvim-dap is available and adapter_path is configured
--- @return boolean
function Dap.is_configured()
  local ok, _ = pcall(require, "dap")
  return ok and Config:get_options().dap.adapter_path ~= nil
end

--- Copy a log file to the DAP debug directory (dap/current.log)
--- @param log_path string Path to the log file to copy
--- @return boolean success
function Dap.copy_log_for_debug(log_path)
  if not Config:get_options().dap.adapter_path then
    vim.notify(Const.DAP_MESSAGES.NOT_CONFIGURED, vim.log.levels.WARN)
    return false
  end

  local dest_dir = Config:get_options().dap_log_dir
  local dest_file = PathUtils.join(dest_dir, "current.log")

  vim.fn.mkdir(dest_dir, "p")

  local lines = vim.fn.readfile(log_path)

  if #lines == 0 then
    vim.notify(Const.DAP_MESSAGES.LOG_EMPTY, vim.log.levels.ERROR)
    return false
  end

  vim.fn.writefile(lines, dest_file)
  vim.notify(Const.DAP_MESSAGES.LOG_COPIED .. dest_file, vim.log.levels.INFO)

  return true
end

--- Launch the Apex Replay Debugger session
--- @return boolean success
function Dap.launch()
  if not Dap.is_configured() then
    vim.notify(Const.DAP_MESSAGES.CANNOT_LAUNCH, vim.log.levels.WARN)
    return false
  end
  local dap = require("dap")
  local configs = dap.configurations.apex
  if not configs or #configs == 0 then
    vim.notify(Const.DAP_MESSAGES.NO_CONFIGURATION, vim.log.levels.ERROR)
    return false
  end
  dap.run(configs[1])
  return true
end

return Dap
