local Log = require("sf.core.log")
local PathUtils = require("sf.core.path_utils")
local Config = {}

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
    log_list_file = "log-list.json", -- Default filename for storing log list results
    log_dir = "logs", -- Default directory for downloaded debug logs
    metadata_types_file = "metadata-types.json", -- Default filename for metadata types schema
    metadatas_dir = "metadatas", -- Default directory for retrieved metadata files
    retrieve_file = "retrieve.json", -- Default filename for storing retrieve results
    debug_levels_dir = "debug-levels", -- Default directory for debug level configs
    apex_temp_dir = "apex", -- Default directory for temp apex scripts
    scripts_dir = "scripts", -- Default scripts directory for persistent apex scripts
    anonymous_log_dir = "anonymous", -- Default subdirectory under logs/ for anonymous apex logs
    dap_log_dir = nil, -- Default directory for DAP debug logs (default: log_dir/dap)
    dap = {
      adapter_path = nil, -- absolute path to apexReplayDebug.js
      port = 4712, -- DAP server port
      lsp_client_name = "apex_ls", -- LSP client name for breakpoint info (apex_ls or apex_ls_ts etc.)
    },
    debug = false, -- Debug mode (enables logging to file)
    logger_scope = {}, -- Module source patterns to log (empty = log everything). Example: {"test/runner", "core/job_utils"}
    debug_inspect = false, -- Show debug output on screen (requires debug = true)
  }

  return o
end

function Config:get_options()
  return self.options
end

function Config:setup(options)
  options = options or {}

  self.options = vim.tbl_deep_extend("keep", options, self.options)
  -- Normalize cache_path to absolute and derive all paths from the resolved value
  self.options.cache_path =
    PathUtils.remove_trailing_separator(PathUtils.normalize(vim.fn.fnamemodify(self.options.cache_path, ":p")))
  self.options.deploy_file = PathUtils.join(self.options.cache_path, self.options.deploy_file)
  self.options.test_results_file = PathUtils.join(self.options.cache_path, self.options.test_results_file)
  self.options.coverage_results_file = PathUtils.join(self.options.cache_path, self.options.coverage_results_file)
  self.options.log_list_file = PathUtils.join(self.options.cache_path, self.options.log_list_file)
  self.options.log_dir = PathUtils.join(self.options.cache_path, self.options.log_dir)
  self.options.metadata_types_file = PathUtils.join(self.options.cache_path, self.options.metadata_types_file)
  self.options.metadatas_dir = PathUtils.join(self.options.cache_path, self.options.metadatas_dir)
  self.options.retrieve_file = PathUtils.join(self.options.cache_path, self.options.retrieve_file)
  self.options.debug_levels_dir = PathUtils.join(self.options.cache_path, self.options.debug_levels_dir)
  self.options.anonymous_log_dir = PathUtils.join(self.options.log_dir, self.options.anonymous_log_dir)
  self.options.dap_log_dir = self.options.dap_log_dir
      and PathUtils.remove_trailing_separator(PathUtils.normalize(vim.fn.fnamemodify(self.options.dap_log_dir, ":p")))
    or PathUtils.join(self.options.log_dir, "dap")
  self.options.namespace = vim.api.nvim_create_namespace("SFNVIM")

  Log.configure(self.options)
  if self.options.debug then
    Log.log("sf.nvim debug enabled", "inspect on screen:", self.options.debug_inspect)
    Log.deb("sf.nvim options", self.options)
  end
end

local config = Config:new()
return config
