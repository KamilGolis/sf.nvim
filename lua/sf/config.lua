local Snacks = require("snacks")
local PathUtils = require("sf.core.path_utils")
local Config = {}

-- Initialize debug functions as no-ops by default
-- These will be replaced with actual implementations if debug mode is enabled in setup()
_G.deb = function() end
_G.trace = function() end
_G.log = function() end
_G.inspect = function() end

--- Default configuration for plugin
function Config:new()
  local o = {}

  setmetatable(o, self)
  self.__index = self

  o.options = {
    sf_cli_path = "sf", -- Default assumes 'sf' is in the system PATH, for Windows it should be "sf.cmd"
    api_version = "65.0", -- Default API version
    cache_path = PathUtils.join(".", ".sf", "sf.nvim"), -- Default cache path
    deploy_file = "deploy.json", -- Default filename for storing deploy info
    test_results_file = "test.json", -- Default filename for storing test results
    coverage_results_file = "coverage.json", -- Default filename for storing coverage results
    delta_dir = "delta", -- Default directory for delta package
    debug = false, -- Debug mode (enables logging to file)
    debug_inspect = false, -- Show debug output on screen (requires debug = true)
  }

  -- Normalize cache_path to absolute path with OS separators (no trailing separator)
  o.options.cache_path = PathUtils.remove_trailing_separator(
    PathUtils.normalize(vim.fn.fnamemodify(o.options.cache_path, ":p"))
  )
  -- Construct full paths using path utilities
  o.options.deploy_file = PathUtils.join(o.options.cache_path, o.options.deploy_file)
  o.options.test_results_file = PathUtils.join(o.options.cache_path, o.options.test_results_file)
  o.options.coverage_results_file =
    PathUtils.join(o.options.cache_path, o.options.coverage_results_file)
  o.options.delta_path = PathUtils.join(o.options.cache_path, o.options.delta_dir)
  -- Delta package manifest file
  o.options.delta_manifest_path = PathUtils.join(o.options.delta_path, "package", "package.xml")
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

  -- Update debug functions based on debug flag
  if self.options.debug then
    -- Always log to file when debug is enabled
    _G.log = function(...)
      Snacks.debug.log(...)
    end

    -- deb() logs to file, and optionally shows on screen
    if self.options.debug_inspect then
      -- Show on screen AND log to file
      _G.deb = function(...)
        Snacks.debug.inspect(...)
        Snacks.debug.log(...)
      end
      _G.inspect = function(...)
        Snacks.debug.inspect(...)
      end
    else
      -- Only log to file, don't show on screen
      _G.deb = function(...)
        Snacks.debug.log(...)
      end
      _G.inspect = function(...)
        -- No-op unless debug_inspect is enabled
      end
    end

    _G.trace = function()
      Snacks.debug.backtrace()
    end

    if vim.fn.has("nvim-0.11") == 1 then
      vim._print = function(_, ...)
        log(...)
      end
    else
      vim.print = log
    end

    log("sf.nvim debug enabled", "inspect on screen:", self.options.debug_inspect)
    deb("sf.nvim options", self.options)
  else
    _G.deb = function() end
    _G.trace = function() end
    _G.log = function() end
    _G.inspect = function() end
  end
end

local config = Config:new()
return config
