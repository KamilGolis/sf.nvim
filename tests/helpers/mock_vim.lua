--- Mock Neovim APIs for testing without a real Neovim UI or SF CLI.

local M = {}

local _orig = {}

M.calls = {
  system = {},
  notify = {},
  fn = {},
  uv = {},
  sign_place = {},
  sign_unplace = {},
  sign_define = {},
  api = {},
}

function M.reset_calls()
  for k, v in pairs(M.calls) do M.calls[k] = {} end
end

--- Create a mock vim.system job handle.
-- Fires callbacks inline (on_stdout, on_exit, on_success/on_error)
-- so production code that passes callbacks via vim.system() sees
-- them execute immediately, no event loop dependency.
local function make_mock_system_job(...)
  local call_args = { ... }
  local command, cmd_args, opts

  -- Detect calling convention
  if type(call_args[1]) == "table" and type(call_args[2]) == "table" then
    -- vim.system({cmd, arg1, ...}, opts, callback?)
    command = call_args[1][1]
    cmd_args = {}
    for i = 2, #call_args[1] do table.insert(cmd_args, call_args[1][i]) end
    opts = call_args[2] or {}
  elseif type(call_args[1]) == "string" and type(call_args[2]) == "table" then
    -- vim.system(cmd, {args}, opts)
    command = call_args[1]
    cmd_args = call_args[2]
    opts = call_args[3] or {}
  else
    command = tostring(call_args[1])
    cmd_args = {}
    opts = {}
  end

  -- Merge callback from Neovim's third-arg callback form
  if call_args[3] and type(call_args[3]) == "function" then
    opts.on_exit = call_args[3]
  end

  local exit_code = opts.exit_code or 0
  local mock_stdout = opts.mock_stdout

  -- Record the system call
  table.insert(M.calls.system, { command = command, args = cmd_args, opts = opts })

  -- Build job handle early so callbacks can reference it if needed
  local job_handle = {
    command = command,
    args = cmd_args,
    opts = opts,
    _stdout = {},
    _stderr = {},
    _exit_code = exit_code,
    code = exit_code,  -- Neovim vim.system callback expects obj.code
  }
  function job_handle:result() return self._stdout end
  function job_handle:stderr_result() return self._stderr end
  function job_handle:start() end
  function job_handle:shutdown() end
  function job_handle:wait() return self._exit_code end

  -- Fire callbacks on the event loop so production code relying on
  -- vim.schedule / async on_exit behaves like a real Neovim session.
  local function schedule(fn)
    if fn then vim.schedule(fn) end
  end
  if opts.on_stdout and mock_stdout then
    local lines = type(mock_stdout) == "table" and mock_stdout or { mock_stdout }
    for _, line in ipairs(lines) do
      job_handle._stdout[#job_handle._stdout + 1] = line
      schedule(function() opts.on_stdout("", line) end)
    end
  end
  if opts.on_stderr and opts.mock_stderr then
    local lines = type(opts.mock_stderr) == "table" and opts.mock_stderr or { opts.mock_stderr }
    for _, line in ipairs(lines) do schedule(function() opts.on_stderr("", line) end) end
  end
  schedule(function() if opts.on_exit then opts.on_exit(job_handle, exit_code) end end)
  schedule(function() if opts.on_success and exit_code == 0 then opts.on_success(job_handle, exit_code) end end)
  schedule(function() if opts.on_error and exit_code ~= 0 then opts.on_error(job_handle, exit_code) end end)

  return job_handle
end

--- Override vim.system with mock.
function M.setup_system_mock()
  _orig.vim_system = vim.system
  vim.system = function(...) return make_mock_system_job(...) end
end

--- Helper: create mock system job directly.
function M.make_job(opts)
  opts = opts or {}
  return make_mock_system_job(opts.command or "sf", opts.args or {}, opts)
end

--- Setup mocks for vim.fn functions.
function M.setup_fn_mocks(overrides)
  if not _orig.vim_fn_exepath then _orig.vim_fn_exepath = vim.fn.exepath end
  if not _orig.vim_fn_fnamemodify then _orig.vim_fn_fnamemodify = vim.fn.fnamemodify end
  if not _orig.vim_fn_filereadable then _orig.vim_fn_filereadable = vim.fn.filereadable end
  if not _orig.vim_fn_getcwd then _orig.vim_fn_getcwd = vim.fn.getcwd end
  if not _orig.vim_fn_sign_place then _orig.vim_fn_sign_place = vim.fn.sign_place end
  if not _orig.vim_fn_sign_unplace then _orig.vim_fn_sign_unplace = vim.fn.sign_unplace end
  if not _orig.vim_fn_sign_define then _orig.vim_fn_sign_define = vim.fn.sign_define end
  if not _orig.vim_fn_readfile then _orig.vim_fn_readfile = vim.fn.readfile end
  if not _orig.vim_fn_mkdir then _orig.vim_fn_mkdir = vim.fn.mkdir end
  if not _orig.vim_fn_delete then _orig.vim_fn_delete = vim.fn.delete end
  if not _orig.vim_fn_localtime then _orig.vim_fn_localtime = vim.fn.localtime end

  overrides = overrides or {}
  if overrides.exepath ~= nil then
    vim.fn.exepath = function(name)
      table.insert(M.calls.fn, { name = "exepath", args = { name } })
      return type(overrides.exepath) == "function" and overrides.exepath(name) or overrides.exepath
    end
  end
  if overrides.fnamemodify ~= nil then
    vim.fn.fnamemodify = function(path, modifier)
      table.insert(M.calls.fn, { name = "fnamemodify", args = { path, modifier } })
      return type(overrides.fnamemodify) == "function" and overrides.fnamemodify(path, modifier) or overrides.fnamemodify
    end
  end
  if overrides.filereadable ~= nil then
    vim.fn.filereadable = function(path)
      table.insert(M.calls.fn, { name = "filereadable", args = { path } })
      return type(overrides.filereadable) == "function" and overrides.filereadable(path) or overrides.filereadable
    end
  end
  if overrides.getcwd ~= nil then
    vim.fn.getcwd = function()
      table.insert(M.calls.fn, { name = "getcwd", args = {} })
      return type(overrides.getcwd) == "function" and overrides.getcwd() or overrides.getcwd
    end
  end
  if overrides.nvim_buf_get_name ~= nil then
    _orig.vim_api_nvim_buf_get_name = vim.api.nvim_buf_get_name
    vim.api.nvim_buf_get_name = function(bufnr)
      table.insert(M.calls.api, { name = "nvim_buf_get_name", args = { bufnr } })
      return type(overrides.nvim_buf_get_name) == "function" and overrides.nvim_buf_get_name(bufnr) or overrides.nvim_buf_get_name
    end
  end
  if overrides.readfile ~= nil then
    vim.fn.readfile = function(path)
      table.insert(M.calls.fn, { name = "readfile", args = { path } })
      return type(overrides.readfile) == "function" and overrides.readfile(path) or overrides.readfile
    end
  end
  if overrides.sign_place ~= nil then
    vim.fn.sign_place = function(...)
      table.insert(M.calls.sign_place, { ... })
      return type(overrides.sign_place) == "function" and overrides.sign_place(...) or overrides.sign_place
    end
  end
  if overrides.sign_unplace ~= nil then
    vim.fn.sign_unplace = function(...)
      table.insert(M.calls.sign_unplace, { ... })
      return type(overrides.sign_unplace) == "function" and overrides.sign_unplace(...) or overrides.sign_unplace
    end
  end
  if overrides.sign_define ~= nil then
    vim.fn.sign_define = function(...)
      table.insert(M.calls.sign_define, { ... })
      return type(overrides.sign_define) == "function" and overrides.sign_define(...) or overrides.sign_define
    end
  end
end

--- Mock vim.notify.
function M.setup_notify_mock()
  _orig.vim_notify = vim.notify
  vim.notify = function(message, level)
    table.insert(M.calls.notify, { message = message, level = level })
  end
end

--- Setup all standard mocks at once.
function M.setup(opts)
  opts = opts or {}
  M.reset_calls()
  if opts.system ~= false then M.setup_system_mock() end
  if opts.notify ~= false then M.setup_notify_mock() end
  if opts.fn_overrides then M.setup_fn_mocks(opts.fn_overrides) end
end

--- Restore all original APIs.
function M.restore()
  if _orig.vim_system then vim.system = _orig.vim_system end
  if _orig.vim_notify then vim.notify = _orig.vim_notify end
  if _orig.vim_fn_exepath then vim.fn.exepath = _orig.vim_fn_exepath end
  if _orig.vim_fn_fnamemodify then vim.fn.fnamemodify = _orig.vim_fn_fnamemodify end
  if _orig.vim_fn_filereadable then vim.fn.filereadable = _orig.vim_fn_filereadable end
  if _orig.vim_fn_getcwd then vim.fn.getcwd = _orig.vim_fn_getcwd end
  if _orig.vim_fn_sign_place then vim.fn.sign_place = _orig.vim_fn_sign_place end
  if _orig.vim_fn_sign_unplace then vim.fn.sign_unplace = _orig.vim_fn_sign_unplace end
  if _orig.vim_fn_sign_define then vim.fn.sign_define = _orig.vim_fn_sign_define end
  if _orig.vim_fn_readfile then vim.fn.readfile = _orig.vim_fn_readfile end
  if _orig.vim_fn_mkdir then vim.fn.mkdir = _orig.vim_fn_mkdir end
  if _orig.vim_fn_delete then vim.fn.delete = _orig.vim_fn_delete end
  if _orig.vim_fn_localtime then vim.fn.localtime = _orig.vim_fn_localtime end
  if _orig.vim_api_nvim_buf_get_name then vim.api.nvim_buf_get_name = _orig.vim_api_nvim_buf_get_name end
  M.reset_calls()
end

--- Assert vim.system was called.
function M.assert_system_called(count)
  if count ~= nil and #M.calls.system ~= count then
    error("Expected " .. tostring(count) .. " vim.system call(s), got " .. #M.calls.system)
  end
  return #M.calls.system > 0
end

function M.assert_no_system_call()
  if #M.calls.system ~= 0 then
    error("Expected no vim.system calls, got " .. #M.calls.system)
  end
end

function M.get_system_calls() return M.calls.system end
function M.get_notify_calls() return M.calls.notify end

function M.clear()
  M.reset_calls()
  _orig = {}
end

return M
