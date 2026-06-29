--- sf-nvim log analysis basic view — tree renderer
-- @license MIT

local Config = require("sf.config")
local Const = require("sf.const")
local PathUtils = require("sf.core.path_utils")

local Basic = {}

--- Determine the highlight group for a given tag via analyze module.
--- @param tag string The extracted tag name
--- @return string|nil Highlight group name
local function category_for(tag)
  return require("sf.log.analyze").tag_category(tag)
end

-- Tag classification sets used by parse() for tree indentation
local ENTRY_SET = {
  CODE_UNIT_STARTED = true,
  SYSTEM_METHOD_ENTRY = true,
  METHOD_ENTRY = true,
  CONSTRUCTOR_ENTRY = true,
  SYSTEM_CONSTRUCTOR_ENTRY = true,
  EXECUTION_STARTED = true,
  VALIDATION_RULE = true,
  WF_CRITERIA_BEGIN = true,
  WF_RULE_EVAL_BEGIN = true,
}

local EXIT_SET = {
  CODE_UNIT_FINISHED = true,
  SYSTEM_METHOD_EXIT = true,
  METHOD_EXIT = true,
  CONSTRUCTOR_EXIT = true,
  SYSTEM_CONSTRUCTOR_EXIT = true,
  EXECUTION_FINISHED = true,
  WF_CRITERIA_END = true,
  WF_RULE_EVAL_END = true,
}

local SKIP_SET = {
  HEAP_ALLOCATE = true,
  STATEMENT_EXECUTE = true,
  SYSTEM_MODE_ENTER = true,
  SYSTEM_MODE_EXIT = true,
}

-- Tags whose content after the first `|` should be split onto continuation lines
local FORMULA_SPLIT_TAGS = {
  VALIDATION_FORMULA = true,
  WF_RULE_FILTER = true,
  WF_FORMULA = true,
}

-- Tags that render at current indent, then decrease indent (opposite of ENTRY_SET)
local POST_EXIT_SET = {
  VALIDATION_PASS = true,
  VALIDATION_FAIL = true,
}
--- Parse a raw Salesforce debug log into rendered tree lines and highlight groups.
--- @param log_path string Path to the raw .log file
--- @return table lines Array of rendered text lines (with indent prefixes)
--- @return table hls Array of highlight group names or nil, one per line
function Basic.parse(log_path)
  local raw_lines = vim.fn.readfile(log_path)
  local lines = {}
  local hls = {}

  local indent = 0
  local last_event_indent = -1
  local last_event_category = nil
  local formula_active = false
  local vars_split = false

  -- Regex: timestamp digits.digit (number)|
  local line_pat = "^(%d%d:%d%d:%d%d%.%d+)%s+%((%d+)%)|(.*)$"

  for _, raw in ipairs(raw_lines) do
    local ts, num, content = raw:match(line_pat)

    if raw:match("^%s*$") then
      -- Empty/whitespace-only — emit blank line, no state change
      table.insert(lines, "")
      table.insert(hls, nil)
      -- do not update indent, last_event_indent, or last_event_category
    elseif ts then
      -- Tagged event line
      local tag = content:match("^([^|]+)")

      -- When a new tagged line arrives, cancel any active formula block
      formula_active = false
      vars_split = false

      if SKIP_SET[tag] then
        -- fall through: no output, no indent/category change
      elseif ENTRY_SET[tag] then
        table.insert(lines, string.rep(Const.SF_CLI.APEX.LOG.ANALYZE.INDENT_UNIT, indent) .. content)
        table.insert(hls, category_for(tag))
        last_event_indent = indent
        last_event_category = category_for(tag)
        indent = indent + 1
      elseif EXIT_SET[tag] then
        indent = math.max(indent - 1, 0)
        table.insert(lines, string.rep(Const.SF_CLI.APEX.LOG.ANALYZE.INDENT_UNIT, indent) .. content)
        table.insert(hls, category_for(tag))
        last_event_indent = indent
        last_event_category = category_for(tag)
      elseif FORMULA_SPLIT_TAGS[tag] then
        -- Emit TAG| header and set formula_active for continuation lines
        local prefix = string.rep(Const.SF_CLI.APEX.LOG.ANALYZE.INDENT_UNIT, indent)
        table.insert(lines, prefix .. tag .. "|")
        table.insert(hls, category_for(tag))
        last_event_indent = indent
        last_event_category = category_for(tag)
        formula_active = true

        -- Emit formula body from the tagged line as continuation
        local formula_body = content:sub(#tag + 2) -- skip "TAG|"

        if #formula_body > 0 then
          if tag == "VALIDATION_FORMULA" or tag == "WF_FORMULA" then
            local last_pipe = formula_body:find("|[^|]*$")

            if last_pipe then
              -- Split: expression before last |, variables after
              local expr = formula_body:sub(1, last_pipe - 1)
              local vars = formula_body:sub(last_pipe + 1)

              if #expr > 0 then
                table.insert(lines, prefix .. Const.SF_CLI.APEX.LOG.ANALYZE.INDENT_UNIT .. expr)
                table.insert(hls, "SfLogCont")
              end

              table.insert(lines, prefix .. Const.SF_CLI.APEX.LOG.ANALYZE.INDENT_UNIT .. "|")
              table.insert(hls, "SfLogCont")

              if #vars > 0 then
                local parts = {}

                for part in vars:gmatch("[^,]+") do
                  parts[#parts + 1] = part:match("^%s*(.-)%s*$")
                end

                for j = 1, #parts do
                  local suffix = (j < #parts) and " ," or ""
                  table.insert(lines, prefix .. Const.SF_CLI.APEX.LOG.ANALYZE.INDENT_UNIT .. parts[j] .. suffix)
                  table.insert(hls, "SfLogCont")
                end
              end

              vars_split = true
            else
              table.insert(lines, prefix .. Const.SF_CLI.APEX.LOG.ANALYZE.INDENT_UNIT .. formula_body)
              table.insert(hls, "SfLogCont")
            end
          else
            table.insert(lines, prefix .. Const.SF_CLI.APEX.LOG.ANALYZE.INDENT_UNIT .. formula_body)
            table.insert(hls, "SfLogCont")
          end
        end
      elseif POST_EXIT_SET[tag] then
        table.insert(lines, string.rep(Const.SF_CLI.APEX.LOG.ANALYZE.INDENT_UNIT, indent) .. content)
        table.insert(hls, category_for(tag))

        last_event_indent = indent
        last_event_category = category_for(tag)
        indent = math.max(indent - 1, 0)
      else
        table.insert(lines, string.rep(Const.SF_CLI.APEX.LOG.ANALYZE.INDENT_UNIT, indent) .. content)
        table.insert(hls, category_for(tag))

        last_event_indent = indent
        last_event_category = category_for(tag)
      end
    else
      -- Continuation line (no timestamp match)
      local cont_indent = (last_event_indent < 0) and 0 or (last_event_indent + 1)
      local cont_hl = (last_event_category == "SfLogError") and "SfLogError" or "SfLogCont"
      local cont_prefix = string.rep(Const.SF_CLI.APEX.LOG.ANALYZE.INDENT_UNIT, cont_indent)

      if formula_active and not vars_split then
        local last_pipe = raw:find("|[^|]*$")

        if last_pipe then
          local expr = raw:sub(1, last_pipe - 1)
          local vars = raw:sub(last_pipe + 1)

          if #expr > 0 then
            table.insert(lines, cont_prefix .. expr)
            table.insert(hls, "SfLogCont")
          end

          table.insert(lines, cont_prefix .. "|")
          table.insert(hls, "SfLogCont")

          if #vars > 0 then
            local parts = {}

            for part in vars:gmatch("[^,]+") do
              parts[#parts + 1] = part:match("^%s*(.-)%s*$")
            end

            for j = 1, #parts do
              local suffix = (j < #parts) and " ," or ""
              table.insert(lines, cont_prefix .. parts[j] .. suffix)
              table.insert(hls, "SfLogCont")
            end
          end

          vars_split = true
        else
          table.insert(lines, cont_prefix .. raw)
          table.insert(hls, cont_hl)
        end
      else
        table.insert(lines, cont_prefix .. raw)
        table.insert(hls, cont_hl)
      end
      -- do not change indent, last_event_indent, or last_event_category
    end
  end

  return lines, hls
end

function Basic.render(log_path)
  local log_id = PathUtils.get_filename(log_path):gsub("%.log$", "")
  local lines = Basic.parse(log_path)

  -- Save cache to log_dir/<log_id>-basic.log
  local log_dir = Config:get_options().log_dir

  vim.fn.mkdir(log_dir, "p")
  local cached_log = PathUtils.join(log_dir, log_id .. "-basic.log")

  vim.fn.writefile(lines, cached_log)

  -- Display
  require("sf.log.analyze").display_buffer(log_id, lines)
end

return Basic
