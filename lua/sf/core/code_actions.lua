--- sf-nvim SF actions module
-- Uses a fake in-process LSP client (pattern from core/progress.lua)
-- to provide code actions without requiring an external LSP server.
-- @license MIT

local Const = require("sf.const")

local M = {}

local null_client_id = nil

--- Dispatch a code action command by ID.
--- @param cmd string The command identifier (e.g. "sf.test.runClass")
local function dispatch_command(cmd)
  local TestRunner = require("sf.test.runner")

  if cmd == Const.SF_ACTIONS.CMD_RUN_CLASS then
    TestRunner.run_current_tests("class")
  elseif cmd == Const.SF_ACTIONS.CMD_RUN_METHOD then
    TestRunner.run_current_tests("method")
  elseif cmd == Const.SF_ACTIONS.CMD_RUN_CLASS_COVERAGE then
    TestRunner.run_coverage_at_cursor("class")
  elseif cmd == Const.SF_ACTIONS.CMD_RUN_METHOD_COVERAGE then
    TestRunner.run_coverage_at_cursor("method")
  end
end

--- Factory for an in-process LSP RPC client.
--- The returned object satisfies vim.lsp.rpc.PublicClient.
--- @param _dispatchers table (unused)
--- @param _config table (unused)
--- @return vim.lsp.rpc.PublicClient
local function create_rpc_client(_dispatchers, _config)
  local closing = false

  return {
    request = function(method, params, callback, _notify_reply_callback)
      if method == "initialize" then
        callback(nil, {
          capabilities = {
            codeActionProvider = true,
            executeCommandProvider = {
              commands = {
                Const.SF_ACTIONS.CMD_RUN_CLASS,
                Const.SF_ACTIONS.CMD_RUN_METHOD,
                Const.SF_ACTIONS.CMD_RUN_CLASS_COVERAGE,
                Const.SF_ACTIONS.CMD_RUN_METHOD_COVERAGE,
              },
            },
          },
          serverInfo = { name = Const.SF_ACTIONS.SERVER_NAME },
        })
        return true, 0
      end

      if method == "shutdown" then
        callback(nil, vim.NIL)
        return true, 0
      end

      if method == "textDocument/codeAction" then
        local bufnr = vim.uri_to_bufnr(params.textDocument.uri)
        local actions = M.get_actions_for_buffer(bufnr)

        callback(nil, actions)
        return true, 0
      end

      if method == "workspace/executeCommand" then
        dispatch_command(params.command)
        callback(nil, vim.NIL)
        return true, 0
      end

      -- Unknown request
      callback({ code = -32601, message = "Method not found: " .. tostring(method) })
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

--- Ensure the fake LSP client is started (lazily, once).
--- @return boolean true if available
local function ensure_client()
  if null_client_id and vim.lsp.get_client_by_id(null_client_id) then
    return true
  end

  local ok, client_id = pcall(vim.lsp.start, {
    name = Const.SF_ACTIONS.CLIENT_NAME,
    cmd = create_rpc_client,
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

--- Get applicable SF test actions for a buffer.
--- @param bufnr number
--- @return table[] LSP code action objects
function M.get_actions_for_buffer(bufnr)
  local TestRunner = require("sf.test.runner")

  if not TestRunner.is_test_class_buf(bufnr) then
    return {}
  end

  local actions = {
    {
      title = Const.SF_ACTIONS.TITLE_RUN_TEST_CLASS,
      kind = "refactor.extract",
      command = { command = Const.SF_ACTIONS.CMD_RUN_CLASS, title = Const.SF_ACTIONS.TITLE_RUN_TEST_CLASS },
    },
    {
      title = Const.SF_ACTIONS.TITLE_RUN_TEST_CLASS_COVERAGE,
      kind = "refactor.extract",
      command = {
        command = Const.SF_ACTIONS.CMD_RUN_CLASS_COVERAGE,
        title = Const.SF_ACTIONS.TITLE_RUN_TEST_CLASS_COVERAGE,
      },
    },
  }

  -- Check cursor position for method-level actions
  local node = TestRunner.get_node_at_cursor()

  if node and TestRunner.find_method_name(node) then
    table.insert(actions, 1, {
      title = Const.SF_ACTIONS.TITLE_RUN_TEST_METHOD,
      kind = "refactor.extract",
      command = {
        command = Const.SF_ACTIONS.CMD_RUN_METHOD,
        title = Const.SF_ACTIONS.TITLE_RUN_TEST_METHOD,
      },
    })
    table.insert(actions, 2, {
      title = Const.SF_ACTIONS.TITLE_RUN_TEST_METHOD_COVERAGE,
      kind = "refactor.extract",
      command = {
        command = Const.SF_ACTIONS.CMD_RUN_METHOD_COVERAGE,
        title = Const.SF_ACTIONS.TITLE_RUN_TEST_METHOD_COVERAGE,
      },
    })
  end

  return actions
end

--- Show test actions via snacks picker (standalone, no LSP needed).
function M.show_actions()
  local actions = M.get_actions_for_buffer(vim.api.nvim_get_current_buf())

  if #actions == 0 then
    vim.notify(Const.SF_ACTIONS.NO_ACTIONS, vim.log.levels.WARN)
    return
  end

  local items = {}
  for _, action in ipairs(actions) do
    table.insert(items, { text = action.title, action = action })
  end

  require("snacks").picker({
    title = Const.SF_ACTIONS.PICKER_TITLE,
    items = items,
    layout = { preset = "vscode" },
    format = function(item)
      return { { item.text } }
    end,
    confirm = function(picker, item)
      picker:close()
      if item and item.action then
        dispatch_command(item.action.command.command)
      end
    end,
  })
end

--- Setup the fake LSP client and BufEnter autocmd to attach it
--- to Apex test class buffers.
function M.setup()
  if not ensure_client() then
    vim.notify(Const.SF_ACTIONS.CLIENT_FAILED, vim.log.levels.WARN)
    return
  end

  vim.api.nvim_create_autocmd("BufEnter", {
    group = vim.api.nvim_create_augroup(Const.SF_ACTIONS.AUGROUP, { clear = true }),
    pattern = "*.cls",
    callback = function(args)
      local bufnr = args.buf

      if vim.bo[bufnr].filetype ~= "apex" then
        return
      end

      local TestRunner = require("sf.test.runner")

      if not TestRunner.is_test_class_buf(bufnr) then
        -- Detach if previously attached to a non-test class buffer
        if null_client_id and vim.lsp.buf_is_attached(bufnr, null_client_id) then
          vim.lsp.buf_detach_client(bufnr, null_client_id)
        end
        return
      end

      -- Attach fake client to this test class buffer
      if null_client_id and not vim.lsp.buf_is_attached(bufnr, null_client_id) then
        vim.lsp.buf_attach_client(bufnr, null_client_id)
      end
    end,
  })
end

return M
