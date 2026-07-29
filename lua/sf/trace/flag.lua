--- sf-nvim trace flag management module
-- @license MIT

local Buffer = require("sf.core.buffer")
local Config = require("sf.config")
local Const = require("sf.const")
local DebugPicker = require("sf.debug.picker")
local DebugUtils = require("sf.debug.utils")
local JobUtils = require("sf.core.job_utils")
local Log = require("sf.core.log").scoped("trace/flag")
local Str = Const.SF_CLI_MESSAGES
local TraceUtils = require("sf.trace.utils")

local Flag = {}

--- Show an input dialog for a date field.
--- @param current_value string The current value pre-filled
--- @param on_confirm fun(value: string) Called with the entered value
local function show_date_input(current_value, on_confirm)
  vim.ui.input({
    prompt = "Enter date (dd.mm.yyyy HH:MM):",
    default = current_value,
  }, function(new_value)
    if new_value then
      local iso, err = TraceUtils.parse_datetime_local(new_value)
      if not iso then
        Log.notify(err or "Invalid date format", vim.log.levels.WARN)
        return
      end
      on_confirm(new_value)
    end
  end)
end

--- Delete conflicting trace flags for the given user, then retry creating a new one.
--- @param executable_path string The SF CLI executable path
--- @param target_org string The target org username
--- @param api_version string The Salesforce API version
--- @param user_id string The TracedEntityId (user ID)
--- @param trace_flags table Existing trace flags from workflow
--- @param create_args table The args for the create command to retry
--- @param context table Progress context
--- @param buf number Buffer handle to close on success
--- @param sf_state table State tracker
local function delete_conflicting_and_retry(
  executable_path,
  target_org,
  api_version,
  user_id,
  trace_flags,
  create_args,
  context,
  buf,
  sf_state
)
  -- Find conflicting trace flags for this user
  local conflicting = {}

  for _, tf in ipairs(trace_flags or {}) do
    if tf.TracedEntityId == user_id then
      table.insert(conflicting, tf)
    end
  end

  if #conflicting == 0 then
    JobUtils.handle_cli_error(1, context, Str.TRACE_NEW_FAILED)
    sf_state.finish("debug")

    return
  end

  -- Delete first conflicting flag, then retry
  local tf = conflicting[1]
  local delete_args = Const.get_tooling_record_delete_args(target_org, "TraceFlag", tf.Id, api_version)

  context.handle:report({ message = Str.TRACE_OVERLAP_DELETING, percentage = 50 })

  local delete_job = JobUtils.create_cli_job(executable_path, delete_args, {
    on_success = function(djob, _)
      local dresult = table.concat(djob:result(), "\n")
      local dok, dparsed, _ = JobUtils.validate_json_response(dresult)

      if dok and dparsed and dparsed.status == 0 then
        context.handle:report({ message = Str.TRACE_OVERLAP_RETRYING, percentage = 75 })

        -- Retry create
        local retry_job = JobUtils.create_cli_job(executable_path, create_args, {
          on_success = function(rjob, _)
            local rresult = table.concat(rjob:result(), "\n")
            Log.deb("Trace flag retry create result:", rresult)

            local rok, rparsed, _ = JobUtils.validate_json_response(rresult)

            if rok and rparsed and rparsed.status == 0 then
              context.handle:report({ message = context.success_message, percentage = 100 })
              context.handle:finish()
              sf_state.finish("debug")

              Log.notify(context.success_message, vim.log.levels.INFO)
              pcall(vim.api.nvim_buf_delete, buf, { force = true })
            else
              local err_msg = Str.TRACE_NEW_FAILED

              if rparsed and rparsed.data and rparsed.data.message then
                err_msg = rparsed.data.message
              elseif rparsed and rparsed.message then
                err_msg = rparsed.message
              end

              JobUtils.handle_cli_error(1, context, err_msg)
              sf_state.finish("debug")
            end
          end,
          on_error = function(rjob, return_val)
            local rstdout_str = table.concat(rjob:result(), "\n")
            local rerr_msg = Str.TRACE_NEW_FAILED

            if rstdout_str ~= "" then
              local rok, rparsed, _ = JobUtils.validate_json_response(rstdout_str)

              if rok and rparsed then
                if rparsed.data and rparsed.data.message then
                  rerr_msg = rparsed.data.message
                elseif rparsed.message then
                  rerr_msg = rparsed.message
                end
              end
            end

            JobUtils.handle_cli_error(return_val, context, rerr_msg)
            sf_state.finish("debug")
          end,
        })

        retry_job:start()
      else
        local derr_msg = Str.TRACE_DELETE_CONFLICT_FAILED

        if dparsed and dparsed.data and dparsed.data.message then
          derr_msg = dparsed.data.message
        elseif dparsed and dparsed.message then
          derr_msg = dparsed.message
        end

        JobUtils.handle_cli_error(1, context, derr_msg)
        sf_state.finish("debug")
      end
    end,
    on_error = function(djob, return_val)
      local dstderr_str = table.concat(djob:stderr_result(), "\n")

      Log.deb("Delete conflicting trace flag error", { return_val = return_val, stderr = dstderr_str })
      JobUtils.handle_cli_error(return_val, context, Str.TRACE_DELETE_CONFLICT_FAILED)
      sf_state.finish("debug")
    end,
  })
  delete_job:start()
end

--- Save the trace flag buffer: validate, build CLI args, run command.
--- @param buf number Buffer handle
local function save_trace_buffer(buf)
  local state = vim.b[buf].trace_state

  if not state then
    Log.notify("No trace state found", vim.log.levels.ERROR)
    return
  end

  if not state.selected_dl then
    Log.notify(Str.TRACE_NO_DEBUG_LEVEL, vim.log.levels.ERROR)
    return
  end

  -- Validate date formats
  local start_iso, start_err = TraceUtils.parse_datetime_local(state.start_date)
  if not start_iso then
    Log.notify(start_err or Str.TRACE_INVALID_DATE_FORMAT, vim.log.levels.ERROR)
    return
  end

  local exp_iso, exp_err = TraceUtils.parse_datetime_local(state.exp_date)
  if not exp_iso then
    Log.notify(exp_err or Str.TRACE_INVALID_DATE_FORMAT, vim.log.levels.ERROR)
    return
  end

  local tf_fields = TraceUtils.required_trace_fields_from_debug_level(state.selected_dl)
  local value_string =
    TraceUtils.build_trace_value_string(tf_fields, state.selected_dl, state.user_id, start_iso, exp_iso)

  local target_org = state.target_org

  if not target_org then
    Log.notify(Str.NO_DEFAULT_ORG, vim.log.levels.ERROR)
    return
  end

  local executable_path = state.executable_path
  if not executable_path then
    local cli_valid, path, err = JobUtils.validate_cli_installation(Config:get_options().sf_cli_path)

    if not cli_valid or not path then
      Log.notify(err or Str.NOT_FOUND, vim.log.levels.ERROR)
      return
    end

    executable_path = path
  end

  local sf_state = require("sf.core.state")
  if sf_state.is_busy("debug") then
    Log.notify(Str.TRACE_SAVE_IN_PROGRESS, vim.log.levels.WARN)
    return
  end
  sf_state.start("debug")

  local context
  local args

  if state.is_refresh and state.trace_flag_id then
    context =
      JobUtils.create_progress_context(Str.TRACE_REFRESH_TITLE, Str.TRACE_REFRESH_SUCCESS, Str.TRACE_REFRESH_FAILED)

    args = Const.get_tooling_record_update_args(
      target_org,
      "TraceFlag",
      value_string,
      state.trace_flag_id,
      state.api_version
    )
  else
    context = JobUtils.create_progress_context(Str.TRACE_NEW_TITLE, Str.TRACE_NEW_SUCCESS, Str.TRACE_NEW_FAILED)

    args = Const.get_tooling_record_create_args(target_org, "TraceFlag", value_string, state.api_version)
  end

  local job = JobUtils.create_cli_job(executable_path, args, {
    on_success = function(job, _)
      local result = table.concat(job:result(), "\n")
      Log.deb("Trace flag save result:", result)

      local ok, parsed, _ = JobUtils.validate_json_response(result)

      if ok and parsed and parsed.status == 0 then
        context.handle:report({ message = context.success_message, percentage = 100 })
        context.handle:finish()
        sf_state.finish("debug")

        Log.notify(context.success_message, vim.log.levels.INFO)
        pcall(vim.api.nvim_buf_delete, buf, { force = true })
      else
        Log.deb("save_trace_buffer on_success non-zero status", parsed)

        local err_msg = state.is_refresh and Str.TRACE_REFRESH_FAILED or Str.TRACE_NEW_FAILED

        if parsed and parsed.data and parsed.data.message then
          err_msg = parsed.data.message
        elseif parsed and parsed.message then
          err_msg = parsed.message
        end

        -- Check for overlapping trace flag conflict; delete-and-retry if detected
        if not state.is_refresh and TraceUtils.is_overlap_error(err_msg) then
          delete_conflicting_and_retry(
            executable_path,
            target_org,
            state.api_version,
            state.user_id,
            state.trace_flags,
            args,
            context,
            buf,
            sf_state
          )

          return
        end

        JobUtils.handle_cli_error(1, context, err_msg)
        sf_state.finish("debug")
      end
    end,
    on_error = function(job, return_val)
      local stderr_lines = job:stderr_result()
      local stderr_str = table.concat(stderr_lines, "\n")
      local stdout_lines = job:result()
      local stdout_str = table.concat(stdout_lines, "\n")
      local err_msg = state.is_refresh and Str.TRACE_REFRESH_FAILED or Str.TRACE_NEW_FAILED

      if stdout_str ~= "" then
        local ok, parsed, _ = JobUtils.validate_json_response(stdout_str)

        if ok and parsed then
          if parsed.data and parsed.data.message then
            err_msg = parsed.data.message
          elseif parsed.message then
            err_msg = parsed.message
          end
        end
      end

      if err_msg == Str.TRACE_NEW_FAILED and stderr_str ~= "" then
        local ok, parsed, _ = JobUtils.validate_json_response(stderr_str)

        if ok and parsed then
          if parsed.data and parsed.data.message then
            err_msg = parsed.data.message
          elseif parsed.message then
            err_msg = parsed.message
          end
        end
      end

      -- Check for overlapping trace flag conflict; delete-and-retry if detected
      if not state.is_refresh and TraceUtils.is_overlap_error(err_msg) then
        delete_conflicting_and_retry(
          executable_path,
          target_org,
          state.api_version,
          state.user_id,
          state.trace_flags,
          args,
          context,
          buf,
          sf_state
        )

        return
      end

      Log.deb("Trace flag save error", { return_val = return_val, err_msg = err_msg, stderr = stderr_str })

      JobUtils.handle_cli_error(return_val, context, err_msg)
      sf_state.finish("debug")
    end,
  })
  job:start()
end

--- Open the interactive trace flag buffer.
--- @param existing_tf table|nil Existing TraceFlag record for refresh mode, or nil for new
--- @param extra table { target_org, user_id, user_name, debug_levels, executable_path, api_version }
local function open_trace_buffer(existing_tf, extra)
  local state = {
    traced_entity_type = "User",
    traced_entity_name = extra.user_name or "",
    start_date = TraceUtils.now_local(),
    exp_date = TraceUtils.now_plus_1h_local(),
    selected_dl = nil,
    is_refresh = existing_tf ~= nil,
    trace_flag_id = nil,
    target_org = extra.target_org,
    user_id = extra.user_id,
    debug_levels = extra.debug_levels or {},
    executable_path = extra.executable_path,
    api_version = extra.api_version,
    trace_flags = extra.trace_flags or {},
  }

  if existing_tf then
    state.trace_flag_id = existing_tf.Id
    local start_formatted = TraceUtils.format_datetime_local(existing_tf.StartDate)
    local exp_formatted = TraceUtils.format_datetime_local(existing_tf.ExpirationDate)

    if start_formatted ~= "" then
      state.start_date = start_formatted
    end

    if exp_formatted ~= "" then
      state.exp_date = exp_formatted
    end

    if existing_tf.DebugLevelId and extra.debug_levels then
      for _, dl in ipairs(extra.debug_levels) do
        if dl.Id == existing_tf.DebugLevelId then
          state.selected_dl = dl
          break
        end
      end
    end
  end

  local buf

  local function get_render_lines()
    local lines = {}
    local line_map = {}

    local width = math.min(70, vim.o.columns - 4)
    local divider = string.rep("─", width)

    -- Header
    lines[#lines + 1] = divider
    lines[#lines + 1] = " "
      .. Const.ICONS.STATE
      .. " Trace Flag — "
      .. (state.is_refresh and (state.trace_flag_id or "?") or "New")
    lines[#lines + 1] = divider
    lines[#lines + 1] = ""

    -- Traced Entity (non-editable info)
    lines[#lines + 1] = " " .. Const.ICONS.USER .. " Traced Entity"
    lines[#lines + 1] = "   " .. (state.traced_entity_type or "User")
    lines[#lines + 1] = "   \u{2022} " .. (state.traced_entity_name or "")
    lines[#lines + 1] = ""

    -- Start Date
    lines[#lines + 1] = " " .. Const.ICONS.TIME .. " Start Date"
    lines[#lines + 1] = "   \u{2022} " .. state.start_date
    line_map[#lines] = "start_date"
    lines[#lines + 1] = ""

    -- Expiration Date
    lines[#lines + 1] = " " .. Const.ICONS.TIME .. " Expiration Date"
    lines[#lines + 1] = "   \u{2022} " .. state.exp_date
    line_map[#lines] = "exp_date"
    lines[#lines + 1] = ""

    -- Debug Level
    lines[#lines + 1] = " " .. Const.ICONS.TECHNICAL .. " Debug Level"
    local dl_label = "none selected"
    if state.selected_dl then
      dl_label = state.selected_dl.DeveloperName or "selected"
    end
    lines[#lines + 1] = "   \u{2022} " .. dl_label
    line_map[#lines] = "debug_level"
    lines[#lines + 1] = ""

    lines[#lines + 1] = divider

    return lines, line_map
  end

  local function re_render()
    if buf and vim.api.nvim_buf_is_valid(buf) then
      local lines, line_map = get_render_lines()
      Buffer.render_accordion(buf, lines, line_map, "trace_line_map")
      vim.b[buf].trace_state = state
    end
  end

  local function on_enter()
    local line = vim.fn.line(".")
    local line_map = vim.b[buf].trace_line_map

    if not line_map then
      return
    end

    local field_key = line_map[line]
    if not field_key then
      return
    end

    if field_key == "start_date" then
      show_date_input(state.start_date, function(new_value)
        if not new_value then
          return
        end
        state.start_date = new_value
        re_render()
      end)
    elseif field_key == "exp_date" then
      show_date_input(state.exp_date, function(new_value)
        if not new_value then
          return
        end
        state.exp_date = new_value
        re_render()
      end)
    elseif field_key == "debug_level" then
      DebugPicker.create_debug_level_picker(state.debug_levels, function(selected_dl)
        state.selected_dl = selected_dl
        re_render()
        local win = vim.fn.bufwinid(buf)
        if win ~= -1 then
          vim.api.nvim_set_current_win(win)
        end
      end)
    end
  end

  local title = state.is_refresh and (" Trace Flag — " .. (state.trace_flag_id or "?") .. " ") or " New Trace Flag "

  local Snacks = require("snacks")
  Snacks.win({
    title = title,
    title_pos = "center",
    position = "float",
    width = math.min(70, vim.o.columns - 4),
    height = 24,
    border = "single",
    ft = "sftraceflag",
    bo = { filetype = "sftraceflag" },
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
          vim.b[self.buf].trace_state = state
          pcall(save_trace_buffer, self.buf)
        end,
      },
      q = { "q", "close", desc = "Close" },
    },
    on_win = function(self)
      buf = self.buf
      local _, line_map = get_render_lines()
      vim.b[buf].trace_line_map = line_map
      vim.b[buf].trace_state = state
    end,
  })
end

--- Sf debug trace new — runs workflow then opens interactive buffer with defaults.
function Flag.new_trace_flag()
  DebugUtils.run_workflow(function(success, data)
    if not success or not data then
      return
    end

    local config = Config:get_options()
    local cli_valid, executable_path, error_msg = JobUtils.validate_cli_installation(config.sf_cli_path)

    if not cli_valid or not executable_path then
      Log.notify(error_msg or Const.SF_CLI_MESSAGES.NOT_FOUND, vim.log.levels.ERROR)
      return
    end

    open_trace_buffer(nil, {
      target_org = data.username,
      user_id = data.user_id,
      user_name = data.user_name,
      debug_levels = data.debug_levels,
      executable_path = executable_path,
      api_version = config.api_version,
      trace_flags = data.trace_flags,
    })
  end)
end

--- Sf debug trace delete — runs workflow, shows picker, deletes selected trace flag.
function Flag.delete_trace_flag()
  DebugUtils.run_workflow(function(success, data)
    if not success or not data then
      return
    end

    local trace_flags = data.trace_flags

    if not trace_flags or #trace_flags == 0 then
      Log.notify(Str.TRACE_NO_TRACE_FLAGS, vim.log.levels.INFO)
      return
    end

    local TracePicker = require("sf.trace.picker")

    TracePicker.create_trace_flag_picker(trace_flags, data.debug_levels, function(selected_tf)
      local record_id = selected_tf.Id

      if not record_id then
        Log.notify(Str.TRACE_NOT_FOUND_ERROR, vim.log.levels.ERROR)
        return
      end

      local config = Config:get_options()
      local cli_valid, executable_path, _ = JobUtils.validate_cli_installation(config.sf_cli_path)
      if not cli_valid or not executable_path then
        Log.notify(Const.SF_CLI_MESSAGES.NOT_FOUND, vim.log.levels.ERROR)
        return
      end
      local sf_state = require("sf.core.state")
      if sf_state.is_busy("debug") then
        Log.notify(Str.TRACE_DELETE_IN_PROGRESS, vim.log.levels.WARN)
        return
      end
      sf_state.start("debug")
      local context =
        JobUtils.create_progress_context(Str.TRACE_DELETE_TITLE, Str.TRACE_DELETE_SUCCESS, Str.TRACE_DELETE_FAILED)

      local target_org = data.username
      local args = Const.get_tooling_record_delete_args(target_org, "TraceFlag", record_id, config.api_version)

      local job = JobUtils.create_cli_job(executable_path, args, {
        on_success = function(job, _)
          local result = table.concat(job:result(), "\n")
          local ok, parsed, _ = JobUtils.validate_json_response(result)

          if ok and parsed and parsed.status == 0 then
            context.handle:report({ message = Str.TRACE_DELETE_SUCCESS, percentage = 100 })
            context.handle:finish()
            sf_state.finish("debug")
            Log.notify(Str.TRACE_DELETE_SUCCESS, vim.log.levels.INFO)
          else
            local err_msg = Str.TRACE_DELETE_FAILED

            if parsed and parsed.data and parsed.data.message then
              err_msg = parsed.data.message
            elseif parsed and parsed.message then
              err_msg = parsed.message
            end

            JobUtils.handle_cli_error(1, context, err_msg)
            sf_state.finish("debug")
          end
        end,
        on_error = function(job, return_val)
          local stdout_str = table.concat(job:result(), "\n")
          local err_msg = Str.TRACE_DELETE_FAILED

          if stdout_str ~= "" then
            local ok, parsed, _ = JobUtils.validate_json_response(stdout_str)

            if ok and parsed then
              if parsed.data and parsed.data.message then
                err_msg = parsed.data.message
              elseif parsed.message then
                err_msg = parsed.message
              end
            end
          end

          JobUtils.handle_cli_error(return_val, context, err_msg)
          sf_state.finish("debug")
        end,
      })

      job:start()
    end)
  end)
end

return Flag
