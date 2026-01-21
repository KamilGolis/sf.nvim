local Snacks = require("snacks")
local Config = {}
-- Add snacks debug functions
_G.dd = function(...)
  Snacks.debug.inspect(...)
end
_G.bt = function()
  Snacks.debug.backtrace()
end
vim.print = _G.dd

--- Default configuration for plugin
function Config:new()
  local o = {}

  setmetatable(o, self)
  self.__index = self

  o.options = {
    sf_cli_path = "sf",                      -- Default assumes 'sf' is in the system PATH
    api_version = "58.0",                    -- Default API version
    cache_path = ".sf/sf.nvim/",             -- Default cache path
    deploy_file = "deploy.json",             -- Default filename for storing deploy info
    test_results_file = "test.json",         -- Default filename for storing test results
    coverage_results_file = "coverage.json", -- Default filename for storing coverage results
    delta_dir = "delta",                     -- Default directory for delta package
    debug = false,                           -- Debug mode
  }

  -- Ensure cache_path ends with a separator
  o.options.cache_path = vim.fn.fnamemodify(o.options.cache_path, ":p")
  -- Construct full path for deploy_file
  o.options.deploy_file = vim.fn.fnamemodify(o.options.cache_path .. o.options.deploy_file, ":p")
  -- Construct full path for test_results_file
  o.options.test_results_file = vim.fn.fnamemodify(o.options.cache_path .. o.options.test_results_file, ":p")
  -- Construct full path for coverage_results_file
  o.options.coverage_results_file = vim.fn.fnamemodify(o.options.cache_path .. o.options.coverage_results_file, ":p")
  -- Delta package manifest path
  o.options.delta_path = vim.fn.fnamemodify(o.options.cache_path .. o.options.delta_dir, ":p")
  -- Delta package manifest file
  o.options.delta_manifest_path = o.options.delta_path .. "package/package.xml"
  -- Create a namespace for the plugin
  o.options.namespace = vim.api.nvim_create_namespace("SFNVIM")

  return o
end

function Config:get_options()
  return self.options
end

function Config:setup(options)
  options = options or {}

  self.options = vim.tbl_deep_extend("keep", options, self.options)

  if self.options.debug then
    Snacks.debug.log("sf.nvim plugin initialized with options:", self.options)
    Snacks.debug.inspect("sf.nvim plugin initialized with options:", self.options)
  end
end

local config = Config:new()
return config
