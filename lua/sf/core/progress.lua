--- Progress display using Neovim's built-in LSP $/progress mechanism.
---
--- Replaces Fidget.nvim with a zero-dependency alternative:
--- an in-process fake LSP client that forwards progress events into
--- `vim.lsp.status()` for consumption in the statusline. No server
--- process is spawned — the client is created entirely in-process.

local M = {}

local null_client_id = nil
local token_counter = 0
local has_lsp_status = nil -- lazily resolved

--- Check whether Neovim's LSP progress API is available.
--- @return boolean
local function check_lsp_status_available()
  if has_lsp_status == nil then
    has_lsp_status = type(vim.lsp.status) == "function"
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
      report = function(_) end,
      finish = function() end,
    }
  end

  local token = "sf_" .. token_counter
  token_counter = token_counter + 1

  local ctx = {
    client_id = null_client_id,
    method = "$/progress",
  }

  -- Notify begin
  pcall(vim.lsp.handlers["$/progress"], nil, {
    token = token,
    value = {
      kind = "begin",
      title = params.title,
      percentage = 0,
    },
  }, ctx)

  return {
    report = function(report_params)
      local value = { kind = "report" }
      if report_params.message then
        value.message = report_params.message
      end
      if report_params.percentage ~= nil then
        value.percentage = report_params.percentage
      end
      pcall(vim.lsp.handlers["$/progress"], nil, {
        token = token,
        value = value,
      }, ctx)
    end,
    finish = function()
      pcall(vim.lsp.handlers["$/progress"], nil, {
        token = token,
        value = { kind = "end" },
      }, ctx)
    end,
  }
end

return M
