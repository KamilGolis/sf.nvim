--- sf-nvim debug level management module
-- @license MIT

local Config = require("sf.config")
local Const = require("sf.const")
local DebugPicker = require("sf.debug.picker")
local DebugUtils = require("sf.debug.utils")
local JobUtils = require("sf.core.job_utils")
local Log = require("sf.core.log")

local Level = {}

--- Get default field values for a new debug level.
--- @return table { DeveloperName = "...", MasterLabel = "...", ... }
local function get_default_fields()
  local fields = {}

  for _, fd in ipairs(Const.DEBUG_LEVEL_FIELDS) do
    fields[fd.name] = fd.default
  end

  fields.MasterLabel = fields.DeveloperName
  return fields
end

--- Get field values from an existing DebugLevel record.
--- @param dl table DebugLevel record from the API
--- @return table { DeveloperName = "...", ApexCode = "...", ... }
local function record_to_fields(dl)
  local fields = {}

  for _, fd in ipairs(Const.DEBUG_LEVEL_FIELDS) do
    local val = dl[fd.name]

    if val then
      fields[fd.name] = val
    else
      fields[fd.name] = fd.default
    end
  end

  fields.MasterLabel = dl.MasterLabel or fields.DeveloperName
  return fields
end

--- Render the debug level edit buffer.
--- @param buf number Buffer handle
--- @param fields table Current field values
--- @param is_edit boolean True if editing existing level (DeveloperName read-only)
local function render_buffer(buf, fields, is_edit)
  local lines = {}
  local line_map = {}

  for i, fd in ipairs(Const.DEBUG_LEVEL_FIELDS) do
    local label = fd.label
    local value = fields[fd.name] or fd.default

    table.insert(lines, "  " .. label)

    local value_line
    if fd.readonly_edit and is_edit then
      value_line = "  > " .. value .. " (read-only)"
    else
      value_line = "  > " .. value
    end
    table.insert(lines, value_line)
    line_map[#lines] = i

    if fd.name == "DeveloperName" then
      table.insert(lines, "")
    end
  end

  -- Footer
  table.insert(lines, "")
  table.insert(
    lines,
    "  ────────────────────────────────────────────────────────────────"
  )
  table.insert(lines, "  Press <Enter> on a field to edit its value")
  table.insert(lines, "  Press <C-s> to save changes")
  table.insert(lines, "  Press q to close this buffer")

  vim.bo[buf].modifiable = true
  vim.bo[buf].readonly = false
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.b[buf].debug_level_line_map = line_map
  vim.bo[buf].modified = false
  vim.bo[buf].readonly = true
  vim.bo[buf].modifiable = false
end

--- Save the debug level buffer: serialize fields, persist JSON, run CLI create/update.
--- @param buf number Buffer handle
local function save_buffer(buf)
  -- Read current fields from buffer-local variable
  local fields = vim.b[buf].debug_level_fields
  -- "new" or "edit"
  local mode = vim.b[buf].debug_level_mode
  -- nil for new
  local record_id = vim.b[buf].debug_level_record_id
  local target_org = vim.b[buf].debug_level_target_org
  local executable_path = vim.b[buf].debug_level_executable_path
  local api_version = vim.b[buf].debug_level_api_version

  if not fields then
    vim.notify(Const.SF_CLI_MESSAGES.DEBUG_LEVEL_NO_FIELD_DATA, vim.log.levels.ERROR)
    return
  end

  if not target_org then
    vim.notify(Const.SF_CLI_MESSAGES.DEBUG_LEVEL_NO_TARGET_ORG, vim.log.levels.ERROR)
    return
  end

  if not executable_path then
    local cli_valid, path, err = JobUtils.validate_cli_installation(Config:get_options().sf_cli_path)

    if not cli_valid or not path then
      vim.notify(err or Const.SF_CLI_MESSAGES.NOT_FOUND, vim.log.levels.ERROR)
      return
    end

    executable_path = path
  end

  fields.MasterLabel = fields.DeveloperName

  DebugUtils.save_debug_level_json(fields)

  local value_string = DebugUtils.fields_to_value_string(fields)
  value_string = value_string .. " MasterLabel=" .. fields.DeveloperName

  local state = require("sf.core.state")
  if state.is_busy("debug") then
    vim.notify(Const.SF_CLI_MESSAGES.DEBUG_LEVEL_SAVE_IN_PROGRESS, vim.log.levels.WARN)
    return
  end
  state.start("debug")

  local context = JobUtils.create_progress_context(
    mode == "new" and Const.SF_CLI_MESSAGES.DEBUG_LEVEL_NEW_TITLE or Const.SF_CLI_MESSAGES.DEBUG_LEVEL_EDIT_TITLE,
    mode == "new" and Const.SF_CLI_MESSAGES.DEBUG_LEVEL_NEW_SUCCESS or Const.SF_CLI_MESSAGES.DEBUG_LEVEL_EDIT_SUCCESS,
    mode == "new" and Const.SF_CLI_MESSAGES.DEBUG_LEVEL_NEW_FAILED or Const.SF_CLI_MESSAGES.DEBUG_LEVEL_EDIT_FAILED
  )

  local args

  if mode == "new" then
    args = Const.get_record_create_args(target_org, "DebugLevel", value_string, api_version)
  else
    args = Const.get_record_update_args(target_org, "DebugLevel", value_string, record_id, api_version)
  end

  local job = JobUtils.create_cli_job(executable_path, args, {
    on_success = function(job, _)
      local result = table.concat(job:result(), "\n")
      Log.deb("Debug level save result:", result)

      local ok, parsed, _ = JobUtils.validate_json_response(result)

      if ok and parsed and parsed.status == 0 then
        context.handle:report({ message = context.success_message, percentage = 100 })
        context.handle:finish()
        state.finish("debug")

        vim.notify(context.success_message, vim.log.levels.INFO)
        pcall(vim.api.nvim_buf_delete, buf, { force = true })
      else
        Log.deb("save_buffer on_success non-zero status", parsed)

        local err_msg = Const.SF_CLI_MESSAGES.DEBUG_LEVEL_SAVE_FAILED

        if parsed and parsed.message then
          err_msg = parsed.message
        elseif parsed and parsed.result and parsed.result.errors and #parsed.result.errors > 0 then
          err_msg = parsed.result.errors[1]
        end

        JobUtils.handle_cli_error(1, context, err_msg)
        state.finish("debug")
      end
    end,
    on_error = function(job, return_val)
      local stderr_lines = job:stderr_result()
      local stderr_str = table.concat(stderr_lines, "\n")
      local stdout_lines = job:result()
      local stdout_str = table.concat(stdout_lines, "\n")
      local err_msg = Const.SF_CLI_MESSAGES.DEBUG_LEVEL_NEW_FAILED

      if stdout_str ~= "" then
        local ok, parsed, _ = JobUtils.validate_json_response(stdout_str)

        if ok and parsed and parsed.message then
          err_msg = parsed.message
        end
      end

      if err_msg == Const.SF_CLI_MESSAGES.DEBUG_LEVEL_NEW_FAILED and stderr_str ~= "" then
        local ok, parsed, _ = JobUtils.validate_json_response(stderr_str)

        if ok and parsed and parsed.message then
          err_msg = parsed.message
        end
      end

      JobUtils.handle_cli_error(return_val, context, err_msg)
      state.finish("debug")
    end,
  })
  job:start()
end

--- Setup syntax highlighting for the debug level buffer.
--- @param buf number Buffer handle
local function setup_syntax(buf)
  vim.api.nvim_buf_call(buf, function()
    vim.cmd([[
      syntax clear
      syntax match SfDebugLevelLabel /^\s\+\w.*$/ contains=@NoSpell
      syntax match SfDebugLevelAccordion /^\s*>/ contained
      syntax match SfDebugLevelValue /^\s*> \zs.*$/ contains=@NoSpell
      syntax match SfDebugLevelReadOnly /(read-only)$/ contained
      syntax match SfDebugLevelSeparator /^.*───.*$/
      syntax match SfDebugLevelFooter /^  Press.*$/

      highlight default link SfDebugLevelLabel Identifier
      highlight default link SfDebugLevelAccordion Special
      highlight default link SfDebugLevelValue String
      highlight default link SfDebugLevelReadOnly Comment
      highlight default link SfDebugLevelSeparator Comment
      highlight default link SfDebugLevelFooter Comment
    ]])
  end)
end

--- Open the interactive debug level buffer.
--- @param existing_dl table|nil Existing DebugLevel record for edit mode, or nil for new
--- @param extra table|nil { target_org, executable_path }
local function open_level_buffer(existing_dl, extra)
  local buf = vim.api.nvim_create_buf(false, true)

  local is_edit = existing_dl ~= nil
  local fields
  local name

  if is_edit then
    fields = record_to_fields(existing_dl)
    name = fields.DeveloperName
  else
    fields = get_default_fields()
    name = "new"
  end

  -- Set buffer name for display
  vim.api.nvim_buf_set_name(buf, "debug-level://" .. (is_edit and name or "new-" .. os.time()))

  -- Set buffer-local variables
  vim.b[buf].debug_level_fields = fields
  vim.b[buf].debug_level_mode = is_edit and "edit" or "new"
  vim.b[buf].debug_level_record_id = is_edit and existing_dl.Id or nil
  vim.b[buf].debug_level_target_org = extra and extra.target_org or nil
  vim.b[buf].debug_level_executable_path = extra and extra.executable_path or nil
  vim.b[buf].debug_level_api_version = extra and extra.api_version or nil

  -- Configure buffer
  vim.bo[buf].buftype = "nofile"
  vim.bo[buf].bufhidden = "wipe"
  vim.bo[buf].filetype = "sfdebuglevel"
  vim.bo[buf].modifiable = false

  -- Render content
  render_buffer(buf, fields, is_edit)
  vim.bo[buf].readonly = true

  -- Set up keymaps
  local function on_enter()
    local line = vim.fn.line(".")
    local line_map = vim.b[buf].debug_level_line_map

    if not line_map then
      return
    end

    local field_index = line_map[line]
    if not field_index then
      -- Not on an actionable line (label, empty, footer)
      return
    end

    local field_def = Const.DEBUG_LEVEL_FIELDS[field_index]
    local current_fields = vim.b[buf].debug_level_fields

    if field_def.readonly_edit and is_edit then
      -- Read-only in edit mode
      vim.notify(Const.SF_CLI_MESSAGES.DEBUG_LEVEL_READONLY_WARN, vim.log.levels.WARN)
      return
    end

    if field_def.name == "DeveloperName" then
      DebugPicker.create_name_input(current_fields[field_def.name] or field_def.default, function(new_value)
        current_fields[field_def.name] = new_value
        vim.b[buf].debug_level_fields = current_fields
        render_buffer(buf, current_fields, is_edit)
      end)
    elseif field_def.values and #field_def.values > 0 then
      DebugPicker.create_field_value_picker(field_def, function(new_value)
        current_fields[field_def.name] = new_value
        vim.b[buf].debug_level_fields = current_fields
        render_buffer(buf, current_fields, is_edit)
        local win = vim.fn.bufwinid(buf)
        if win ~= -1 then
          vim.api.nvim_set_current_win(win)
        end
      end)
    end
  end

  -- Map Enter key to edit field under cursor
  vim.keymap.set("n", "<CR>", function()
    pcall(on_enter)
  end, { buffer = buf, silent = true, desc = "Edit debug level field" })

  -- Map Ctrl+S to save
  vim.keymap.set("n", "<C-s>", function()
    pcall(save_buffer, buf)
  end, { buffer = buf, silent = true, desc = "Save debug level" })

  -- Map q to close
  vim.keymap.set("n", "q", ":bdelete<CR>", { buffer = buf, silent = true, desc = "Close debug level buffer" })

  -- Open the buffer at 40% right vertical split
  vim.api.nvim_command("vertical rightbelow sbuffer " .. tostring(buf))
  vim.api.nvim_command("vertical resize " .. math.floor(vim.o.columns * 0.25))
  setup_syntax(buf)
end

--- Sf debug level new — runs workflow then opens interactive buffer with defaults.
function Level.new_level()
  DebugUtils.run_workflow(function(success, data)
    if not success then
      return
    end

    local config = Config:get_options()
    local cli_valid, executable_path, error_msg = JobUtils.validate_cli_installation(config.sf_cli_path)

    if not cli_valid or not executable_path then
      vim.notify(error_msg or Const.SF_CLI_MESSAGES.NOT_FOUND, vim.log.levels.ERROR)
      return
    end

    open_level_buffer(nil, {
      target_org = data and data.username or nil,
      executable_path = executable_path,
      api_version = config.api_version,
    })
  end)
end

--- Sf debug level delete — runs workflow, shows picker, deletes selected.
function Level.delete_level()
  DebugUtils.run_workflow(function(success, data)
    if not success or not data then
      return
    end

    local target_org = data.username
    local debug_levels = data.debug_levels

    if not debug_levels or #debug_levels == 0 then
      vim.notify(Const.SF_CLI_MESSAGES.DEBUG_LEVEL_NONE_FOUND, vim.log.levels.INFO)
      return
    end

    DebugPicker.create_debug_level_picker(debug_levels, function(selected_dl)
      local record_id = selected_dl.Id

      if not record_id then
        vim.notify(Const.SF_CLI_MESSAGES.DEBUG_LEVEL_NO_ID, vim.log.levels.ERROR)

        return
      end

      local config = Config:get_options()
      local cli_valid, executable_path, _ = JobUtils.validate_cli_installation(config.sf_cli_path)

      if not cli_valid or not executable_path then
        vim.notify(Const.SF_CLI_MESSAGES.NOT_FOUND, vim.log.levels.ERROR)
        return
      end
      local state = require("sf.core.state")
      if state.is_busy("debug") then
        vim.notify(Const.SF_CLI_MESSAGES.DEBUG_LEVEL_DELETE_IN_PROGRESS, vim.log.levels.WARN)
        return
      end
      state.start("debug")
      local context = JobUtils.create_progress_context(
        Const.SF_CLI_MESSAGES.DEBUG_LEVEL_DELETE_TITLE,
        Const.SF_CLI_MESSAGES.DEBUG_LEVEL_DELETE_SUCCESS,
        Const.SF_CLI_MESSAGES.DEBUG_LEVEL_DELETE_FAILED
      )

      local args = Const.get_record_delete_args(target_org, "DebugLevel", record_id, config.api_version)
      local job = JobUtils.create_cli_job(executable_path, args, {
        on_success = function(job, _)
          local result = table.concat(job:result(), "\n")
          local ok, parsed, _ = JobUtils.validate_json_response(result)

          if ok and parsed and parsed.status == 0 then
            context.handle:report({ message = Const.SF_CLI_MESSAGES.DEBUG_LEVEL_DELETE_SUCCESS, percentage = 100 })
            context.handle:finish()

            state.finish("debug")
            vim.notify(Const.SF_CLI_MESSAGES.DEBUG_LEVEL_DELETE_SUCCESS, vim.log.levels.INFO)
          else
            local err_msg = Const.SF_CLI_MESSAGES.DEBUG_LEVEL_DELETE_FAILED

            if parsed and parsed.message then
              err_msg = parsed.message
            end

            JobUtils.handle_cli_error(1, context, err_msg)
            state.finish("debug")
          end
        end,
        on_error = function(job, return_val)
          local stderr = job:stderr_result()
          local err_msg = Const.SF_CLI_MESSAGES.DEBUG_LEVEL_DELETE_FAILED

          if stderr and stderr ~= "" then
            local ok, parsed, _ = JobUtils.validate_json_response(stderr)

            if ok and parsed and parsed.message then
              err_msg = parsed.message
            end
          end

          JobUtils.handle_cli_error(return_val, context, err_msg)
          state.finish("debug")
        end,
      })
      job:start()
    end)
  end)
end

--- Sf debug level edit — runs workflow, shows picker, opens buffer with selected values.
function Level.edit_level()
  DebugUtils.run_workflow(function(success, data)
    if not success or not data then
      return
    end

    local target_org = data.username
    local debug_levels = data.debug_levels

    if not debug_levels or #debug_levels == 0 then
      vim.notify(Const.SF_CLI_MESSAGES.DEBUG_LEVEL_NONE_FOUND, vim.log.levels.INFO)
      return
    end

    local config = Config:get_options()
    local cli_valid, executable_path, _ = JobUtils.validate_cli_installation(config.sf_cli_path)

    if not cli_valid or not executable_path then
      vim.notify(Const.SF_CLI_MESSAGES.NOT_FOUND, vim.log.levels.ERROR)

      return
    end
    DebugPicker.create_debug_level_picker(debug_levels, function(selected_dl)
      open_level_buffer(selected_dl, {
        target_org = target_org,
        executable_path = executable_path,
        api_version = config.api_version,
      })
    end)
  end)
end

return Level
