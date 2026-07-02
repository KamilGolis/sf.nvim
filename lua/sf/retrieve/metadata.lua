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

local function show_items_picker(xml_name)
  local metadatas_dir = Config:get_options().metadatas_dir
  local json_file = PathUtils.join(metadatas_dir, xml_name .. ".json")

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
end


--- Runs the retrieval CLI command for the given items and metadata type.
--- If >10 items, creates a manifest file and uses -x flag; deletes manifest after.
--- @param items table Array of { fullName = "...", id = "..." } items
--- @param xml_name string The metadata type
function Metadata.execute_retrieve(items, xml_name)
  vim.schedule(function()
    Connector:check_cli(function()
      local has_default_org, target_org, org_error = OrgUtils.check_default_org()

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

      local api_version = Config:get_options().api_version
      local use_manifest = #items > Const.MANIFEST_THRESHOLD
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

        args = Const.get_project_retrieve_manifest_args(
          PathUtils.to_forward_slashes(manifest_path),
          api_version,
          target_org
        )
      else
        -- Build items with type_name for the "xmlName:fullName" -m format
        local typed_items = vim.tbl_map(function(item)
          return { fullName = item.fullName, type_name = xml_name }
        end, items)

        args = Const.get_project_retrieve_args(typed_items, api_version, target_org)
      end

      local job = JobUtils.create_cli_job(executable_path, args, {
        on_success = function(job, return_val)
          Log.deb("Metadata retrieve success", { return_val = return_val })

          local result = table.concat(job:result(), "\n")

          Log.deb("Retrieve result:", result)

          -- Save result to retrieve.json
          local retrieve_file = Config:get_options().retrieve_file
          local retrieve_dir = vim.fn.fnamemodify(retrieve_file, ":h")

          vim.fn.mkdir(retrieve_dir, "p")

          local rfile = io.open(retrieve_file, "w")

          if rfile then
            rfile:write(result)
            rfile:close()
            Log.deb("Retrieve result saved to:", retrieve_file)
          end

          -- Clean up manifest file
          if use_manifest and manifest_path then
            os.remove(manifest_path)
          end

          -- Check JSON response for status/messages/warnings
          local ok, parsed = pcall(vim.json.decode, result)

          if ok and parsed then
            local status = parsed.status
            local success = parsed.result and parsed.result.success
            local messages = parsed.result and parsed.result.messages
            local warnings = parsed.warnings

            if status ~= "Succeeded" or success == false then
              local error_detail = "Retrieval encountered issues"

              if messages and #messages > 0 then
                error_detail = messages[1].error or messages[1].message or error_detail
              end
              JobUtils.handle_cli_error(return_val, context, error_detail)
              return
            end

            if warnings and #warnings > 0 then
              vim.notify(Const.SF_CLI_MESSAGES.RETRIEVE_WARNING, vim.log.levels.WARN)
            end
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

    if vim.fn.filereadable(json_file) == 1 then
      show_items_picker(xml_name)
    else
      SchemaRetrieve.fetch_metadata(xml_name, function()
        show_items_picker(xml_name)
      end)
    end
  end, true) -- skip_fetch = true
end

--- Sf retrieve type: select type, then retrieve ALL items by type name only.
--- Runs `sf project retrieve start -m "<xmlName>"` without listing individual items.
function Metadata.retrieve_all_of_type()
  SchemaRetrieve.retrieve(function(xml_name)
    Connector:check_cli(function()
      local has_default_org, target_org, org_error = OrgUtils.check_default_org()

      if not has_default_org then
        vim.notify(org_error or Const.SF_CLI_MESSAGES.NO_DEFAULT_ORG, vim.log.levels.ERROR)
        return
      end

      local cli_valid, executable_path, error_msg = JobUtils.validate_cli_installation(Config:get_options().sf_cli_path)

      if not cli_valid or not executable_path then
        vim.notify(error_msg or Const.SF_CLI_MESSAGES.NOT_FOUND, vim.log.levels.ERROR)
        return
      end

      local api_version = Config:get_options().api_version

      local context = JobUtils.create_progress_context(
        Const.SF_CLI_MESSAGES.RETRIEVE_TITLE,
        Const.SF_CLI_MESSAGES.RETRIEVE_SUCCESS,
        Const.SF_CLI_MESSAGES.RETRIEVE_FAILED
      )

      local direct_args = {}

      vim.list_extend(direct_args, vim.split(Const.SF_CLI.PROJECT.RETRIEVE.CMD, " "))
      vim.list_extend(direct_args, { Const.SF_CLI.PROJECT.RETRIEVE.ARGS.METADATA, xml_name })
      vim.list_extend(direct_args, { Const.SF_CLI.PROJECT.RETRIEVE.ARGS.JSON })
      vim.list_extend(direct_args, { Const.SF_CLI.PROJECT.RETRIEVE.ARGS.API_VERSION, api_version })
      vim.list_extend(direct_args, { Const.SF_CLI.PROJECT.RETRIEVE.ARGS.IGNORE_CONFLICTS })
      if target_org then
        vim.list_extend(direct_args, { Const.SF_CLI.PROJECT.RETRIEVE.ARGS.TARGET_ORG, target_org })
      end

      local job = JobUtils.create_cli_job(executable_path, direct_args, {
        on_success = function(job, return_val)
          Log.deb("Retrieve type success", { xml_name = xml_name, return_val = return_val })

          local result = table.concat(job:result(), "\n")

          Log.deb("Retrieve type result:", result)

          -- Save result to retrieve.json
          local retrieve_file = Config:get_options().retrieve_file
          local retrieve_dir = vim.fn.fnamemodify(retrieve_file, ":h")

          vim.fn.mkdir(retrieve_dir, "p")

          local rfile = io.open(retrieve_file, "w")

          if rfile then
            rfile:write(result)
            rfile:close()
            Log.deb("Retrieve type result saved to:", retrieve_file)
          end

          -- Check JSON response for status/messages/warnings
          local ok, parsed = pcall(vim.json.decode, result)

          if ok and parsed then
            local status = parsed.status
            local success = parsed.result and parsed.result.success
            local messages = parsed.result and parsed.result.messages
            local warnings = parsed.warnings

            if status ~= "Succeeded" or success == false then
              local error_detail = "Retrieval encountered issues"

              if messages and #messages > 0 then
                error_detail = messages[1].error or messages[1].message or error_detail
              end
              JobUtils.handle_cli_error(return_val, context, error_detail)
              return
            end

            if warnings and #warnings > 0 then
              vim.notify(Const.SF_CLI_MESSAGES.RETRIEVE_WARNING, vim.log.levels.WARN)
            end
          end

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
