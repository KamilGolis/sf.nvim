--- sf-nvim diff-against-server module
-- Orchestrates metadata detection, two-step retrieve (metadata format) + convert,
-- buffer tracking, and diff display for the `Sf retrieve diff` command.
-- @license MIT

local Config = require("sf.config")
local Connector = require("sf.org.connect")
local Const = require("sf.const")
local Detect = require("sf.diff.detect")
local Display = require("sf.diff.display")
local JobUtils = require("sf.core.job_utils")
local Log = require("sf.core.log")
local OrgUtils = require("sf.org.utils")
local PathUtils = require("sf.core.path_utils")
local State = require("sf.core.state")
local Utils = require("sf.core.utils")

local M = {}

--- Buffer tracking state for ongoing diff operations.
--- Captured at job start, used in the completion callback.
local diff_state = {
  bufnr = nil,
  filename = nil,
  info = nil,
  temp_dir = nil,
}

--- Handle a failed job in the two-step flow.
--- Cleans up temp dir and reports the error.
--- @param return_val number CLI exit code
--- @param context table Progress context
function M.handle_job_error(return_val, context)
  local detail = context.failure_message

  State.finish("diff")
  JobUtils.handle_cli_error(return_val, context, detail)

  if diff_state.temp_dir then
    vim.fn.delete(diff_state.temp_dir, "rf")
  end
end

--- Handle the convert step response.
--- Finds the converted file and opens the diff view.
--- @param sfdx_response table Parsed JSON from sf project convert mdapi
--- @param local_path string Path to the local file
--- @param context table Progress context
function M.handle_convert_response(sfdx_response, local_path, context)
  local converted_dir = PathUtils.join(diff_state.temp_dir, "converted")

  -- Search for the converted file matching the original filename
  local retrieved_file = Utils.find_file(converted_dir, diff_state.filename)

  if not retrieved_file or vim.fn.filereadable(retrieved_file) ~= 1 then
    Log.notify("Failed to locate converted file in " .. converted_dir, vim.log.levels.ERROR)
    State.finish("diff")
    vim.fn.delete(diff_state.temp_dir, "rf")

    return
  end

  Log.deb("Diff server file: " .. retrieved_file)
  Log.deb("Diff local file: " .. local_path)

  -- Read server content into memory and delete temp dir before LSP can scan it
  local f = io.open(retrieved_file, "r")

  if not f then
    Log.notify("Failed to read retrieved file", vim.log.levels.ERROR)
    State.finish("diff")
    vim.fn.delete(diff_state.temp_dir, "rf")

    return
  end

  local server_content = f:read("*all")
  f:close()

  vim.fn.delete(diff_state.temp_dir, "rf")

  context.handle:report({ message = "Diff ready", percentage = 100 })
  context.handle:finish()

  State.finish("diff")

  Display.open_file_diff(local_path, server_content, diff_state.filename)
end

--- Entry point for `Sf retrieve diff`.
--- Detects metadata type, retrieves in metadata format, converts to source, and diffs.
function M.diff_current_buffer()
  vim.schedule(function()
    Connector:check_cli(function()
      local has_default_org, target_org, org_error = OrgUtils.check_default_org()

      if not has_default_org then
        Log.notify(org_error or Const.SF_CLI_MESSAGES.NO_DEFAULT_ORG, vim.log.levels.ERROR)
        return
      end

      if State.is_busy("diff") then
        Log.notify("Already diffing. Please wait...", vim.log.levels.WARN)
        return
      end

      local cli_valid, executable_path, error_msg = JobUtils.validate_cli_installation(Config:get_options().sf_cli_path)

      if not cli_valid or not executable_path then
        Log.notify(error_msg or Const.SF_CLI_MESSAGES.NOT_FOUND, vim.log.levels.ERROR)
        return
      end

      local bufnr = vim.api.nvim_get_current_buf()
      local info, detect_err = Detect.detect_metadata_from_buffer(bufnr)

      if not info then
        Log.notify(detect_err or "Could not determine metadata type.", vim.log.levels.ERROR)
        return
      end

      diff_state.bufnr = bufnr
      diff_state.filename = vim.fn.fnamemodify(vim.api.nvim_buf_get_name(bufnr), ":t")
      diff_state.info = info

      -- Create unique temp directory for this diff operation
      diff_state.temp_dir = vim.fn.tempname()
      vim.fn.mkdir(diff_state.temp_dir, "p")
      Log.deb("Diff temp directory: " .. diff_state.temp_dir)

      local title = "Diffing " .. (diff_state.filename or "metadata") .. "..."

      local context = JobUtils.create_progress_context(
        title,
        "Diff ready for " .. (diff_state.filename or "metadata"),
        "Diff retrieve failed"
      )

      -- Job 1: Retrieve in metadata API format
      local retrieve_args = Const.get_diff_retrieve_args(info.type, info.member, diff_state.temp_dir, target_org)
      Log.deb("Diff retrieve args: ", retrieve_args)

      local retrieve_job = JobUtils.create_cli_job(executable_path, retrieve_args, {
        on_success = function(job, return_val)
          local result = table.concat(job:result(), "\n")
          Log.deb("Diff retrieve result:", result)

          local ok, parsed = JobUtils.validate_json_response(result)

          if not ok or not parsed then
            M.handle_job_error(return_val, context)
            return
          end

          if parsed.status ~= 0 then
            local detail = parsed.message or "Retrieve failed"

            State.finish("diff")
            JobUtils.handle_cli_error(return_val, context, detail)
            vim.fn.delete(diff_state.temp_dir, "rf")

            return
          end

          -- Job 2: Convert from metadata format to source format
          local unpackaged_dir = PathUtils.join(diff_state.temp_dir, "unpackaged")
          local converted_dir = PathUtils.join(diff_state.temp_dir, "converted")

          local convert_args = Const.get_diff_convert_args(unpackaged_dir, converted_dir)
          Log.deb("Diff convert args: ", convert_args)

          context.handle:report({ message = "Converting to source format...", percentage = 60 })

          local convert_job = JobUtils.create_cli_job(executable_path, convert_args, {
            on_success = function(conv_job, conv_return_val)
              local conv_result = table.concat(conv_job:result(), "\n")
              Log.deb("Diff convert result:", conv_result)

              local conv_ok, conv_parsed = JobUtils.validate_json_response(conv_result)

              if not conv_ok or not conv_parsed then
                M.handle_job_error(conv_return_val, context)
                return
              end

              if conv_parsed.status ~= 0 then
                local detail = conv_parsed.message or "Convert failed"

                State.finish("diff")
                JobUtils.handle_cli_error(conv_return_val, context, detail)
                vim.fn.delete(diff_state.temp_dir, "rf")

                return
              end

              M.handle_convert_response(conv_parsed, info.local_path, context)
            end,
            on_error = function(conv_job, conv_return_val)
              M.handle_job_error(conv_return_val, context)
            end,
          })

          convert_job:start()
        end,
        on_error = function(job, return_val)
          M.handle_job_error(return_val, context)
        end,
      })

      State.start("diff")
      retrieve_job:start()
    end)
  end)
end

return M
