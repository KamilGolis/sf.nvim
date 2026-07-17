--- sf-nvim faux Apex class generator
-- Ported from salesforcedx-vscode-metadata/src/sobjects/fauxClassGenerator.ts
-- Renders SObjectDefinition into a syntactically valid .cls file.
-- @license MIT
--
-- Input: { name: string, fields: FieldDeclaration[] }
-- Output: string — the complete .cls file content

local M = {}

local MODIFIER = "global"
local INDENT = "    "
local EOL = "\n"

--- Auto-generated header comment (matches VS Code output)
local CLASS_HEADER_COMMENT = table.concat({
  "// This file is generated as an Apex representation of the",
  "//     corresponding sObject and its fields.",
  "// This read-only file is used by the Apex Language Server to",
  "//     provide code smartness, and is deleted each time you",
  "//     refresh your sObject definitions.",
  "// To edit your sObjects and their fields, edit the corresponding",
  "//     .object-meta.xml and .field-meta.xml files.",
  "",
  "",
}, EOL)

--- Render a comment string, sanitizing Apex comment markers
--- @param comment string
--- @return string
local function comment_to_string(comment)
  if not comment or comment == "" then
    return ""
  end

  -- Strip comment markers that could break the Apex comment
  local sanitized = comment:gsub("[/*]", "")

  return INDENT .. "/* " .. sanitized .. " */" .. EOL
end

--- Render a single field declaration to a string line
--- @param decl table FieldDeclaration
--- @return string
local function field_decl_to_string(decl)
  return comment_to_string(decl.comment) .. INDENT .. decl.modifier .. " " .. decl.type .. " " .. decl.name .. ";"
end

--- Generate a complete .cls file content from an SObjectDefinition
--- @param definition table SObjectDefinition — { name: string, fields: FieldDeclaration[] }
--- @return string The complete .cls file content
--- @usage local text = generateFauxClassText({ name = "Account", fields = {...} })
function M.generate_faux_class_text(definition)
  --- Sort fields by name and deduplicate
  -- Duplicates can happen due to childRelationships w/o a relationshipName
  local fields = definition.fields or {}

  table.sort(fields, function(a, b)
    return a.name < b.name
  end)

  -- Deduplicate: keep first occurrence of each name
  local seen = {}
  local deduped = {}

  for _, decl in ipairs(fields) do
    if not seen[decl.name] then
      seen[decl.name] = true
      table.insert(deduped, decl)
    end
  end

  local class_name = definition.name
  local lines = {}

  -- Header
  lines[#lines + 1] = CLASS_HEADER_COMMENT
  lines[#lines + 1] = MODIFIER .. " class " .. class_name .. " {"

  -- Field declarations
  for _, decl in ipairs(deduped) do
    lines[#lines + 1] = field_decl_to_string(decl)
  end

  -- Empty constructor
  lines[#lines + 1] = ""
  lines[#lines + 1] = INDENT .. MODIFIER .. " " .. class_name .. " ()"
  lines[#lines + 1] = INDENT .. "    {"
  lines[#lines + 1] = INDENT .. "    }"

  -- Close class
  lines[#lines + 1] = "}"

  return table.concat(lines, EOL)
end

return M
