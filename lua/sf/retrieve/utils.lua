--- sf-nvim retrieve utility functions
-- @license MIT

local Config = require("sf.config")
local Const = require("sf.const")

local Utils = {}

--- Builds the manifest XML string from selected items and metadata type.
--- @param items table Array of { fullName = "...", id = "..." } items
--- @param xml_name string The metadata type xmlName (e.g. "ApexClass")
--- @return string The manifest XML content
function Utils.build_manifest_xml(items, xml_name)
  local lines = {}

  table.insert(lines, '<?xml version="1.0" encoding="UTF-8"?>')
  table.insert(lines, '<Package xmlns="http://soap.sforce.com/2006/04/metadata">')
  table.insert(lines, "    <types>")

  for _, item in ipairs(items) do
    table.insert(lines, "        <members>" .. item.fullName .. "</members>")
  end

  table.insert(lines, "        <name>" .. xml_name .. "</name>")
  table.insert(lines, "    </types>")
  table.insert(lines, "    <version>" .. Config:get_options().api_version .. "</version>")
  table.insert(lines, "</Package>")

  return table.concat(lines, "\n")
end

--- Formats retrieval warning/error messages into a numbered list string.
--- Each entry in the messages array has `fileName` and `problem` fields.
--- @param messages table|nil Array of { fileName = string, problem = string } from retrieve result
--- @return string|nil Formatted message string, or nil if messages is nil or empty
function Utils.format_retrieve_messages(messages)
  if not messages or #messages == 0 then
    return nil
  end

  local lines = { "Retrieve issues:" }

  for i, msg in ipairs(messages) do
    table.insert(lines, string.format("  %d. %s: %s", i, msg.fileName or "unknown", msg.problem or "unknown"))
  end

  return table.concat(lines, "\n")
end

--- Parse a retrieve JSON result, save it to disk, check status/warnings.
--- @param result string Raw JSON result from sf project retrieve start
--- @param context table Progress context with handle, success_message
--- @return string|nil "success" on success, "warning" on success with warnings, "error" on failure, nil on parse failure
--- @return string|nil Error/warning detail message
function Utils.handle_retrieve_result(result, context)
  if not result or result == "" then
    return "error", "Empty retrieve result"
  end

  -- Save to retrieve.json
  local retrieve_file = Config:get_options().retrieve_file
  local retrieve_dir = vim.fn.fnamemodify(retrieve_file, ":h")

  vim.fn.mkdir(retrieve_dir, "p")

  local rfile = io.open(retrieve_file, "w")

  if rfile then
    rfile:write(result)
    rfile:close()
  end

  -- Parse JSON
  local ok, parsed = pcall(vim.json.decode, result)

  if not ok or not parsed then
    return "error", "Invalid JSON in retrieve result"
  end

  local result_data = parsed.result
  local status = result_data and result_data.status
  local success = result_data and result_data.success
  local messages = result_data and result_data.messages
  local warnings = parsed.warnings
  local formatted = Utils.format_retrieve_messages(messages)

  if status ~= "Succeeded" or success == false then
    local error_detail = formatted or "Retrieval encountered issues"
    return "error", error_detail
  end

  if formatted then
    return "warning", formatted
  end

  if warnings and #warnings > 0 then
    return "success", Const.SF_CLI_MESSAGES.RETRIEVE_WARNING
  end

  return "success", nil
end

return Utils
