--- sf-nvim metadata type detection for diff-against-server.
-- Parses `-meta.xml` files to determine Salesforce metadata type and member name.
-- @license MIT

local PathUtils = require("sf.core.path_utils")

local Detect = {}

--- Salesforce metadata XML namespace pattern.
-- Matches the root element of any -meta.xml file.
-- Handles optional namespace prefix (e.g. `<mns:ApexClass xmlns=...>`).
local META_XML_PATTERN_NAMESPACED = "<([A-Za-z]+):([A-Za-z]+)%s+xmlns="
local META_XML_PATTERN_PLAIN = "<([A-Za-z]+)%s+xmlns="

--- Maximum parent directory levels to search for a bundle -meta.xml.
local BUNDLE_SEARCH_DEPTH = 1

--- Parse the metadata type from a -meta.xml file's root element.
--- @param file_path string Path to the -meta.xml file
--- @return string|nil metadata_type The root element name (e.g. "ApexClass"), or nil on failure
--- @return string|nil error_message Error description if parsing fails
function Detect.parse_meta_xml_type(file_path)
  local file, open_err = io.open(file_path, "r")

  if not file then
    return nil, "Cannot open -meta.xml: " .. (open_err or "unknown error")
  end

  -- Read first 2KB (need only header and first line from -meta.xml to determine metadata type)
  local content = file:read(2048)
  file:close()

  if not content or content == "" then
    return nil, "Empty -meta.xml file: " .. file_path
  end

  local type_name

  -- Try namespaced first (e.g. <mns:ApexClass xmlns=...>)
  local _, ns_type = content:match(META_XML_PATTERN_NAMESPACED)

  if ns_type then
    type_name = ns_type
  else
    -- Fallback to plain (e.g. <ApexClass xmlns=...>)
    type_name = content:match(META_XML_PATTERN_PLAIN)
  end

  if not type_name then
    return nil, "Could not determine metadata type from: " .. file_path
  end

  return type_name, nil
end

--- Given a file path, find its companion -meta.xml if one exists.
--- For split-file metadata (`MyClass.cls`), looks for `MyClass.cls-meta.xml`.
--- @param file_path string The current file path
--- @return string|nil meta_xml_path Path to the companion -meta.xml, or nil
function Detect.find_companion_meta_xml(file_path)
  -- Already a -meta.xml file
  if file_path:match("%-meta%.xml$") then
    return file_path
  end

  local candidate = file_path .. "-meta.xml"

  if vim.fn.filereadable(candidate) == 1 then
    return candidate
  end

  return nil
end

--- Check if a parent directory contains a bundle -meta.xml.
--- Searches up to BUNDLE_SEARCH_DEPTH parent directories.
--- @param file_path string The current file path
--- @return string|nil bundle_name The bundle directory name (used as member name), or nil
--- @return string|nil bundle_meta_xml Path to the bundle's -meta.xml, or nil
function Detect.find_bundle_meta_xml(file_path)
  local dir = vim.fn.fnamemodify(file_path, ":h")

  for _ = 1, BUNDLE_SEARCH_DEPTH do
    -- List files in the directory
    local handle = vim.loop.fs_scandir(dir)

    if handle then
      while true do
        local name = vim.loop.fs_scandir_next(handle)

        if not name then
          break
        end

        if name:match("%-meta%.xml$") then
          local meta_path = PathUtils.join(dir, name)

          if vim.fn.filereadable(meta_path) == 1 then
            -- Bundle name is the parent directory name
            local bundle_name = vim.fn.fnamemodify(dir, ":t")
            return bundle_name, meta_path
          end
        end
      end
    end

    -- Move one level up
    local parent = vim.fn.fnamemodify(dir, ":h")

    if parent == dir then
      break -- Reached filesystem root
    end

    dir = parent
  end

  return nil, nil
end

--- Get the member name from file path.
--- For split-file: `MyClass.cls` -> `MyClass`
--- For single-file -meta.xml: `MyObject.object-meta.xml` -> `MyObject.object`
--- @param file_path string The current file path
--- @return string member_name
function Detect.get_member_name(file_path)
  local filename = vim.fn.fnamemodify(file_path, ":t")

  -- Single-file -meta.xml: strip the -meta.xml suffix
  local meta_stripped = filename:match("^(.*)%-meta%.xml$")

  if meta_stripped then
    return meta_stripped
  end

  -- Split-file: strip last extension
  return vim.fn.fnamemodify(filename, ":r")
end

--- Determine the metadata type and member for the current buffer's file.
--- Runs three-tier detection: bundle -> split-file -> single-file.
--- @param bufnr number The buffer number to detect from
--- @return table|nil result `{ type: string, member: string, is_bundle: boolean, local_path: string }` or nil
--- @return string|nil error_message Error description if detection fails
function Detect.detect_metadata_from_buffer(bufnr)
  local file_path = vim.api.nvim_buf_get_name(bufnr)

  if not file_path or file_path == "" then
    return nil, "Buffer has no file name (not saved?)."
  end

  -- Tier 1: Find companion -meta.xml (split-file or self)
  -- This handles the common case: MyClass.cls + MyClass.cls-meta.xml → ApexClass:MyClass
  local meta_xml_path = Detect.find_companion_meta_xml(file_path)

  if meta_xml_path then
    local meta_type, type_err = Detect.parse_meta_xml_type(meta_xml_path)

    if not meta_type then
      return nil, type_err
    end

    local member_name = Detect.get_member_name(file_path)

    return {
      type = meta_type,
      member = member_name,
      is_bundle = false,
      local_path = file_path,
    },
      nil
  end

  -- Tier 2: Bundle detection (check parent directories for -meta.xml)
  -- Handles files inside LWC/Aura bundles where no direct companion exists
  -- e.g., myCmp/utils.js → no companion → finds myCmp.js-meta.xml in parent dir
  local bundle_name, bundle_meta_xml = Detect.find_bundle_meta_xml(file_path)

  if bundle_name and bundle_meta_xml then
    local meta_type, type_err = Detect.parse_meta_xml_type(bundle_meta_xml)

    if not meta_type then
      return nil, type_err
    end

    local bundle_dir = vim.fn.fnamemodify(bundle_meta_xml, ":h")

    return {
      type = meta_type,
      member = bundle_name,
      is_bundle = true,
      local_path = bundle_dir,
    },
      nil
  end

  return nil, "Could not determine metadata type for this file. No -meta.xml found."
end

return Detect
