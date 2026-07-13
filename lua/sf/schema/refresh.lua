--- sf-nvim schema refresh module
-- @license MIT

local Config = require("sf.config")
local Connector = require("sf.org.connect")
local Const = require("sf.const")
local JobUtils = require("sf.core.job_utils")
local Log = require("sf.core.log")
local OrgUtils = require("sf.org.utils")

local Schema = {}

--- Refresh the org metadata types schema by running `sf org list metadata-types --json`.
--- Saves the result to `.sf/.sf.nvim/metadata-types.json` (configurable via metadata_types_file).
--- Always overwrites the file on each invocation.
function Schema.refresh(on_complete)
  Connector:check_cli(function()
    local has_default_org, target_org, org_error = OrgUtils.check_default_org()

    if not has_default_org then
      Log.notify(org_error or Const.SF_CLI_MESSAGES.NO_DEFAULT_ORG, vim.log.levels.ERROR)

      if on_complete then
        on_complete(false)
      end

      return
    end

    local cli_valid, executable_path, error_msg = JobUtils.validate_cli_installation(Config:get_options().sf_cli_path)

    if not cli_valid or not executable_path then
      Log.notify(error_msg or Const.SF_CLI_MESSAGES.NOT_FOUND, vim.log.levels.ERROR)

      if on_complete then
        on_complete(false)
      end

      return
    end

    local context = JobUtils.create_progress_context(
      Const.SF_CLI_MESSAGES.SCHEMA_REFRESH_TITLE,
      Const.SF_CLI_MESSAGES.SCHEMA_REFRESH_SUCCESS,
      Const.SF_CLI_MESSAGES.SCHEMA_REFRESH_FAILED
    )

    local result_file = Config:get_options().metadata_types_file
    local result_dir = vim.fn.fnamemodify(result_file, ":h")

    vim.fn.mkdir(result_dir, "p")

    local args = Const.get_org_list_metadata_types_args(target_org)

    local job = JobUtils.create_cli_job(executable_path, args, {
      on_success = function(job, return_val)
        local result = table.concat(job:result(), "\n")

        Log.deb("Schema refresh raw result:", result)

        local ok, _, json_err = JobUtils.validate_json_response(result)

        if not ok then
          JobUtils.handle_cli_error(return_val, context, "Invalid JSON response: " .. (json_err or "unknown error"))

          if on_complete then
            on_complete(false)
          end

          return
        end

        local file = io.open(result_file, "w")

        if file then
          file:write(result)
          file:close()
          Log.deb("Schema saved to:", result_file)
        else
          JobUtils.handle_cli_error(return_val, context, "Failed to write schema file: " .. result_file)

          if on_complete then
            on_complete(false)
          end

          return
        end

        context.handle:report({ message = context.success_message, percentage = 100 })
        context.handle:finish()
        if on_complete then
          on_complete(true)
        end
      end,
      on_error = function(job, return_val)
        local stderr = job:stderr_result()

        JobUtils.handle_cli_error(return_val, context)
        if on_complete then
          on_complete(false)
        end
      end,
    })

    job:start()
  end)
end

return Schema
