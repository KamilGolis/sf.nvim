--- sf-nvim retrieve metadata module
-- @license MIT

local Config = require("sf.config")
local Connector = require("sf.org.connect")
local Const = require("sf.const")
local JobUtils = require("sf.core.job_utils")
local Log = require("sf.core.log")
local OrgUtils = require("sf.org.utils")
local PathUtils = require("sf.core.path_utils")
local SchemaRetrieve = require("sf.schema.retrieve")
local Picker = require("sf.retrieve.picker")
local RetrieveUtils = require("sf.retrieve.utils")

local Metadata = {}


--- Runs the retrieval CLI command for the given items and metadata type.
--- If >10 items, creates a manifest file and uses -x flag; deletes manifest after.
--- @param items table Array of { fullName = "...", id = "..." } items
--- @param xml_name string The metadata type
function Metadata.execute_retrieve(items, xml_name)
  vim.schedule(function()
    Connector:check_cli(function()
      local has_default_org, _, org_error = OrgUtils.check_default_org()

      if not has_default_org then
        vim.notify(org_error or Const.SF_CLI_MESSAGES.NO_DEFAULT_ORG, vim.log.levels.ERROR)
        return
      end

      local cli_valid, executable_path, error_msg = JobUtils.validate_cli_installation(Config:get_options().sf_cli_path)

      if not cli_valid or not executable_path then
        vim.notify(error_msg or Const.SF_CLI_MESSAGES.NOT_FOUND, vim.log.levels.ERROR)
        return
      end

      local context = JobUtils.create_progress_context(
        Const.SF_CLI_MESSAGES.RETRIEVE_TITLE,
        Const.SF_CLI_MESSAGES.RETRIEVE_SUCCESS,
        Const.SF_CLI_MESSAGES.RETRIEVE_FAILED
      )

      local use_manifest = #items > 10
      local manifest_path = nil
      local args

      if use_manifest then
        -- Manifest directory is <project_root>/manifest/
        local project_root = vim.fn.getcwd()

        local manifest_dir = PathUtils.join(project_root, "manifest")

        vim.fn.mkdir(manifest_dir, "p")

        manifest_path = PathUtils.join(manifest_dir, "retrieve-manifest.xml")
        local xml = RetrieveUtils.build_manifest_xml(items, xml_name)

        local file = io.open(manifest_path, "w")

        if file then
          file:write(xml)
          file:close()
          vim.notify(string.format(Const.SF_CLI_MESSAGES.RETRIEVE_MANIFEST_CREATED, #items), vim.log.levels.INFO)
        else
          JobUtils.handle_cli_error(0, context, "Failed to create manifest file: " .. manifest_path)
          return
        end

        args = Const.get_project_retrieve_manifest_args(PathUtils.to_forward_slashes(manifest_path))
      else
        -- Build items with type_name for the "xmlName:fullName" -m format
        local typed_items = vim.tbl_map(function(item)
          return { fullName = item.fullName, type_name = xml_name }
        end, items)

        args = Const.get_project_retrieve_args(typed_items)
      end

      local job = JobUtils.create_cli_job(executable_path, args, {
        on_success = function(job, return_val)
          Log.deb("Metadata retrieve success", { return_val = return_val })

          local result = table.concat(job:result(), "\n")

          Log.deb("Retrieve result:", result)

          if use_manifest and manifest_path then
            os.remove(manifest_path)
          end

          context.handle:report({ message = context.success_message, percentage = 100 })
          context.handle:finish()

          vim.notify("Metadata retrieved successfully.", vim.log.levels.INFO)
        end,
        on_error = function(job, return_val)
          local stderr = job:stderr_result()

          Log.deb("Metadata retrieve error", { return_val = return_val, stderr = stderr })

          if use_manifest and manifest_path then
            os.remove(manifest_path)
          end

          JobUtils.handle_cli_error(return_val, context)
        end,
      })

      job:start()
    end)
  end)
end

--- Sf retrieve metadata: select type, then select individual items (multi-select)
function Metadata.retrieve_selected()
  SchemaRetrieve.retrieve(function(xml_name)
    local metadatas_dir = Config:get_options().metadatas_dir
    local json_file = PathUtils.join(metadatas_dir, xml_name .. ".json")

    if vim.fn.filereadable(json_file) == 0 then
      vim.notify("Metadata file not found: " .. json_file, vim.log.levels.ERROR)
      return
    end

    local file = io.open(json_file, "r")

    if not file then
      vim.notify("Failed to open metadata file: " .. json_file, vim.log.levels.ERROR)
      return
    end

    local content = file:read("*a")
    file:close()

    local ok, parsed = pcall(vim.json.decode, content)

    if not ok or not parsed or not parsed.result then
      vim.notify("Invalid metadata file format.", vim.log.levels.ERROR)
      return
    end

    local result = parsed.result

    if type(result) ~= "table" or #result == 0 then
      vim.notify("No metadata items found for " .. xml_name .. ".", vim.log.levels.WARN)
      return
    end

    local items = {}

    for _, item in ipairs(result) do
      table.insert(items, {
        text = item.type .. ": " .. item.fullName .. " (id:" .. item.id .. ")",
        fullName = item.fullName,
        id = item.id,
        type = item.type,
        file_name = item.fileName,
        created_date = item.createdDate,
        created_by = item.createdByName,
        last_modified = item.lastModifiedDate,
        manageable_state = item.manageableState,
      })
    end

    table.sort(items, function(a, b)
      return a.fullName < b.fullName
    end)

    -- Show multi-select picker with preview details
    Picker.create_items_picker(items, xml_name, function(selected)
      Metadata.execute_retrieve(selected, xml_name)
    end)
  end)
end

--- Sf retrieve type: select type, then retrieve ALL items by type name only.
--- Runs `sf project retrieve start -m "<xmlName>"` without listing individual items.
function Metadata.retrieve_all_of_type()
  SchemaRetrieve.retrieve(function(xml_name)
    Connector:check_cli(function()
      local has_default_org, _, org_error = OrgUtils.check_default_org()

      if not has_default_org then
        vim.notify(org_error or Const.SF_CLI_MESSAGES.NO_DEFAULT_ORG, vim.log.levels.ERROR)
        return
      end

      local cli_valid, executable_path, error_msg = JobUtils.validate_cli_installation(Config:get_options().sf_cli_path)

      if not cli_valid or not executable_path then
        vim.notify(error_msg or Const.SF_CLI_MESSAGES.NOT_FOUND, vim.log.levels.ERROR)
        return
      end

      local context = JobUtils.create_progress_context(
        Const.SF_CLI_MESSAGES.RETRIEVE_TITLE,
        Const.SF_CLI_MESSAGES.RETRIEVE_SUCCESS,
        Const.SF_CLI_MESSAGES.RETRIEVE_FAILED
      )

      local direct_args = {}

      vim.list_extend(direct_args, vim.split(Const.SF_CLI.PROJECT.RETRIEVE.CMD, " "))
      vim.list_extend(direct_args, { Const.SF_CLI.PROJECT.RETRIEVE.ARGS.METADATA, xml_name })
      vim.list_extend(direct_args, { Const.SF_CLI.PROJECT.RETRIEVE.ARGS.JSON })

      local job = JobUtils.create_cli_job(executable_path, direct_args, {
        on_success = function(job, return_val)
          Log.deb("Retrieve type success", { xml_name = xml_name, return_val = return_val })

          context.handle:report({ message = context.success_message, percentage = 100 })
          context.handle:finish()
          vim.notify(xml_name .. " metadata retrieved successfully.", vim.log.levels.INFO)
        end,
        on_error = function(job, return_val)
          local stderr = job:stderr_result()

          Log.deb("Retrieve type error", { xml_name = xml_name, return_val = return_val, stderr = stderr })
          JobUtils.handle_cli_error(return_val, context)
        end,
      })

      job:start()
    end)
  end)
end

return Metadata
