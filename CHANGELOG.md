# CHANGELOG

## Release v0.4

### 🎉 New Features

#### Code Analyzer Integration

- Code Analyzer Wrapper: Scan metadata files with `sf code-analyzer` and display violations as inline diagnostics
- Four new commands for the scan workflow:
  - `:Sf scan all` — Scan entire project directory
  - `:Sf scan metadata` — Scan current buffer's file
  - `:Sf scan resume` — Recreate diagnostics from last cached scan results
  - `:Sf scan clear` — Clear all scan diagnostics
- Rich violation display with rule name, severity, engine, and resource info per diagnostic
- Async execution with LSP progress spinner and graceful error handling

#### SOQL Query Builder

- Interactive schema-aware query builder (`:Sf soql open`) with custom `sfsoqlbuilder` filetype and syntax highlighting
- Multi-select field picker with type annotations and labels from org schema
- Parent-relationship dotted fields (e.g. `Owner.Name`, `MyLookup__r.Custom__c`) via guided 2-step picker
- WHERE, ORDER BY, GROUP BY, and HAVING clause support with field-guided operators
- Child-relationship subqueries with independent nested builder windows
- Save queries to `.soql` files with auto-dedup naming; resume with `:Sf soql resume`
- Live compiled SOQL preview at the bottom of the builder buffer
- Result format cycling (human-readable table, CSV, JSON) via `f` key
- ALL ROWS (`T`) and Tooling API (`t`) toggles
- Help overlay (`?`) showing all keybindings
- Raw SOQL runner (`:Sf soql run`), re-execute last query (`:Sf soql rerun`), clear results (`:Sf soql clear`)

#### Apex Cache Management

- sObject cache status, clear, and rebuild commands:
  - `:Sf apex cache status` — Show cache file count and disk usage
  - `:Sf apex cache clear` — Delete all cached sObject describe files
  - `:Sf apex cache rebuild` — Rebuild sObject cache from org (~10x faster with curl)

#### UI Improvements

- Debug Levels and Trace Flags windows migrated to `Snacks.win` for consistent floating-window behavior
- Syntax highlighting for debug level and trace flag buffers moved from ftplugin to dedicated `syntax/` files
- Org picker preview redesigned with icon-decorated details (alias, instance URL, username, org ID, connected status, devhub/sandbox flags, API version)
- Screenshots added to README for SOQL builder, debug levels, and trace flags

### 🐛 Bug Fixes

- Fixed LIMIT and OFFSET keybindings: split combined `L / O` into separate `L` and `O` keys
- Fixed `d` key: now deletes LIMIT/OFFSET items in addition to fields, WHERE, ORDER BY, and subqueries
- Fixed `:Sf soql resume` parsing: restored GROUP BY and HAVING clauses from saved queries
- Fixed `:Sf soql run` result buffer: now opens in a new window instead of replacing the query buffer

### ♻️ Code Quality

- Multi-namespace diagnostic support: `Diagnostics:clear_diagnostics(ns)` and `Diagnostics:apply(ns, buf, diagnostics)` replace the hardcoded single-namespace approach
- Namespace configuration refactored into `options.namespaces` table (`deploy`, `scan`, `log_analysis`)
- Removed unused code: `M.ORG_DETAILS_FORMAT`, `M.SF_CLI.PROJECT.GENERATE`, `get_project_generate_args`, old `get_data_query_args`
- Org preview lines inlined with `Const.ICONS` instead of the removed `M.ORG_DETAILS_FORMAT` table
- `.gitignore` updated with `.codegraph/`, `.omp/`, `.reasonix/`, `reasonix.toml` entries

### 📝 Configuration Updates

- New config options:
  - `scan_dir` — Directory for code-analyzer scan results (default: `"scan"` under `cache_path`)
  - `scan_results_file` — Filename for code-analyzer JSON output (default: `"metadata.json"`)

### 🔧 Commands

- New commands added:
  - `:Sf scan all` — Scan entire project
  - `:Sf scan metadata` — Scan current file
  - `:Sf scan resume` — Reload cached scan results
  - `:Sf scan clear` — Clear scan diagnostics
  - `:Sf soql open` — Open SOQL query builder
  - `:Sf soql run` — Run raw SOQL query
  - `:Sf soql rerun` — Re-execute last query
  - `:Sf soql resume` — Resume saved query
  - `:Sf soql clear` — Clear SOQL result files
  - `:Sf apex cache status` — Show sObject cache status
  - `:Sf apex cache clear` — Clear sObject cache
  - `:Sf apex cache rebuild` — Rebuild sObject cache

### 📚 Documentation

- Added `doc/snacks-win.md` — Complete reference for `Snacks.win` integration
- README updated with SOQL builder, code analyzer, and apex cache command documentation
- Screenshots added for all major features

---

## Release v0.3

### 🎉 New Features

#### DAP Integration & Debug Improvements

- Debug Adapter Protocol Integration: Integrated DAP configuration into the plugin for seamless debugging
- Debug Log Generation: New command to generate and prepare debug logs for inspection
- Enhanced Debug Experience: Improved debugging workflow with built-in DAP support

#### Apex Class Stubs Generation

- Faux Class Generation: Implement stub generation mechanism for Apex classes
- LSP Support: Create stubs for improved Apex LSP functionality and code completion

#### Git Integration Enhancements

- Removed `sgd` Plugin Dependency: Simplified git diff operations by using native git log
- Better Performance: Direct git integration without external plugin dependencies

#### LSP Progress Redesign

- Improved Progress Display: LSP progress notifications now display correctly and consistently
- Better User Feedback: Enhanced visibility of long-running LSP operations

### ♻️ Code Quality

- Async Operations Refactor: Converted callback-based async operations to coroutines across the entire codebase
- Reduced Callback Hell: Cleaner, more maintainable async code using Lua coroutines
- Improved Code Reliability: Better error handling and state management in async operations

### 🔧 Related Issues Resolved

- Resolve #39 - DAP configuration integration and debug log generation
- Resolve #38 - Apex faux class generation for LSP
- Resolve #46 - Removed sgd plugin dependency
- Resolve #47 - LSP progress display improvements

---

## Release v0.2

### 🎉 New Features

#### Debug Level Management

- Debug Level Picker: Create, edit, and delete debug log levels with an interactive buffer editor
- Field configuration with syntax highlighting and inline help
- Support for all debug level categories (Apex Code, Apex Profiling, Callout, Database, System, Validation, Visualforce, Wave, Workflow)

#### Trace Flag Management

- Trace Flags Window: Create and delete debug log trace flags for the current user
- Interactive editor with date/time picker and debug level selection
- Auto-resolution of overlapping trace flags
- Trace flag deletion with conflict detection

#### Anonymous Apex Execution

- Execute Anonymous Apex: Run .apex files with integrated log parsing
- Three execution modes:
  - Execute current buffer
  - Create and execute new scripts
  - Browse and execute from scripts directory
- Log saving to logs/anonymous/<timestamp>.log
- Error diagnostics displayed inline with compile and runtime errors

#### Apex Unit Test Enhancements

- LSP Code Actions: Run Apex Unit Tests via `vim.lsp.buf.code_action()` without requiring external LSP
- Test Actions Picker: Snacks-based picker to display available test actions
- Method-level and class-level test execution via code actions
- Coverage execution support through code actions

### 🐛 Bug Fixes

- Fixed unit test class discovery issue when class has leading comments
- Improved test class detection with fallback when cursor is on top-level comments
- Made Trouble diagnostics call safe with `pcall` wrapper (non-blocking when Trouble is unavailable)
- Enhanced debug log cleanup to include anonymous Apex logs

### ♻️ Code Quality

- Hardcoded Strings Refactor: Moved all hardcoded strings to constants (`Const.SF_CLI_MESSAGES`)
- Comprehensive CLI message constants for all new features
- Improved Lua pattern matching in test source navigation
- Better handling of null values from JSON responses

### 📝 Configuration Updates

- New cache and configuration directories:
  - `debug_levels_dir`: Debug level configurations
  - `apex_temp_dir`: Temporary Apex script files
  - `scripts_dir`: Persistent user Apex scripts
  - `anonymous_log_dir`: Anonymous Apex execution logs
  - `retrieve_file`: Retrieve operation results cache

### 🔧 Commands

- New Commands Added:
  - `:Sf apex execute file` - Execute current Apex file
  - `:Sf apex execute new` - Create new Apex script
  - `:Sf apex execute list` - Browse and execute scripts
  - `:Sf apex execute cleanup` - Delete temporary files
  - `:Sf debug level new` - Create debug level
  - `:Sf debug level edit` - Edit debug level
  - `:Sf debug level delete` - Delete debug level
  - `:Sf debug trace new` - Create trace flag
  - `:Sf debug trace delete` - Delete trace flag
  - `:Sf test action` - Show available test actions via picker

### 📚 Documentation

- Updated README with new features documentation
- Added configuration table for new directories and files
- Added usage examples for all new commands
- Sample keymaps for new functionality

---

## Release v0.1

### 🎉 First Release

This is the first official release of sf.nvim, featuring a comprehensive suite of tools for Salesforce development in Neovim.

### ✨ Core Features

#### Metadata Management

- Metadata Deployment - Deploy current file, changed files, or selected files
- Metadata Retrieval - Retrieve metadata individually, by type, or refresh from org
- Server Diff - Compare local metadata against server version with scroll-synced diff view
- Schema Management - Refresh org metadata type index and retrieve type details

#### Apex Testing & Coverage

- Apex Test Execution - Run tests at class or method level with detailed results
- Code Coverage - Visual coverage indicators in gutter with detailed statistics

#### Org Management

- Easy org switching between Salesforce orgs

#### Debug Logs

- List, fetch, and analyze debug logs
- Rich per-token highlighting with tree view
- Log caching for quick resumption
- Interactive picker with metadata preview

#### Developer Experience

- Inline diagnostics for deployment failures
- Rich UI powered by Snacks.nvim
- Asynchronous operations with progress indicators
- Cross-platform support (Windows, macOS, Linux)

### Technical Implementation

#### Added:

- Unit tests using mini.test framework
- CI/CD pipeline setup
- Comprehensive configuration system

#### Fixed:

- Bug fixes including logList.json filename handling (#13)
