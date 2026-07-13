--- sf-nvim DAP integration for Apex Replay Debugger
-- @license MIT

local Config = require("sf.config")
local PathUtils = require("sf.core.path_utils")

local Dap = {}

--- Setup nvim-dap adapter and configurations for Apex Replay Debugger
--- @param dap_opts table Options: { adapter_path, port }
function Dap.setup(dap_opts)
  dap_opts = dap_opts or {}

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
        for _, client in pairs(vim.lsp.get_clients({ name = "apex_ls" })) do
          local done = false
          local result = nil

          client.request("debugger/lineBreakpoints", {}, function(err, res)
            if err then
              vim.notify("Apex LSP breakpoint info error: " .. vim.inspect(err), vim.log.levels.ERROR)
            end
            done = true
            result = res
          end)

          vim.wait(5000, function()
            return done
          end, 100)

          return result
        end

        vim.notify("Apex Language Server is not available.", vim.log.levels.WARN)
      end,
      projectPath = function()
        return vim.fn.getcwd()
      end,
    },
  }
end

--- Copy a log file to the DAP debug directory (dap/current.log)
--- @param log_path string Path to the log file to copy
--- @return boolean success
function Dap.copy_log_for_debug(log_path)
  local dest_dir = Config:get_options().dap_log_dir
  local dest_file = PathUtils.join(dest_dir, "current.log")

  vim.fn.mkdir(dest_dir, "p")

  local lines = vim.fn.readfile(log_path)

  if #lines == 0 then
    vim.notify("DAP: log file is empty or unreadable", vim.log.levels.ERROR)
    return false
  end

  vim.fn.writefile(lines, dest_file)
  vim.notify("DAP: log copied to " .. dest_file, vim.log.levels.INFO)

  return true
end

return Dap
