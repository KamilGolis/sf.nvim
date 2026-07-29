--- sf-nvim debug level management module
-- @license MIT

local Buffer = require("sf.core.buffer")
local Config = require("sf.config")
local Const = require("sf.const")
local DebugPicker = require("sf.debug.picker")
local DebugUtils = require("sf.debug.utils")
local JobUtils = require("sf.core.job_utils")
local Log = require("sf.core.log").scoped("debug/level")
local Progress = require("sf.core.progress")

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
    Log.notify(Const.SF_CLI_MESSAGES.DEBUG_LEVEL_NO_FIELD_DATA, vim.log.levels.ERROR)
    return
  end

  if not target_org then
    Log.notify(Const.SF_CLI_MESSAGES.DEBUG_LEVEL_NO_TARGET_ORG, vim.log.levels.ERROR)
    return
  end

  if not executable_path then
    local cli_valid, path, err = JobUtils.validate_cli_installation(Config:get_options().sf_cli_path)

    if not cli_valid or not path then
      Log.notify(err or Const.SF_CLI_MESSAGES.NOT_FOUND, vim.log.levels.ERROR)
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
    Log.notify(Const.SF_CLI_MESSAGES.DEBUG_LEVEL_SAVE_IN_PROGRESS, vim.log.levels.WARN)
    return
  end
  state.start("debug")

  local args
  if mode == "new" then
    args = Const.get_record_create_args(target_org, "DebugLevel", value_string, api_version)
  else
    args = Const.get_record_update_args(target_org, "DebugLevel", value_string, record_id, api_version)
  end

  local title = mode == "new" and Const.SF_CLI_MESSAGES.DEBUG_LEVEL_NEW_TITLE
    or Const.SF_CLI_MESSAGES.DEBUG_LEVEL_EDIT_TITLE
  Progress.sf_execute(args, title, {
    on_complete = function(parsed, err, raw_stdout)
      if err then
        Log.deb("Debug level save error:", err)
        local err_msg = err
        if raw_stdout and raw_stdout ~= "" then
          local ok, p = pcall(vim.json.decode, raw_stdout)
          if ok and p and p.message then
            err_msg = p.message
          end
        end
        Log.notify(err_msg, vim.log.levels.ERROR)
        state.finish("debug")
        return
      end

      if parsed and parsed.status == 0 then
        state.finish("debug")
        local success_msg = mode == "new" and Const.SF_CLI_MESSAGES.DEBUG_LEVEL_NEW_SUCCESS
          or Const.SF_CLI_MESSAGES.DEBUG_LEVEL_EDIT_SUCCESS
        Log.notify(success_msg, vim.log.levels.INFO)
        pcall(vim.api.nvim_buf_delete, buf, { force = true })
      else
        local err_msg = Const.SF_CLI_MESSAGES.DEBUG_LEVEL_SAVE_FAILED
        if parsed and parsed.message then
          err_msg = parsed.message
        elseif parsed and parsed.result and parsed.result.errors and #parsed.result.errors > 0 then
          err_msg = parsed.result.errors[1]
        end
        Log.deb("Debug level save failure:", err_msg)
        Log.notify(err_msg, vim.log.levels.ERROR)
        state.finish("debug")
      end
    end,
  })
end

--- Open the interactive debug level buffer.
--- @param existing_dl table|nil Existing DebugLevel record for edit mode, or nil for new
--- @param extra table|nil { target_org, executable_path }
local function open_level_buffer(existing_dl, extra)
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

  local buf

  -- Build render lines + line_map (replaces the deleted render_buffer function).
  local function get_render_lines()
    local lines = {}
    local line_map = {}

    -- Header with divider (same as SOQL builder)
    local width = math.min(70, vim.o.columns - 4)
    local divider = string.rep("─", width)

    lines[#lines + 1] = divider
    lines[#lines + 1] = " " .. Const.ICONS.TECHNICAL .. " Debug Level — " .. (is_edit and name or "New")
    lines[#lines + 1] = divider
    lines[#lines + 1] = ""

    -- Log Level Name field (special: has its own section with blank line after)
    lines[#lines + 1] = " " .. Const.ICONS.EDIT .. " Log Level Name"
    local name_value = fields["DeveloperName"] or "Default"

    if Const.DEBUG_LEVEL_FIELDS[1].readonly_edit and is_edit then
      lines[#lines + 1] = "   " .. name_value .. " (read-only)"
    else
      lines[#lines + 1] = "   \u{2022} " .. name_value
    end

    line_map[#lines] = 1
    lines[#lines + 1] = ""

    -- Log Categories section header
    lines[#lines + 1] = " " .. Const.ICONS.LOG_INFO .. " Log Categories"
    lines[#lines + 1] = ""

    -- Remaining fields (ApexCode through Workflow)
    for i = 2, #Const.DEBUG_LEVEL_FIELDS do
      local fd = Const.DEBUG_LEVEL_FIELDS[i]
      local value = fields[fd.name] or fd.default

      lines[#lines + 1] = "   " .. fd.label
      lines[#lines + 1] = "   \u{2022} " .. value
      line_map[#lines] = i
    end

    lines[#lines + 1] = ""
    lines[#lines + 1] = divider

    return lines, line_map
  end

  -- Re-render after a field value changes.
  local function re_render()
    if buf and vim.api.nvim_buf_is_valid(buf) then
      local lines, line_map = get_render_lines()
      Buffer.render_accordion(buf, lines, line_map, "debug_level_line_map")
    end
  end

  -- Edit field under cursor.
  local function on_enter()
    local line = vim.fn.line(".")
    local line_map = vim.b[buf].debug_level_line_map

    if not line_map then
      return
    end

    local field_index = line_map[line]
    if not field_index then
      return
    end

    local field_def = Const.DEBUG_LEVEL_FIELDS[field_index]

    if field_def.readonly_edit and is_edit then
      Log.notify(Const.SF_CLI_MESSAGES.DEBUG_LEVEL_READONLY_WARN, vim.log.levels.WARN)
      return
    end

    if field_def.name == "DeveloperName" then
      DebugPicker.create_name_input(fields[field_def.name] or field_def.default, function(new_value)
        fields[field_def.name] = new_value
        re_render()
      end)
    elseif field_def.values and #field_def.values > 0 then
      DebugPicker.create_field_value_picker(field_def, function(new_value)
        fields[field_def.name] = new_value
        re_render()
        local win = vim.fn.bufwinid(buf)
        if win ~= -1 then
          vim.api.nvim_set_current_win(win)
        end
      end)
    end
  end

  local title = is_edit and (" Debug Level — " .. name .. " ") or " New Debug Level "

  local Snacks = require("snacks")
  Snacks.win({
    title = title,
    title_pos = "center",
    position = "float",
    width = math.min(70, vim.o.columns - 4),
    height = math.max(#Const.DEBUG_LEVEL_FIELDS * 2 + 10, 24),
    border = "single",
    ft = "sfdebuglevel",
    bo = { filetype = "sfdebuglevel" },
    enter = true,
    footer_keys = { "q", "<CR>", "<C-s>" },
    text = function()
      local lines, _ = get_render_lines()
      return lines
    end,
    keys = {
      ["<CR>"] = {
        desc = "Edit Field",
        function()
          pcall(on_enter)
        end,
      },
      ["<C-s>"] = {
        desc = "Save",
        function(self)
          vim.b[self.buf].debug_level_fields = fields
          vim.b[self.buf].debug_level_mode = is_edit and "edit" or "new"
          vim.b[self.buf].debug_level_record_id = is_edit and existing_dl.Id or nil
          vim.b[self.buf].debug_level_target_org = extra and extra.target_org or nil
          vim.b[self.buf].debug_level_executable_path = extra and extra.executable_path or nil
          vim.b[self.buf].debug_level_api_version = extra and extra.api_version or nil
          pcall(save_buffer, self.buf)
        end,
      },
      q = { "q", "close", desc = "Close" },
    },
    on_win = function(self)
      buf = self.buf
      local _, line_map = get_render_lines()
      vim.b[buf].debug_level_line_map = line_map
    end,
  })
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
      Log.notify(error_msg or Const.SF_CLI_MESSAGES.NOT_FOUND, vim.log.levels.ERROR)
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
      Log.notify(Const.SF_CLI_MESSAGES.DEBUG_LEVEL_NONE_FOUND, vim.log.levels.INFO)
      return
    end

    DebugPicker.create_debug_level_picker(debug_levels, function(selected_dl)
      local record_id = selected_dl.Id

      if not record_id then
        Log.notify(Const.SF_CLI_MESSAGES.DEBUG_LEVEL_NO_ID, vim.log.levels.ERROR)

        return
      end

      local config = Config:get_options()
      local cli_valid, executable_path, _ = JobUtils.validate_cli_installation(config.sf_cli_path)

      if not cli_valid or not executable_path then
        Log.notify(Const.SF_CLI_MESSAGES.NOT_FOUND, vim.log.levels.ERROR)
        return
      end
      local state = require("sf.core.state")
      if state.is_busy("debug") then
        Log.notify(Const.SF_CLI_MESSAGES.DEBUG_LEVEL_DELETE_IN_PROGRESS, vim.log.levels.WARN)
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
            Log.notify(Const.SF_CLI_MESSAGES.DEBUG_LEVEL_DELETE_SUCCESS, vim.log.levels.INFO)
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
      Log.notify(Const.SF_CLI_MESSAGES.DEBUG_LEVEL_NONE_FOUND, vim.log.levels.INFO)
      return
    end

    local config = Config:get_options()
    local cli_valid, executable_path, _ = JobUtils.validate_cli_installation(config.sf_cli_path)

    if not cli_valid or not executable_path then
      Log.notify(Const.SF_CLI_MESSAGES.NOT_FOUND, vim.log.levels.ERROR)

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
