--- sf-nvim SOQL schema cache — fetch/refresh SObject list and describe
-- @license MIT

local Async = require("sf.core.async")
local Config = require("sf.config")
local Const = require("sf.const")
local Log = require("sf.core.log").scoped("soql/schema")
local OrgUtils = require("sf.org.utils")
local PathUtils = require("sf.core.path_utils")

local M = {}

--- Get the cache directory for SOQL schema data.
--- @return string
local function cache_dir()
  return PathUtils.join(Config:get_options().cache_path, "soql")
end

--- Check if a cache file is within the TTL (1 hour).
--- @param filepath string Absolute path to cache file
--- @return boolean true if cache is fresh
local function is_cache_fresh(filepath)
  if vim.fn.filereadable(filepath) == 0 then
    return false
  end

  local mtime = vim.fn.getftime(filepath)
  if mtime < 0 then
    return false
  end

  local age = vim.loop.now() - mtime
  local ttl = (Config:get_options().soql or {}).cache_ttl or 3600

  return age < ttl
end

--- Read and parse a JSON cache file.
--- @param filepath string
--- @return table|nil
local function read_cache(filepath)
  local file = io.open(filepath, "r")

  if not file then
    return nil
  end

  local content = file:read("*a")
  file:close()

  local ok, parsed = pcall(vim.json.decode, content)
  if not ok then
    return nil
  end

  return parsed
end

--- Write data to a JSON cache file.
--- @param filepath string
--- @param data table
local function write_cache(filepath, data)
  local dir = vim.fn.fnamemodify(filepath, ":h")

  if vim.fn.isdirectory(dir) == 0 then
    vim.fn.mkdir(dir, "p")
  end

  local file = io.open(filepath, "w")
  if file then
    file:write(vim.json.encode(data))
    file:close()
  end
end

--- Fetch the list of all SObjects from cache or CLI.
--- Passes array of sobject names to `on_complete`.
--- @param on_complete function|nil
function M.fetch_sobjects(on_complete)
  Async.async(function()
    if not Async.await_cli_check() then
      if on_complete then
        on_complete(nil)
      end

      return
    end

    local has_org, target_org, org_err = OrgUtils.check_default_org()
    if not has_org then
      Log.notify(org_err or "No default org set", vim.log.levels.ERROR)

      if on_complete then
        on_complete(nil)
      end

      return
    end

    local cache_file = PathUtils.join(cache_dir(), "sobjects.json")

    if is_cache_fresh(cache_file) then
      local cached = read_cache(cache_file)

      if cached and cached.sobjects then
        if on_complete then
          on_complete(cached.sobjects)
        end

        return
      end
    end

    local args = Const.get_sobject_list_args("all", nil, target_org)
    local parsed, err = Async.await_sf(args, "Fetching SObject list")

    if err or not parsed then
      Log.notify(string.format(Const.SOQL.MESSAGES.FETCH_SOBJECT_FAILED, err or "unknown error"), vim.log.levels.ERROR)

      if on_complete then
        on_complete(nil)
      end

      return
    end

    local sobjects = {}
    if parsed.result then
      for _, obj in ipairs(parsed.result) do
        table.insert(sobjects, obj.name or obj)
      end
    end

    table.sort(sobjects)

    write_cache(cache_file, { sobjects = sobjects })

    if on_complete then
      on_complete(sobjects)
    end
  end)()
end

--- Fetch describe data for a specific SObject from cache or CLI.
--- Passes `{ fields, childRelationships }` to `on_complete`.
--- @param sobject_name string
--- @param on_complete function|nil
function M.fetch_describe(sobject_name, on_complete)
  Async.async(function()
    if not Async.await_cli_check() then
      if on_complete then
        on_complete(nil)
      end

      return
    end

    local has_org, target_org, org_err = OrgUtils.check_default_org()
    if not has_org then
      Log.notify(org_err or "No default org set", vim.log.levels.ERROR)

      if on_complete then
        on_complete(nil)
      end

      return
    end

    local cache_file = PathUtils.join(cache_dir(), "describe", sobject_name .. ".json")

    if is_cache_fresh(cache_file) then
      local cached = read_cache(cache_file)
      -- Validate cache format: ensure fields have referenceTo key (added in v2)
      if cached and cached.fields and #cached.fields > 0 and cached.fields[1].referenceTo ~= nil then
        if on_complete then
          on_complete({ fields = cached.fields, childRelationships = cached.childRelationships })
        end

        return
      end
    end

    local args = Const.get_sobject_describe_args(sobject_name, nil, target_org)
    local parsed, err = Async.await_sf(args, "Describing " .. sobject_name)

    if err or not parsed then
      Log.notify(
        string.format(Const.SOQL.MESSAGES.DESCRIBE_FAILED, sobject_name, err or "unknown error"),
        vim.log.levels.ERROR
      )

      if on_complete then
        on_complete(nil)
      end

      return
    end

    local fields = {}
    local childRelationships = {}

    if parsed.result and parsed.result.fields then
      for _, f in ipairs(parsed.result.fields) do
        table.insert(fields, {
          name = f.name,
          label = f.label or "",
          field_type = f.type or "string",
          referenceTo = f.referenceTo,
          relationshipName = f.relationshipName,
        })
      end
    end

    if parsed.result and parsed.result.childRelationships then
      for _, r in ipairs(parsed.result.childRelationships) do
        if r.relationshipName and r.relationshipName ~= vim.NIL then
          table.insert(childRelationships, {
            relationshipName = r.relationshipName,
            childSObject = r.childSObject,
          })
        end
      end
    end

    write_cache(cache_file, {
      fields = fields,
      childRelationships = childRelationships,
    })

    if on_complete then
      on_complete({ fields = fields, childRelationships = childRelationships })
    end
  end)()
end

--- Delete the SObject list cache and re-fetch.
--- @param on_complete function|nil
function M.refresh_sobjects(on_complete)
  local cache_file = PathUtils.join(cache_dir(), "sobjects.json")

  if vim.fn.filereadable(cache_file) == 1 then
    os.remove(cache_file)
  end

  M.fetch_sobjects(on_complete)
end

--- Delete the describe cache for a specific SObject and re-fetch.
--- @param sobject_name string
--- @param on_complete function|nil
function M.refresh_describe(sobject_name, on_complete)
  local cache_file = PathUtils.join(cache_dir(), "describe", sobject_name .. ".json")

  if vim.fn.filereadable(cache_file) == 1 then
    os.remove(cache_file)
  end

  M.fetch_describe(sobject_name, on_complete)
end

return M
