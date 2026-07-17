--- sf-nvim retrieve metadata module
-- @license MIT

local Async = require("sf.core.async")
local Config = require("sf.config")
local Const = require("sf.const")
local Detect = require("sf.diff.detect")
local Log = require("sf.core.log").scoped("retrieve/metadata")
local OrgUtils = require("sf.org.utils")
local PathUtils = require("sf.core.path_utils")
local Picker = require("sf.retrieve.picker")
local RetrieveUtils = require("sf.retrieve.utils")
local SchemaRetrieve = require("sf.schema.retrieve")
local State = require("sf.core.state")

local Metadata = {}

local function show_items_picker(xml_name)
  local metadatas_dir = Config:get_options().metadatas_dir
  local json_file = PathUtils.join(metadatas_dir, xml_name .. ".json")

  local file = io.open(json_file, "r")
  if not file then
    Log.notify("Failed to open metadata file: " .. json_file, vim.log.levels.ERROR)
    return
  end

  local content = file:read("*a")
  file:close()

  local ok, parsed = pcall(vim.json.decode, content)
  if not ok or not parsed or not parsed.result then
    Log.notify("Invalid metadata file format.", vim.log.levels.ERROR)
    return
  end

  local result = parsed.result
  if type(result) ~= "table" or #result == 0 then
    Log.notify("No metadata items found for " .. xml_name .. ".", vim.log.levels.WARN)
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

  Picker.create_items_picker(items, xml_name, function(selected)
    Metadata.execute_retrieve(selected, xml_name)
  end)
end

--- Runs the retrieval CLI command for the given items and metadata type.
--- If >10 items, creates a manifest file and uses -x flag; deletes manifest after.
--- @param items table Array of { fullName = "...", id = "..." } items
--- @param xml_name string The metadata type
function Metadata.execute_retrieve(items, xml_name)
  Async.async(function()
    if not Async.await_cli_check() then
      return
    end

    local has_default_org, target_org, org_error = OrgUtils.check_default_org()
    if not has_default_org then
      Log.notify(org_error or Const.SF_CLI_MESSAGES.NO_DEFAULT_ORG, vim.log.levels.ERROR)
      return
    end

    if State.is_busy("retrieve") then
      Log.notify("Already retrieving. Please wait...", vim.log.levels.WARN)
      return
    end

    local executable_path = Config:get_options().sf_cli_path or "sf"
    local context = require("sf.core.job_utils").create_progress_context(
      Const.SF_CLI_MESSAGES.RETRIEVE_TITLE,
      Const.SF_CLI_MESSAGES.RETRIEVE_SUCCESS,
      Const.SF_CLI_MESSAGES.RETRIEVE_FAILED
    )

    local api_version = Config:get_options().api_version
    local use_manifest = #items > Const.MANIFEST_THRESHOLD
    local manifest_path = nil
    local args

    if use_manifest then
      local cache_dir = Config:get_options().cache_path
      local manifest_dir = PathUtils.join(cache_dir, "manifest")
      vim.fn.mkdir(manifest_dir, "p")

      manifest_path = PathUtils.join(manifest_dir, "retrieve-manifest.xml")
      local xml = RetrieveUtils.build_manifest_xml(items, xml_name)

      local file = io.open(manifest_path, "w")
      if file then
        file:write(xml)
        file:close()

        Log.notify(string.format(Const.SF_CLI_MESSAGES.RETRIEVE_MANIFEST_CREATED, #items), vim.log.levels.INFO)
      else
        context.handle:report({ message = "Failed to create manifest file", percentage = 100 })
        context.handle:finish()

        Log.notify("Failed to create manifest file: " .. manifest_path, vim.log.levels.ERROR)
        return
      end

      args =
        Const.get_project_retrieve_manifest_args(PathUtils.to_forward_slashes(manifest_path), api_version, target_org)
    else
      local typed_items = vim.tbl_map(function(item)
        return { fullName = item.fullName, type_name = xml_name }
      end, items)

      args = Const.get_project_retrieve_args(typed_items, api_version, target_org)
    end

    State.start("retrieve")
    local stdout, code = Async.await_system(executable_path, args)
    State.finish("retrieve")

    -- Clean up manifest file
    if use_manifest and manifest_path then
      os.remove(manifest_path)
    end

    if code ~= 0 then
      context.handle:report({ message = "Retrieve failed", percentage = 100 })
      context.handle:finish()

      return
    end

    local status, detail = RetrieveUtils.handle_retrieve_result(stdout, context)

    if status == "error" then
      Log.notify(detail or "Retrieval encountered issues", vim.log.levels.ERROR)
      return
    end

    if status == "warning" then
      Log.notify(detail, vim.log.levels.WARN)
      context.handle:report({ message = Const.SF_CLI_MESSAGES.RETRIEVE_WITH_ISSUES, percentage = 100 })
      context.handle:finish()

      return
    end

    if status == "success" then
      if detail then
        Log.notify(detail, vim.log.levels.WARN)
      end
      context.handle:report({ message = context.success_message, percentage = 100 })
      context.handle:finish()
      Log.notify("Metadata retrieved successfully.", vim.log.levels.INFO)
    end
  end)()
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
  end, true)
end

--- Sf retrieve type: select type, then retrieve ALL items by type name only.
function Metadata.retrieve_all_of_type()
  SchemaRetrieve.retrieve(function(xml_name)
    Async.async(function()
      if not Async.await_cli_check() then
        return
      end

      local has_default_org, target_org, org_error = OrgUtils.check_default_org()
      if not has_default_org then
        Log.notify(org_error or Const.SF_CLI_MESSAGES.NO_DEFAULT_ORG, vim.log.levels.ERROR)
        return
      end

      if State.is_busy("retrieve") then
        Log.notify("Already retrieving. Please wait...", vim.log.levels.WARN)
        return
      end

      local executable_path = Config:get_options().sf_cli_path or "sf"
      local api_version = Config:get_options().api_version

      local context = require("sf.core.job_utils").create_progress_context(
        Const.SF_CLI_MESSAGES.RETRIEVE_TITLE,
        Const.SF_CLI_MESSAGES.RETRIEVE_SUCCESS,
        Const.SF_CLI_MESSAGES.RETRIEVE_FAILED
      )

      local args = Const.get_project_retrieve_type_args(xml_name, api_version, target_org)

      State.start("retrieve")
      local stdout, code = Async.await_system(executable_path, args)
      State.finish("retrieve")

      if code ~= 0 then
        context.handle:report({ message = "Retrieve failed", percentage = 100 })
        context.handle:finish()
        return
      end

      local status, detail = RetrieveUtils.handle_retrieve_result(stdout, context)

      if status == "error" then
        Log.notify(detail or "Retrieval encountered issues", vim.log.levels.ERROR)
        return
      end

      if status == "warning" then
        Log.notify(detail, vim.log.levels.WARN)
        context.handle:report({ message = Const.SF_CLI_MESSAGES.RETRIEVE_WITH_ISSUES, percentage = 100 })
        context.handle:finish()
        return
      end

      if status == "success" then
        if detail then
          Log.notify(detail, vim.log.levels.WARN)
        end
        context.handle:report({ message = context.success_message, percentage = 100 })
        context.handle:finish()
        Log.notify(xml_name .. " metadata retrieved successfully.", vim.log.levels.INFO)
      end
    end)()
  end)
end

--- Sf retrieve refresh: detect metadata type from the current buffer and retrieve
--- directly, skipping pickers.
function Metadata.retrieve_current_buffer()
  local bufnr = vim.api.nvim_get_current_buf()
  local info, detect_err = Detect.detect_metadata_from_buffer(bufnr)

  if not info then
    Log.notify(detect_err or "Could not determine metadata type.", vim.log.levels.ERROR)
    return
  end

  Async.async(function()
    if not Async.await_cli_check() then
      return
    end

    local has_default_org, target_org, org_error = OrgUtils.check_default_org()
    if not has_default_org then
      Log.notify(org_error or Const.SF_CLI_MESSAGES.NO_DEFAULT_ORG, vim.log.levels.ERROR)
      return
    end

    if State.is_busy("retrieve") then
      Log.notify("Already retrieving. Please wait...", vim.log.levels.WARN)
      return
    end

    local executable_path = Config:get_options().sf_cli_path or "sf"
    local api_version = Config:get_options().api_version

    local context = require("sf.core.job_utils").create_progress_context(
      Const.SF_CLI_MESSAGES.RETRIEVE_TITLE,
      Const.SF_CLI_MESSAGES.RETRIEVE_SUCCESS,
      Const.SF_CLI_MESSAGES.RETRIEVE_FAILED
    )

    local items = { { fullName = info.member, type_name = info.type } }
    local args = Const.get_project_retrieve_args(items, api_version, target_org)

    State.start("retrieve")
    local stdout, code = Async.await_system(executable_path, args)
    State.finish("retrieve")

    if code ~= 0 then
      context.handle:report({ message = "Retrieve failed", percentage = 100 })
      context.handle:finish()
      return
    end

    local status, detail = RetrieveUtils.handle_retrieve_result(stdout, context)

    if status == "error" then
      Log.notify(detail or "Retrieval encountered issues", vim.log.levels.ERROR)
      return
    end

    if status == "warning" then
      Log.notify(detail, vim.log.levels.WARN)
      context.handle:report({ message = Const.SF_CLI_MESSAGES.RETRIEVE_WITH_ISSUES, percentage = 100 })
      context.handle:finish()
      return
    end

    if status == "success" then
      if detail then
        Log.notify(detail, vim.log.levels.WARN)
      end
      context.handle:report({ message = context.success_message, percentage = 100 })
      context.handle:finish()
      Log.notify(info.type .. ":" .. info.member .. " retrieved successfully.", vim.log.levels.INFO)
    end
  end)()
end

return Metadata
