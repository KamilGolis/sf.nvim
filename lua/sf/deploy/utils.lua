--- Deploy utilities — re-exported from domain sub-modules.
--- @class DeployUtils

local M = {}

-- Merge all sub-module exports into a single table
for _, mod in ipairs({
  "sf.deploy.context",
  "sf.deploy.result",
  "sf.deploy.precheck",
  "sf.deploy.delta",
  "sf.deploy.quickfix",
}) do
  local m = require(mod)

  for k, v in pairs(m) do
    M[k] = v
  end
end

return M
