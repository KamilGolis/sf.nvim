--- sf-nvim diff display module.
-- Opens Neovim native diff views using in-memory scratch buffers.
-- @license MIT

local Log = require("sf.core.log")

local Display = {}
local diff_augroup = nil

--- Ensure the diff cleanup autocmd group exists.
--- @return number
local function ensure_augroup()
  if not diff_augroup then
    diff_augroup = vim.api.nvim_create_augroup("SFDiffCleanup", { clear = true })
  end

  return diff_augroup
end

--- Open a Neovim native diff view between local file and in-memory server content.
--- Server content is shown in a scratch buffer with `sf://` scheme to avoid LSP workspace conflicts.
--- Opens in a new tab with a vertical split: server (left, read-only) vs local (right).
--- @param local_file string Path to the local file on disk
--- @param server_content string Raw content of the retrieved server file (from memory)
--- @param server_label string Short label for the scratch buffer name (e.g. filename)
function Display.open_file_diff(local_file, server_content, server_label)
  if vim.fn.filereadable(local_file) ~= 1 then
    Log.notify("Local file not found: " .. local_file, vim.log.levels.ERROR)
    return
  end

  -- Create scratch buffer with server content before opening the tab
  -- so timers/callbacks can't race between the two
  local lines = vim.split(server_content, "\n", { plain = true })

  local server_buf = vim.api.nvim_create_buf(false, true)
  vim.bo[server_buf].buftype = "nofile"
  vim.bo[server_buf].bufhidden = "wipe"
  vim.api.nvim_buf_set_name(server_buf, "sf://" .. server_label .. " (Server)")
  vim.api.nvim_buf_set_lines(server_buf, 0, -1, false, lines)

  -- Open a new tab with the local file — clean 2-pane diff, no extra windows
  vim.cmd("tabedit " .. vim.fn.fnameescape(local_file))
  local local_buf = vim.api.nvim_get_current_buf()
  vim.cmd("diffthis")

  -- Apply server filetype from local buffer
  vim.bo[server_buf].filetype = vim.bo[local_buf].filetype

  -- Create vertical split and replace with the scratch buffer
  vim.cmd("leftabove vsplit")
  vim.api.nvim_win_set_buf(0, server_buf)
  vim.cmd("diffthis")

  -- Set server buffer to read-only
  vim.api.nvim_set_option_value("readonly", true, { buf = server_buf })
  vim.api.nvim_set_option_value("modifiable", false, { buf = server_buf })

  -- Unfold all folds on both buffers so diff is fully visible
  vim.api.nvim_buf_call(server_buf, function()
    vim.cmd("normal! zR")
  end)
  vim.api.nvim_buf_call(local_buf, function()
    vim.cmd("normal! zR")
  end)

  -- Synchronize scrolling between both diff windows
  local local_win = vim.fn.win_getid(vim.fn.bufwinnr(local_buf))
  local server_win = vim.fn.win_getid(vim.fn.bufwinnr(server_buf))
  vim.api.nvim_set_option_value("scrollbind", true, { win = server_win })
  vim.api.nvim_set_option_value("scrollbind", true, { win = local_win })

  -- Focus on the local buffer (right side) for convenience
  vim.api.nvim_set_current_win(local_win)

  -- Register cleanup autocmds
  local augroup = ensure_augroup()

  -- Close server buffer when local buffer is wiped
  vim.api.nvim_create_autocmd("BufWipeout", {
    group = augroup,
    buffer = local_buf,
    once = true,
    callback = function()
      if vim.api.nvim_buf_is_valid(server_buf) then
        vim.api.nvim_buf_delete(server_buf, { force = true })
      end
    end,
  })
end

return Display
