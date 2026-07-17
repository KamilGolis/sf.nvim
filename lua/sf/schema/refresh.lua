--- sf-nvim schema refresh module
-- @license MIT

local Async = require("sf.core.async")
local Config = require("sf.config")
local Const = require("sf.const")
local Log = require("sf.core.log").scoped("schema/refresh")
local OrgUtils = require("sf.org.utils")

local Schema = {}

--- Refresh the org metadata types schema by running `sf org list metadata-types --json`.
--- Saves the result to `.sf/.sf.nvim/metadata-types.json` (configurable via metadata_types_file).
--- Always overwrites the file on each invocation.
function Schema.refresh(on_complete)
  Async.async(function()
    if not Async.await_cli_check() then
      if on_complete then
        on_complete(false)
      end

      return
    end

    local has_default_org, target_org, org_error = OrgUtils.check_default_org()
    if not has_default_org then
      Log.notify(org_error or Const.SF_CLI_MESSAGES.NO_DEFAULT_ORG, vim.log.levels.ERROR)

      if on_complete then
        on_complete(false)
      end

      return
    end

    local result_file = Config:get_options().metadata_types_file
    local result_dir = vim.fn.fnamemodify(result_file, ":h")
    vim.fn.mkdir(result_dir, "p")

    local args = Const.get_org_list_metadata_types_args(target_org)
    local parsed, err, raw_stdout = Async.await_sf(args, Const.SF_CLI_MESSAGES.SCHEMA_REFRESH_TITLE)

    if err then
      Log.notify(string.format(Const.SF_CLI_MESSAGES.SCHEMA_REFRESH_FAILED, err), vim.log.levels.ERROR)

      if on_complete then
        on_complete(false)
      end

      return
    end

    if not parsed then
      Log.notify("Failed to parse schema response", vim.log.levels.ERROR)

      if on_complete then
        on_complete(false)
      end

      return
    end

    local file = io.open(result_file, "w")
    if file then
      file:write(raw_stdout)
      file:close()
      Log.deb("Schema saved to:", result_file)
    else
      Log.notify("Failed to write schema file: " .. result_file, vim.log.levels.ERROR)

      if on_complete then
        on_complete(false)
      end

      return
    end

    if on_complete then
      on_complete(true)
    end
  end)()
end

return Schema
