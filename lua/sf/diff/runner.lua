local Config = require("sf.config")
local Const = require("sf.const")
local Detect = require("sf.diff.detect")
local Display = require("sf.diff.display")
local JobUtils = require("sf.core.job_utils")
local Log = require("sf.core.log").scoped("diff/runner")
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
  local Async = require("sf.core.async")

  Async.async(function()
    if not Async.await_cli_check() then
      return
    end

    local has_default_org, target_org, org_error = OrgUtils.check_default_org()
    if not has_default_org then
      Log.notify(org_error or Const.SF_CLI_MESSAGES.NO_DEFAULT_ORG, vim.log.levels.ERROR)
      return
    end

    if State.is_busy("diff") then
      Log.notify("Already diffing. Please wait...", vim.log.levels.WARN)
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
    diff_state.temp_dir = vim.fn.tempname()
    vim.fn.mkdir(diff_state.temp_dir, "p")
    Log.deb("Diff temp directory: " .. diff_state.temp_dir)

    local title = "Diffing " .. (diff_state.filename or "metadata") .. "..."

    local handle = require("sf.core.progress").create_handle({ title = title })
    local executable_path = Config:get_options().sf_cli_path or "sf"

    State.start("diff")

    -- Step 1: Retrieve in metadata API format
    local retrieve_args = Const.get_diff_retrieve_args(info.type, info.member, diff_state.temp_dir, target_org)
    Log.deb("Diff retrieve args: ", retrieve_args)

    local retrieve_stdout, retrieve_code = Async.await_system(executable_path, retrieve_args)
    if retrieve_code ~= 0 then
      handle:report({ message = "Diff retrieve failed", percentage = 100 })
      handle:finish()
      State.finish("diff")

      vim.fn.delete(diff_state.temp_dir, "rf")
      Log.notify("Diff retrieve failed", vim.log.levels.ERROR)

      return
    end

    local ok, parsed = pcall(vim.json.decode, retrieve_stdout)
    if not ok or not parsed then
      handle:report({ message = "Diff retrieve failed", percentage = 100 })
      handle:finish()
      State.finish("diff")

      vim.fn.delete(diff_state.temp_dir, "rf")
      Log.notify("Failed to parse diff retrieve response", vim.log.levels.ERROR)

      return
    end

    if parsed.status ~= 0 then
      local detail = parsed.message or "Retrieve failed"
      handle:finish()
      State.finish("diff")

      vim.fn.delete(diff_state.temp_dir, "rf")
      Log.notify("Diff retrieve: " .. detail, vim.log.levels.ERROR)

      return
    end

    -- Step 2: Convert from metadata format to source format
    local unpackaged_dir = PathUtils.join(diff_state.temp_dir, "unpackaged")
    local converted_dir = PathUtils.join(diff_state.temp_dir, "converted")
    local convert_args = Const.get_diff_convert_args(unpackaged_dir, converted_dir)

    Log.deb("Diff convert args: ", convert_args)

    handle:report({ message = "Converting to source format...", percentage = 60 })

    local convert_stdout, convert_code = Async.await_system(executable_path, convert_args)
    if convert_code ~= 0 then
      handle:report({ message = "Diff convert failed", percentage = 100 })
      handle:finish()
      State.finish("diff")

      vim.fn.delete(diff_state.temp_dir, "rf")
      Log.notify("Diff convert failed", vim.log.levels.ERROR)

      return
    end

    local conv_ok, conv_parsed = pcall(vim.json.decode, convert_stdout)
    if not conv_ok or not conv_parsed then
      handle:report({ message = "Diff convert failed", percentage = 100 })
      handle:finish()
      State.finish("diff")

      vim.fn.delete(diff_state.temp_dir, "rf")
      Log.notify("Failed to parse diff convert response", vim.log.levels.ERROR)

      return
    end

    if conv_parsed.status ~= 0 then
      local detail = conv_parsed.message or "Convert failed"
      handle:finish()
      State.finish("diff")

      vim.fn.delete(diff_state.temp_dir, "rf")
      Log.notify("Diff convert: " .. detail, vim.log.levels.ERROR)

      return
    end

    M.handle_convert_response(conv_parsed, info.local_path, {
      handle = handle,
      success_message = "Diff ready for " .. (diff_state.filename or "metadata"),
      failure_message = "Diff retrieve failed",
    })
  end)()
end

return M
