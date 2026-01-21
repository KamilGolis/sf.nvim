--- Module for handling diagnostics in the SF plugin
--- @class Diagnostics
local Config = require("sf.config")
local Utils = require("sf.core.utils")

local indexes = require("sf.core.indexes")

local Diagnostics = {}

--- Creates a new instance of the Diagnostics class
--- @return Diagnostics A new diagnostics instance
--- @usage local diagnostics = Diagnostics:new()
function Diagnostics:new()
  local o = {}
  setmetatable(o, self)
  self.__index = self
  self.diagnostic_store = {}

  return o
end

--- Clears all diagnostics from the editor and resets the diagnostic store
--- @usage diagnostics:clear_diagnostics()
function Diagnostics:clear_diagnostics()
  vim.diagnostic.reset(Config:get_options().namespace)
  self.diagnostic_store = {}
end

--- Creates a diagnostic entry from a source problem
--- @param source table The source problem containing error_message, error_line_number, error_column_number
--- @param severity number|nil Optional severity level, defaults to ERROR if not provided
--- @return table diagnostic A diagnostic entry compatible with Neovim's diagnostic format
--- @usage local diag = diagnostics:create_diagnostic({error_message = "Error", error_line_number = 5})
function Diagnostics:create_diagnostic(source, severity)
  if not severity then
    severity = vim.diagnostic.severity.ERROR
  end

  Snacks.debug.log("Diagnostics - Source:", source)

  local diagnostic = {}

  diagnostic.severity = severity
  diagnostic.message = source.error_message
  diagnostic.source = "sf"
  if source.error_line_number == nil then
    source.error_line_number = 1
  end
  if source.error_column_number == nil then
    source.error_column_number = 1
  end
  diagnostic.lnum = tonumber(source.error_line_number) - 1
  diagnostic.col = tonumber(source.error_column_number) - 1
  -- Diagnostic end line and column are set to max values
  diagnostic.end_col = 255
  -- Extract just the file name from the full path
  diagnostic.file = Utils.get_file_name(source.file_path)

  return diagnostic
end

--- Sets diagnostics in the editor based on the provided source problems
--- @param source table[] Array of source problems to convert into diagnostics
--- @usage diagnostics:set_diagnostics(error_results)
function Diagnostics:set_diagnostics(source)
  local options = Config:get_options()
  local home = vim.loop.os_homedir()

  for _, error in pairs(source) do
    if error.error_type ~= "Error" then
      return
    end

    local file_path = error.file_path:gsub("^" .. home, "~")
    error.file_path = file_path

    if not self.diagnostic_store[file_path] then
      self.diagnostic_store[file_path] = {}
    end

    local diagnostic = self:create_diagnostic(error)
    table.insert(self.diagnostic_store[file_path], diagnostic)
  end

  for file_path, diagnostics in pairs(self.diagnostic_store) do
    local buf = vim.fn.bufnr(file_path, true)

    Snacks.debug.log("Diagnostics - Buffer number:", buf)

    if buf ~= -1 then
      -- Set diagnostics for the buffer
      vim.diagnostic.set(options.namespace, buf, diagnostics)
    end
  end

  vim.cmd("Trouble diagnostics")
end

--- Create and return a singleton Diagnostics instance
--- @type Diagnostics
local diagnostics = Diagnostics:new()
return diagnostics
