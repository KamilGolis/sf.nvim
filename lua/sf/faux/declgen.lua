--- sf-nvim sObject declaration generator
-- Ported from salesforcedx-vscode-metadata/src/sobjects/declarationGenerator.ts
-- Converts sObject describe API results into Apex field declarations.
-- @license MIT
--
-- Input structure (from `sf sobject describe --json`):
--   { result: { name: string, fields: SObjectField[], childRelationships: ChildRelationship[] } }
--   SObjectField = { name, type, referenceTo?, relationshipName?, inlineHelpText?, extraTypeInfo? }
--   ChildRelationship = { childSObject, field, relationshipName?, ... }
--
-- Output: { name: string, fields: FieldDeclaration[] }
--   FieldDeclaration = { modifier: "global", type: string, name: string, comment?: string }

local Const = require("sf.const")

local M = {}

--- @class FieldDeclaration
--- @field modifier string
--- @field type string
--- @field name string
--- @field comment string|nil

--- @class SObjectDefinition
--- @field name string
--- @field fields FieldDeclaration[]

local MODIFIER = "global"

--- Strip trailing "Id" from a field name
--- @param name string
--- @return string
local function strip_id(name)
  if name:sub(-2) == "Id" then
    return name:sub(1, -3)
  end

  return name
end

--- Map a describe type to its Apex equivalent
--- Falls back to capitalized raw type for unknown types.
--- @param describe_type string
--- @return string
local function get_target_type(describe_type)
  local apex_type = Const.TYPE_MAPPING[describe_type]
  if apex_type ~= nil then
    return apex_type
  end

  -- Fallback: capitalize first letter
  if #describe_type > 0 then
    return describe_type:sub(1, 1):upper() .. describe_type:sub(2)
  end

  return describe_type
end

--- Get the name to use for the reference part of a field
--- Uses relationshipName when available, otherwise strips "Id" from the field name.
--- @param name string The raw field name (e.g. "AccountId")
--- @param relationship_name string|nil Optional relationship name (e.g. "Account")
--- @return string
local function get_reference_name(name, relationship_name)
  if relationship_name and relationship_name ~= vim.NIL then
    return relationship_name
  end

  return strip_id(name)
end

--- Generate field declarations for a child relationship
--- @param rel table ChildRelationship from describe result
--- @return FieldDeclaration[]
local function generate_child_relationship(rel)
  return {
    {
      modifier = MODIFIER,
      type = "List<" .. rel.childSObject .. ">",
      name = get_reference_name(rel.field, rel.relationshipName),
    },
  }
end

--- Generate field declarations for a single sObject field
--- @param field table SObjectField from describe result
--- @return FieldDeclaration[]
local function generate_field(field)
  local common = { modifier = MODIFIER }
  if field.inlineHelpText and field.inlineHelpText ~= vim.NIL then
    common.comment = field.inlineHelpText
  end

  -- No reference targets → normal field
  if not field.referenceTo or #field.referenceTo == 0 then
    local gen_type
    if field.extraTypeInfo == "externallookup" then
      gen_type = "String"
    else
      gen_type = get_target_type(field.type)
    end

    return { vim.tbl_extend("keep", { type = gen_type, name = field.name }, common) }
  end

  -- Reference field → two declarations: reference type + raw Id
  local ref_type
  if #field.referenceTo > 1 then
    ref_type = "SObject"
  else
    ref_type = field.referenceTo[1]
  end

  return {
    vim.tbl_extend("keep", {
      name = get_reference_name(field.name, field.relationshipName),
      type = ref_type,
    }, common),
    vim.tbl_extend("keep", { name = field.name, type = "Id" }, common),
  }
end

--- Generate a SObjectDefinition from an sObject describe result
--- @param describe_result table The `result` field from `sf sobject describe --json`
--- @return SObjectDefinition
--- @usage local def = generateSObjectDefinition(describe_json.result)
--- @usage local def = generateSObjectDefinition({ name = "Account", fields = {...}, childRelationships = {...} })
function M.generate_definition(describe_result)
  --- @type FieldDeclaration[]
  local declarations = {}

  -- Generate field declarations
  if describe_result.fields then
    for _, field in ipairs(describe_result.fields) do
      local field_decls = generate_field(field)

      for _, decl in ipairs(field_decls) do
        table.insert(declarations, decl)
      end
    end
  end

  -- Generate child relationship declarations (named relationships first, then unnamed)
  if describe_result.childRelationships then
    for _, rel in ipairs(describe_result.childRelationships) do
      if rel.relationshipName and rel.relationshipName ~= vim.NIL then
        local rel_decls = generate_child_relationship(rel)

        for _, decl in ipairs(rel_decls) do
          table.insert(declarations, decl)
        end
      end
    end

    for _, rel in ipairs(describe_result.childRelationships) do
      if not rel.relationshipName or rel.relationshipName == vim.NIL then
        local rel_decls = generate_child_relationship(rel)

        for _, decl in ipairs(rel_decls) do
          table.insert(declarations, decl)
        end
      end
    end
  end

  return { name = describe_result.name, fields = declarations }
end

return M
