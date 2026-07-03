--- sf-nvim log analysis module
-- @license MIT

local Const = require("sf.const")
local PathUtils = require("sf.core.path_utils")

local Analyze = {}

-- Define highlight groups for log analysis views (idempotent, user-overridable)
vim.api.nvim_set_hl(0, "SfLogNoise", { default = true, link = "Comment" })
vim.api.nvim_set_hl(0, "SfLogSignal", { default = true, link = "Statement" })
vim.api.nvim_set_hl(0, "SfLogError", { default = true, link = "ErrorMsg" })
vim.api.nvim_set_hl(0, "SfLogInfo", { default = true, link = "Title" })
vim.api.nvim_set_hl(0, "SfLogCont", { default = true, link = "Conceal" })
vim.api.nvim_set_hl(0, "SfLogEvent", { default = true, link = "String" })
vim.api.nvim_set_hl(0, "SfLogLineNr", { default = true, link = "Number" })

--- Dedicated namespace for analysis buffer highlights
local NS = vim.api.nvim_create_namespace("sf.nvim.log.analysis")

-- Tag classification data for highlight group assignment

-- Exact match tag → category
local NOISE_TAGS = {
  VARIABLE_ASSIGNMENT = true,
  VARIABLE_SCOPE_BEGIN = true,
}

local ERROR_TAGS = {
  FATAL_ERROR = true,
  EXCEPTION_THROWN = true,
  EXCEPTION_EXITED = true,
  SYSTEM_EXCEPTION = true,
  ["FATAL fired"] = true,
  LIMIT_USAGE_FOR_NS = true,
  CUMULATIVE_LIMIT_USAGE = true,
}

local SIGNAL_PREFIXES = {
  "CODE_UNIT_",
  "METHOD_",
  "SYSTEM_METHOD_",
  "CONSTRUCTOR_",
  "SYSTEM_CONSTRUCTOR_",
  "SYSTEM_MODE_",
  "SOQL_EXECUTE_",
  "SOSL_EXECUTE_",
  "DML_",
  "STACK_FRAME_",
  "VALIDATION_",
  "WF_",
}

--- Determine the highlight group for a given tag.
--- @param tag string The extracted tag name
--- @return string|nil Highlight group name
function Analyze.tag_category(tag)
  if NOISE_TAGS[tag] then
    return "SfLogNoise"
  end

  if ERROR_TAGS[tag] then
    return "SfLogError"
  end

  for _, prefix in ipairs(SIGNAL_PREFIXES) do
    if tag:find(prefix, 1, true) == 1 then
      return "SfLogSignal"
    end
  end

  return "SfLogInfo"
end

--- Display rendered log analysis output in a scratch buffer.
--- @param log_id string The log ID for the buffer name
--- @param lines table Array of rendered text lines (with indent prefixes)
function Analyze.display_buffer(log_id, lines)
  local buf = vim.api.nvim_create_buf(false, true)

  vim.api.nvim_buf_set_name(buf, "sf-analysis://basic/" .. log_id)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)

  -- Apply rich per-segment highlights
  Analyze.apply_highlights(buf)

  -- Buffer options
  vim.bo[buf].filetype = Const.SF_CLI.APEX.LOG.ANALYZE.BUF_FILETYPE
  vim.bo[buf].buftype = "nofile"
  vim.bo[buf].swapfile = false
  vim.bo[buf].modifiable = false
  vim.bo[buf].bufhidden = "wipe"

  -- 'q' to close
  vim.api.nvim_buf_set_keymap(buf, "n", "q", "<Cmd>bd!<CR>", { nowait = true, silent = true, noremap = true })

  vim.api.nvim_set_current_buf(buf)
end

--- Apply per-segment rich highlights to a buffer.
--- Walks every line and applies extmarks for tags, line numbers, and event names.
--- @param buf number Buffer handle
function Analyze.apply_highlights(buf)
  local all_lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)

  for line_idx, line in ipairs(all_lines) do
    local i = line_idx - 1 -- 0-indexed for highlight API

    if line == "" then
      goto continue
    end

    local indent_end = line:find("%S")

    if not indent_end then
      goto continue
    end

    local rest = line:sub(indent_end)
    local pipe1 = rest:find("|", 1, true)

    if not pipe1 then
      -- No pipe: continuation line — apply SfLogCont to the whole content
      vim.hl.range(buf, NS, "SfLogCont", { i, indent_end - 1 }, { i, -1 })
      goto continue
    end

    local tag = rest:sub(1, pipe1 - 1)
    local tag_hl = Analyze.tag_category(tag)

    -- Highlight tag from indent_end to just before the first `|`
    vim.hl.range(buf, NS, tag_hl, { i, indent_end - 1 }, { i, indent_end + pipe1 - 2 })

    -- After first `|` — look for `[N]` or `[EXTERNAL]`
    local after_tag = rest:sub(pipe1 + 1)
    local ln_start, ln_end = after_tag:find("%[[%w]+%]")

    if ln_start then
      -- position right after first `|`
      local base_col = indent_end + pipe1

      -- Highlight the line number bracket
      vim.hl.range(buf, NS, "SfLogLineNr", { i, base_col + ln_start - 1 }, { i, base_col + ln_end })
      -- Event name: segment after `[N]|`

      local name_start = ln_end + 1

      if after_tag:sub(name_start, name_start) == "|" then
        name_start = name_start + 1
        local name_end = after_tag:find("|", name_start, true)

        if name_end then
          vim.hl.range(buf, NS, "SfLogEvent", { i, base_col + name_start - 1 }, { i, base_col + name_end - 1 })
        else
          vim.hl.range(buf, NS, "SfLogEvent", { i, base_col + name_start - 1 }, { i, -1 })
        end
      end
    end

    ::continue::
  end
end

--- Run basic analysis on a selected log.
--- Picks from cached log list, ensures the raw log file is on disk,
--- checks for cached rendered output, then displays the tree view.
function Analyze.basic()
  local LogList = require("sf.log.list")
  local Config = require("sf.config")
  local log_dir = Config:get_options().log_dir

  LogList.pick_cached_logs(function(item)
    LogList.ensure_log_file(item, function(log_path)
      local log_id = PathUtils.get_filename(log_path):gsub("%.log$", "")
      local cached_log = PathUtils.join(log_dir, log_id .. "-basic.log")
      local raw_stat = vim.uv.fs_stat(log_path)
      local cached_stat = vim.uv.fs_stat(cached_log)

      if cached_stat and raw_stat and cached_stat.mtime.sec >= raw_stat.mtime.sec then
        local lines = vim.fn.readfile(cached_log)

        if lines and #lines > 0 then
          Analyze.display_buffer(log_id, lines)
          return
        end
      end

      require("sf.log.analysis.basic").render(log_path)
    end)
  end)
end

return Analyze
