# Copilot Instructions for sf.nvim

## Project Overview

sf.nvim is a Neovim plugin for Salesforce development that integrates the SF CLI directly into Neovim. It provides commands for deploying metadata, running Apex tests with coverage, managing orgs, and viewing debug logs.

## Build and Lint

**Linting:**
```bash
stylua --check .
```

**Format code:**
```bash
stylua .
```

**Configuration:** See `stylua.toml` for code style settings (120 char width, 2-space indents, Unix line endings)

## Architecture

### Module Organization

The plugin follows a domain-driven structure under `lua/sf/`:

- **`core/`** - Shared utilities and infrastructure
  - `utils.lua` - General helpers (get SF project root, file name extraction)
  - `process.lua` - Process/job execution 
  - `diagnostics.lua` - Diagnostic management and storage
  - `indexes.lua` - File indexing for autocomplete and navigation
  - `job_utils.lua` - Job state management

- **`deploy/`** - Metadata deployment
  - `metadata.lua` - Main deployment orchestration (current file, changed files, selected)
  - `utils.lua` - Deployment-specific helpers

- **`test/`** - Apex test execution
  - `runner.lua` - Test execution (class-level, method-level)
  - `coverage.lua` - Coverage display and management
  - `results_buffer.lua` - Test results UI

- **`org/`** - Org connection management
  - `connect.lua` - Org selection and default org setting
  - `utils.lua` - Org-related utilities

- **`log/`** - Debug log management
  - `list.lua` - Log listing and viewing

- **`config.lua`** - Plugin configuration with defaults
- **`const.lua`** - Constants: SF CLI command builders, regex patterns, icons, string formats

### Plugin Entry Points

1. **`plugin/sf.lua`** - Main entry point that:
   - Checks for SF project (`.forceignore` or `sfdx-project.json`)
   - Registers the `:Sf` command with subcommands
   - Sets up autocommands (diagnostics on BufEnter, coverage display)
   - Indexes files from default package directory

2. **`lua/sf/init.lua`** - Module setup function called by users in their config

### Command Architecture

The `:Sf` command uses a hierarchical subcommand structure:
- `Sf org set` - Select default org
- `Sf deploy metadata|changed|selected [force]` - Deploy operations
- `Sf test class|method|result` - Test operations
- `Sf coverage class|method|result|on|off` - Coverage operations  
- `Sf log list` - Log operations

### Key Data Flows

**Deployment:**
1. User calls `:Sf deploy metadata`
2. `deploy/metadata.lua` validates preconditions (CLI available, no active job, default org set)
3. Creates deployment context with file path, options, callbacks
4. Executes SF CLI via `core/process.lua` 
5. Parses JSON response, stores in cache (`.sf/sf.nvim/deploy.json`)
6. Updates diagnostics via `core/diagnostics.lua`

**Testing with Coverage:**
1. User calls `:Sf test class` or `:Sf coverage class`
2. `test/runner.lua` extracts class/method name from current buffer
3. Builds SF CLI command using `const.lua` builders
4. Executes test via `core/process.lua`
5. Parses results, stores in cache (`.sf/sf.nvim/test.json`, `.sf/sf.nvim/coverage.json`)
6. `test/coverage.lua` displays inline coverage indicators via virtual text
7. `test/results_buffer.lua` shows test results in split buffer

## Key Conventions

### Configuration Pattern

Config is a singleton (`config.lua:new()` called once at module load). All modules access it via:
```lua
local Config = require("sf.config")
local options = Config:get_options()
```

### SF CLI Command Building

Never construct CLI commands as strings. Use builders from `const.lua`:
```lua
local args = Const.get_apex_test_class_args("TestClass", true) -- with_coverage = true
local args = Const.get_current_file_deploy_args(file_path, api_version, force)
```

### Job Management Pattern

Deployment and test jobs follow this pattern:
1. Check if job is running (`deploy_job` or `test_job` module variable)
2. Clear previous diagnostics
3. Create Snacks progress handle
4. Start job via `core/process.lua` or `core/job_utils.lua`
5. Store job reference
6. Use callbacks for completion/failure
7. Set job to nil on completion

### Diagnostic Storage

Diagnostics are stored by filename (not full path) in `diagnostics.diagnostic_store`. The BufEnter autocmd in `plugin/sf.lua` applies stored diagnostics when files are opened.

### File Path Resolution

Always get SF project root via `Utils.get_sf_root()` which searches upward for `.forceignore` or `sfdx-project.json`. Default package path comes from `sfdx-project.json` parsing.

### Cache Files

All cache files go in `.sf/sf.nvim/` (configurable via `cache_path`):
- `deploy.json` - Last deployment info
- `test.json` - Last test results
- `coverage.json` - Last coverage data
- `delta/` - Delta package for changed files

### Dependencies

The plugin requires:
- **Snacks.nvim** - For progress UI, debug utilities, and pickers
- **SF CLI** - The Salesforce CLI (`sf` command)
- **Optional:** `sgd` plugin for delta deployments of changed files

### LuaJIT and Neovim API

This is a Neovim plugin using LuaJIT runtime. Use:
- `vim.loop` (libuv) for async I/O, not `os.execute`
- `vim.fn` for Vim functions
- `vim.api` for Neovim API
- Module pattern with `M = {}` and `return M`
- OOP with metatables when needed (see `Config:new()`, `Metadata:new()`)

### Cross-Platform Path Handling

**CRITICAL:** Always use `PathUtils` from `lua/sf/core/path_utils.lua` for path operations:
- `PathUtils.join(...)` - Join path segments with OS-appropriate separator
- `PathUtils.get_filename(path)` - Extract filename (OS-aware, replaces string patterns)
- `PathUtils.normalize(path)` - Normalize to OS format
- `PathUtils.ensure_trailing_separator(path)` - Add separator if missing
- `PathUtils.to_forward_slashes(path)` - Convert to forward slashes for SF CLI

Never hardcode `/` or `\` separators or use string concatenation for paths. The plugin must work on both Windows and Unix systems.
