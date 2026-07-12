# CHANGELOG

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
