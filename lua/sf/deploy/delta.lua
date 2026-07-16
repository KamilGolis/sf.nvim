--- Git-delta file resolution for changed-files deployment.
--- Handles pairing LWC/aura directories, -meta.xml companions,
--- deduplication, and git repo validation.

local Async = require("sf.core.async")
local Config = require("sf.config")

local M = {}

--- Resolves a list of changed files into deploy-ready paths.
--- Handles: LWC/aura → parent directory, -meta.xml → base file pairing,
--- base file → -meta.xml pairing, dedup, existence filtering.
--- @param files string[] List of git-diff file paths
--- @return table|nil deduplicated deploy paths
function M.resolve_deploy_paths(files)
  local resolved = {}

  -- TODO: More bundled metadata will go here in future.
  for _, file in ipairs(files) do
    -- LWC / Aura: deploy the whole bundle directory
    if file:match("/lwc/") or file:match("/aura/") then
      local dir = vim.fn.fnamemodify(file, ":h")
      table.insert(resolved, dir)
    -- -meta.xml file: pair with its base file
    elseif file:match("%-meta%.xml$") then
      local base = file:gsub("%-meta%.xml$", "")
      table.insert(resolved, file)
      table.insert(resolved, base)
    -- Base file: pair with its -meta.xml
    else
      table.insert(resolved, file)
      table.insert(resolved, file .. "-meta.xml")
    end
  end

  -- Deduplicate and filter to existing files only
  local seen = {}
  local result = {}

  for _, path in ipairs(resolved) do
    if not seen[path] and vim.fn.filereadable(path) == 1 then
      seen[path] = true
      table.insert(result, path)
    end
  end

  return result
end

--- Validates we're inside a git work tree.
--- @return boolean ok True if in a git repo
--- @return string|nil err Error message if not
function M.require_git_repo()
  local git = Config:get_options().git_path or "git"
  local stdout, code = Async.await_system(git, { "rev-parse", "--is-inside-work-tree" })

  if code ~= 0 then
    return false, "Not inside a git repository"
  end

  return true, nil
end

return M
