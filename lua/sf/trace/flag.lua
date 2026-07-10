--- sf-nvim trace flag management module
-- @license MIT

local Config = require("sf.config")
local Const = require("sf.const")
local DebugUtils = require("sf.debug.utils")
local Str = Const.SF_CLI_MESSAGES
local DebugPicker = require("sf.debug.picker")
local JobUtils = require("sf.core.job_utils")
local Log = require("sf.core.log")
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
        vim.notify(err or "Invalid date format", vim.log.levels.WARN)
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

              vim.notify(context.success_message, vim.log.levels.INFO)
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
--- Render the trace flag buffer.
--- @param buf number Buffer handle
--- @param state table Current buffer state
local function render_trace_buffer(buf, state)
  local lines = {}
  local line_map = {}

  -- Traced Entity Type
  table.insert(lines, "  Traced Entity Type")
  table.insert(lines, "  > " .. (state.traced_entity_type or "User"))
  table.insert(lines, "")

  -- Traced Entity Name
  table.insert(lines, "  Traced Entity Name")
  table.insert(lines, "  > " .. (state.traced_entity_name or ""))
  table.insert(lines, "")

  -- Start Date
  table.insert(lines, "  Start Date")
  table.insert(lines, "  > " .. state.start_date)
  line_map[#lines] = "start_date"
  table.insert(lines, "")

  -- Expiration Date
  table.insert(lines, "  Expiration Date")
  table.insert(lines, "  > " .. state.exp_date)
  line_map[#lines] = "exp_date"
  table.insert(lines, "")

  -- Debug Level
  table.insert(lines, "  Debug Level")
  local dl_label = "none selected"
  if state.selected_dl then
    dl_label = state.selected_dl.DeveloperName or "selected"
  end
  table.insert(lines, "  > " .. dl_label)
  line_map[#lines] = "debug_level"
  table.insert(lines, "")

  -- Footer
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
  vim.b[buf].trace_state = state
  vim.b[buf].trace_line_map = line_map
  vim.bo[buf].modified = false
  vim.bo[buf].readonly = true
  vim.bo[buf].modifiable = false
end

--- Save the trace flag buffer: validate, build CLI args, run command.
--- @param buf number Buffer handle
local function save_trace_buffer(buf)
  local state = vim.b[buf].trace_state

  if not state then
    vim.notify("No trace state found", vim.log.levels.ERROR)
    return
  end

  if not state.selected_dl then
    vim.notify(Str.TRACE_NO_DEBUG_LEVEL, vim.log.levels.ERROR)
    return
  end

  -- Validate date formats
  local start_iso, start_err = TraceUtils.parse_datetime_local(state.start_date)
  if not start_iso then
    vim.notify(start_err or Str.TRACE_INVALID_DATE_FORMAT, vim.log.levels.ERROR)
    return
  end

  local exp_iso, exp_err = TraceUtils.parse_datetime_local(state.exp_date)
  if not exp_iso then
    vim.notify(exp_err or Str.TRACE_INVALID_DATE_FORMAT, vim.log.levels.ERROR)
    return
  end

  local tf_fields = TraceUtils.required_trace_fields_from_debug_level(state.selected_dl)
  local value_string =
    TraceUtils.build_trace_value_string(tf_fields, state.selected_dl, state.user_id, start_iso, exp_iso)

  local target_org = state.target_org

  if not target_org then
    vim.notify(Str.NO_DEFAULT_ORG, vim.log.levels.ERROR)
    return
  end

  local executable_path = state.executable_path
  if not executable_path then
    local cli_valid, path, err = JobUtils.validate_cli_installation(Config:get_options().sf_cli_path)

    if not cli_valid or not path then
      vim.notify(err or Str.NOT_FOUND, vim.log.levels.ERROR)
      return
    end

    executable_path = path
  end

  local sf_state = require("sf.core.state")
  if sf_state.is_busy("debug") then
    vim.notify(Str.TRACE_SAVE_IN_PROGRESS, vim.log.levels.WARN)
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

        vim.notify(context.success_message, vim.log.levels.INFO)
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

--- Setup syntax highlighting for the trace flag buffer.
--- @param buf number Buffer handle
local function setup_syntax(buf)
  vim.api.nvim_buf_call(buf, function()
    vim.cmd([[
      syntax clear
      syntax match SfTraceFlagLabel /^\s\+\w.*$/ contains=@NoSpell
      syntax match SfTraceFlagAccordion /^\s*>/ contained
      syntax match SfTraceFlagValue /^\s*> \zs.*$/ contains=@NoSpell
      syntax match SfTraceFlagSeparator /^.*───.*$/
      syntax match SfTraceFlagFooter /^  Press.*$/

      highlight default link SfTraceFlagLabel Identifier
      highlight default link SfTraceFlagAccordion Special
      highlight default link SfTraceFlagValue String
      highlight default link SfTraceFlagSeparator Comment
      highlight default link SfTraceFlagFooter Comment
    ]])
  end)
end

--- Open the interactive trace flag buffer.
--- @param existing_tf table|nil Existing TraceFlag record for refresh mode, or nil for new
--- @param extra table { target_org, user_id, user_name, debug_levels, executable_path, api_version }
local function open_trace_buffer(existing_tf, extra)
  local buf = vim.api.nvim_create_buf(false, true)

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

    -- Find matching DebugLevel by DebugLevelId
    if existing_tf.DebugLevelId and extra.debug_levels then
      for _, dl in ipairs(extra.debug_levels) do
        if dl.Id == existing_tf.DebugLevelId then
          state.selected_dl = dl
          break
        end
      end
    end
  end

  -- Set buffer name for display
  local buf_name = existing_tf and ("trace-flag://" .. existing_tf.Id) or ("trace-flag://new-" .. os.time())

  -- Set buffer-local variables
  vim.b[buf].trace_state = state
  vim.b[buf].trace_line_map = {}

  -- Configure buffer
  vim.bo[buf].buftype = "nofile"
  vim.bo[buf].bufhidden = "wipe"
  vim.bo[buf].filetype = "sftraceflag"
  vim.bo[buf].modifiable = false

  render_trace_buffer(buf, state)
  vim.bo[buf].readonly = true

  -- Set up keymaps
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

    local current_state = vim.b[buf].trace_state
    if not current_state then
      return
    end

    if field_key == "start_date" then
      show_date_input(current_state.start_date, function(new_value)
        if not new_value then
          return
        end

        current_state.start_date = new_value
        vim.b[buf].trace_state = current_state

        render_trace_buffer(buf, current_state)
      end)
    elseif field_key == "exp_date" then
      show_date_input(current_state.exp_date, function(new_value)
        if not new_value then
          return
        end

        current_state.exp_date = new_value

        vim.b[buf].trace_state = current_state
        render_trace_buffer(buf, current_state)
      end)
    elseif field_key == "debug_level" then
      DebugPicker.create_debug_level_picker(current_state.debug_levels, function(selected_dl)
        current_state.selected_dl = selected_dl
        vim.b[buf].trace_state = current_state

        render_trace_buffer(buf, current_state)
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
  end, { buffer = buf, silent = true, desc = "Edit trace flag field" })

  -- Map Ctrl+S to save
  vim.keymap.set("n", "<C-s>", function()
    pcall(save_trace_buffer, buf)
  end, { buffer = buf, silent = true, desc = "Save trace flag" })

  -- Map q to close
  vim.keymap.set("n", "q", ":bdelete<CR>", { buffer = buf, silent = true, desc = "Close trace flag buffer" })

  -- Open the buffer at 40% right vertical split
  vim.api.nvim_command("vertical rightbelow sbuffer " .. tostring(buf))
  vim.api.nvim_command("vertical resize " .. math.floor(vim.o.columns * 0.25))
  setup_syntax(buf)
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
      vim.notify(error_msg or Const.SF_CLI_MESSAGES.NOT_FOUND, vim.log.levels.ERROR)
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
      vim.notify(Str.TRACE_NO_TRACE_FLAGS, vim.log.levels.INFO)
      return
    end

    local TracePicker = require("sf.trace.picker")

    TracePicker.create_trace_flag_picker(trace_flags, data.debug_levels, function(selected_tf)
      local record_id = selected_tf.Id

      if not record_id then
        vim.notify(Str.TRACE_NOT_FOUND_ERROR, vim.log.levels.ERROR)
        return
      end

      local config = Config:get_options()
      local cli_valid, executable_path, _ = JobUtils.validate_cli_installation(config.sf_cli_path)
      if not cli_valid or not executable_path then
        vim.notify(Const.SF_CLI_MESSAGES.NOT_FOUND, vim.log.levels.ERROR)
        return
      end
      local sf_state = require("sf.core.state")
      if sf_state.is_busy("debug") then
        vim.notify(Str.TRACE_DELETE_IN_PROGRESS, vim.log.levels.WARN)
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
            vim.notify(Str.TRACE_DELETE_SUCCESS, vim.log.levels.INFO)
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
