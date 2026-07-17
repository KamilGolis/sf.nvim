--- Pre-deployment precondition checks.
--- Validates CLI availability and checks no conflicting deployment is running.

local Log = require("sf.core.log").scoped("deploy/precheck")
local State = require("sf.core.state")

local M = {}

--- Validates pre-deployment conditions using state registry
--- @return boolean valid Whether pre-deployment conditions are met
--- @return string|nil error_message Error message if validation failed
function M.validate_deployment_preconditions()
  if State.is_busy("deploy") then
    return false, "A deployment is already in progress. Please wait for it to finish."
  end

  return true, nil
end

--- Checks that SF CLI is installed and no conflicting job is running.
--- Must be called inside an async.async() block.
--- @return boolean ready True if both preconditions are met
function M.ensure_cli_ready()
  local ok = require("sf.core.async").await_cli_check()
  if not ok then
    return false
  end

  local valid, err = M.validate_deployment_preconditions()
  if not valid then
    if err then
      Log.notify(err, vim.log.levels.WARN)
    end

    return false
  end

  return true
end

return M
