--- sf-nvim retrieve utility functions
-- @license MIT

local Config = require("sf.config")

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

return Utils
