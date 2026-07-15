--- sf-nvim schema retrieve module
-- @license MIT

local Config = require("sf.config")
local Connector = require("sf.org.connect")
local Const = require("sf.const")
local JobUtils = require("sf.core.job_utils")
local Log = require("sf.core.log").scoped("schema/retrieve")
local OrgUtils = require("sf.org.utils")
local PathUtils = require("sf.core.path_utils")
local Picker = require("sf.schema.picker")
local SchemaRefresh = require("sf.schema.refresh")

local Retrieve = {}

--- Present a picker of metadata types from the cached schema file.
--- On selection, fetch the selected metadata type from the org and save to disk.
--- Automatically refreshes the schema if the cached file is missing.
function Retrieve.retrieve(on_type_selected, skip_fetch)
  local schema_file = Config:get_options().metadata_types_file

  if vim.fn.filereadable(schema_file) == 0 then
    Log.notify("Metadata types schema not found. Running schema refresh first...", vim.log.levels.INFO)
    SchemaRefresh.refresh(function(success)
      if success then
        Retrieve.retrieve(on_type_selected, skip_fetch)
      else
        Log.notify("Schema refresh failed. Cannot retrieve metadata.", vim.log.levels.ERROR)
      end
    end)
    return
  end

  local file = io.open(schema_file, "r")

  if not file then
    Log.notify("Failed to open schema file: " .. schema_file, vim.log.levels.ERROR)
    return
  end

  local content = file:read("*a")
  file:close()

  local ok, parsed = pcall(vim.json.decode, content)

  if not ok or not parsed or not parsed.result or not parsed.result.metadataObjects then
    Log.notify("Invalid schema file format. Try running :Sf schema refresh", vim.log.levels.ERROR)
    return
  end

  local metadata_objects = parsed.result.metadataObjects

  if #metadata_objects == 0 then
    Log.notify("No metadata types found in schema.", vim.log.levels.WARN)
    return
  end

  local items = {}

  for _, obj in ipairs(metadata_objects) do
    table.insert(items, {
      text = obj.xmlName .. " (in " .. obj.directoryName .. ")",
      directory_name = obj.directoryName,
      xml_name = obj.xmlName,
    })
  end

  table.sort(items, function(a, b)
    return a.xml_name < b.xml_name
  end)

  Picker.create_type_picker(items, function(item)
    if skip_fetch then
      if on_type_selected then
        on_type_selected(item.xml_name)
      end
    else
      Retrieve.fetch_metadata(item.xml_name, on_type_selected)
    end
  end)
end

--- Fetch metadata of a specific type from the org and save to disk.
--- @param xml_name string The metadata type xmlName (e.g. "ApexClass")
function Retrieve.fetch_metadata(xml_name, on_type_selected, on_complete)
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
      Const.SF_CLI_MESSAGES.SCHEMA_RETRIEVE_TITLE,
      Const.SF_CLI_MESSAGES.SCHEMA_RETRIEVE_SUCCESS,
      Const.SF_CLI_MESSAGES.SCHEMA_RETRIEVE_FAILED
    )

    local output_dir = Config:get_options().metadatas_dir

    vim.fn.mkdir(output_dir, "p")

    local output_file = PathUtils.join(output_dir, xml_name .. ".json")
    local args = Const.get_org_list_metadata_args(xml_name, target_org)

    local job = JobUtils.create_cli_job(executable_path, args, {
      on_success = function(job, return_val)
        local result = table.concat(job:result(), "\n")

        local ok, _, json_err = JobUtils.validate_json_response(result)

        if not ok then
          JobUtils.handle_cli_error(return_val, context, "Invalid JSON response: " .. (json_err or "unknown error"))

          if on_complete then
            on_complete(false)
          end

          return
        end

        local file = io.open(output_file, "w")

        if file then
          file:write(result)
          file:close()
          Log.deb("Metadata saved to:", output_file)
        else
          JobUtils.handle_cli_error(return_val, context, "Failed to write metadata file: " .. output_file)

          if on_complete then
            on_complete(false)
          end

          return
        end

        context.handle:report({ message = context.success_message, percentage = 100 })
        context.handle:finish()
        Log.notify(xml_name .. " metadata info retrieved", vim.log.levels.INFO)
        if on_type_selected then
          on_type_selected(xml_name)
        end

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

return Retrieve
