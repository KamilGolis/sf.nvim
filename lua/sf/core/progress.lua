--- Progress display using Neovim's built-in LSP $/progress mechanism.
---
--- Replaces Fidget.nvim with a zero-dependency alternative:
--- an in-process fake LSP client that forwards progress events into
--- `vim.lsp.status()` for consumption in the statusline. No server
--- process is spawned — the client is created entirely in-process.

--- @class SfExecuteCallbacks
--- @field on_complete fun(parsed: table|nil, err: string|nil, raw_stdout: string|nil)
--- @field on_stdout? fun(err: string|nil, data: string|nil)
--- @field on_stderr? fun(err: string|nil, data: string|nil)
local M = {}
local Config = require("sf.config")
local Log = require("sf.core.log")

local null_client_id = nil
local token_counter = 0
local has_lsp_status = nil -- lazily resolved

--- Check whether Neovim's LSP progress API is available.
--- @return boolean
local function check_lsp_status_available()
  if has_lsp_status == nil then
    has_lsp_status = type(vim.lsp.status) == "function" and type(vim.lsp.handlers["$/progress"]) == "function"
  end

  return has_lsp_status
end

--- Factory for an in-process LSP RPC client that only handles the
--- initialize handshake. No child process is spawned.
---
--- The returned object satisfies the `vim.lsp.rpc.PublicClient` interface.
---
--- @param _dispatchers vim.lsp.rpc.Dispatchers (unused — no server→client messages)
--- @param _config vim.lsp.ClientConfig (unused)
--- @return vim.lsp.rpc.PublicClient
local function create_rpc_client(_dispatchers, _config)
  local closing = false

  return {
    request = function(method, _params, callback, _notify_reply_callback)
      if method == "initialize" then
        callback(nil, {
          capabilities = vim.empty_dict(),
          serverInfo = { name = "sf.nvim" },
        })
        return true, 0
      end

      if method == "shutdown" then
        callback(nil, vim.NIL)
        return true, 0
      end
      --
      -- Unknown request: return error
      callback({
        code = -32601,
        message = "Method not found: " .. tostring(method),
      })

      return true, 0
    end,
    notify = function(method, _params)
      if method == "exit" then
        closing = true
      end

      return true
    end,
    is_closing = function()
      return closing
    end,
    terminate = function()
      closing = true
    end,
  }
end

--- Ensure the null LSP client is available.
--- Lazily creates it on first call using an in-process RPC factory.
--- @return boolean true if the client is available
local function ensure_client()
  if null_client_id and vim.lsp.get_client_by_id(null_client_id) then
    return true
  end

  if not check_lsp_status_available() then
    return false
  end

  local ok, client_id = pcall(vim.lsp.start, {
    name = "sf-progress",
    cmd = create_rpc_client, -- function, not string[] — no process spawned
    root_dir = vim.fn.getcwd(),
    capabilities = vim.lsp.protocol.make_client_capabilities(),
    on_init = function(client)
      client.server_capabilities = client.server_capabilities or {}
      client.server_capabilities.workDoneProgressProvider = true
    end,
    on_exit = function()
      null_client_id = nil
    end,
  })

  if not ok or not client_id then
    null_client_id = nil
    return false
  end

  null_client_id = client_id

  return true
end

--- Create a progress handle compatible with the current Fidget-like API.
---
--- The returned handle has `report({message?, percentage?})` and `finish()`
--- methods. If the LSP progress mechanism is unavailable, a no-op handle
--- is returned.
---
--- @param params table { title: string }
--- @return table { report: fun(table), finish: fun() }
function M.create_handle(params)
  if not ensure_client() then
    return {
      report = function(self, _) end,
      finish = function(self) end,
    }
  end

  -- Ensure client is attached to the current buffer so progress notifications
  -- are visible to UI plugins (fidget.nvim, noice.nvim, etc.)
  if null_client_id and not vim.lsp.buf_is_attached(0, null_client_id) then
    vim.lsp.buf_attach_client(0, null_client_id)
  end

  local token = "sf_" .. token_counter
  token_counter = token_counter + 1

  local ctx = {
    client_id = null_client_id,
    method = "$/progress",
  }

  -- Notify begin
  local handle_title = params.title

  vim.lsp.handlers["$/progress"](nil, {
    token = token,
    value = {
      kind = "begin",
      title = params.title,
      percentage = 0,
    },
  }, ctx)

  do
    local status = vim.lsp.status()
    local diag_msg = string.format(
      "[progress diag] ensure_client=%s client_id=%d status='%s'",
      tostring(ensure_client()),
      null_client_id or -1,
      status or "nil"
    )
    Log.deb(diag_msg)
    if Config:get_options().debug_inspect then
      vim.notify(diag_msg, vim.log.levels.INFO)
    end
  end

  return {
    report = function(self, report_params)
      local value = {
        kind = "report",
        title = handle_title,
      }

      if report_params.message then
        value.message = report_params.message
      end

      if report_params.percentage ~= nil then
        value.percentage = report_params.percentage
      end

      Log.deb("[progress] report", { message = report_params.message, percentage = report_params.percentage })

      vim.lsp.handlers["$/progress"](nil, {
        token = token,
        value = value,
        percentage = value.percentage,
      }, ctx)
    end,

    finish = function(self)
      Log.deb("[progress] finish", handle_title)
      vim.lsp.handlers["$/progress"](nil, {
        token = token,
        value = { kind = "end", title = handle_title },
      }, ctx)
    end,
  }
end

--- Run an sf CLI command asynchronously with an LSP progress spinner,
--- parse its JSON output, and deliver the result to a callback.
---
--- The spinner begins when the command starts and finishes when it exits.
--- The callback is always invoked on the main thread (via vim.schedule).
---
--- @param args string[] CLI arguments to pass after "sf" (e.g. {"--version", "--json"})
--- @param title string Label for the LSP progress spinner
--- @param callbacks SfExecuteCallbacks Callback table with on_complete, on_stdout?, on_stderr?
function M.sf_execute(args, title, callbacks)
  vim.validate({
    args = { args, "table" },
    title = { title, "string" },
    callbacks = { callbacks, "table" },
  })

  local handle = M.create_handle({ title = title })
  handle:report({ message = title, percentage = 0 })
  local stdout_lines = {}

  local opts = { text = true }

  opts.stdout = function(err, data)
    if data then
      table.insert(stdout_lines, data)
    end

    if callbacks.on_stdout then
      vim.schedule(function()
        callbacks.on_stdout(err, data)
      end)
    end
  end

  if callbacks.on_stderr then
    opts.stderr = function(err, data)
      vim.schedule(function()
        callbacks.on_stderr(err, data)
      end)
    end
  end

  local cmd = { Config:get_options().sf_cli_path or "sf" }

  for _, arg in ipairs(args) do
    table.insert(cmd, arg)
  end

  vim.system(cmd, opts, function(obj)
    vim.schedule(function()
      handle:finish()

      local stdout = table.concat(stdout_lines, "")
      -- Failure mode 1: non-zero exit AND empty stdout → pass stderr as error
      if obj.code ~= 0 and (not stdout or stdout == "") then
        callbacks.on_complete(nil, obj.stderr or "Command failed", stdout)
        return
      end

      -- Failure mode 2: stdout is not valid JSON
      local ok, parsed = pcall(vim.json.decode, stdout)
      if not ok or type(parsed) ~= "table" then
        callbacks.on_complete(nil, "JSON Parse Error", stdout)
        return
      end

      -- Success (or non-zero exit with parseable JSON — let caller decide)
      callbacks.on_complete(parsed, nil, stdout)
    end)
  end)
end

return M
