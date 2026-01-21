local Config = require("sf.config")
local Utils = require("sf.core.utils")

--- Main SF plugin module
--- @class Sf
local Sf = {}

--- Plugin setup function that initializes the SF plugin with provided options
--- @param opts table Options for the plugin configuration
--- @usage require("sf").setup({sf_cli_path = "sf", api_version = "58.0"})
function Sf.setup(opts)
  if not Utils.has_sfdx_project() then
    return
  end
  Sf.config = Config:setup(opts)
end

return Sf
