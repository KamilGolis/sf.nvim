# sf.nvim

A comprehensive Neovim plugin for Salesforce development that integrates the Salesforce CLI directly into your editor workflow.

As a Salesforce developer, I’ve mostly used VS Code and WebStorm with Illuminated Cloud until now. However, I love Neovim, so I decided to build my own 'wrapper' for the Salesforce CLI. Initially, it was just a simple plugin that executed commands and displayed the output within Neovim. I didn't intend to publish it because it's still quite buggy, lacks features, and might not even work properly. But a recent computer crash convinced me to push it to GitHub just to have a backup. While there are already a few interesting Salesforce plugins for Neovim out there, none of them quite clicked for me, so I decided to build something of my own.

<div align="center">

![Neovim](https://img.shields.io/badge/NeoVim-%2357A143.svg?&style=for-the-badge&logo=neovim&logoColor=white)
![Lua](https://img.shields.io/badge/lua-%232C2D72.svg?style=for-the-badge&logo=lua&logoColor=white)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg?style=for-the-badge)](https://opensource.org/licenses/MIT)

</div>

## ✨ Features

- 🚀 **Metadata Deployment** - Deploy current file, changed files, or selected files
- 🧪 **Apex Test Execution** - Run tests at class or method level with detailed results
- ⚡ **LSP Code Actions** - Run tests via `vim.lsp.buf.code_action()` with integrated test actions, no Apex LSP required
- 📊 **Code Coverage** - Visual coverage indicators with detailed statistics
- 🔌 **Org Management** - Easy switching between Salesforce orgs with rich detail preview
- 📝 **Debug Logs** - List, fetch, and analyze debug logs with rich per-token highlighting and tree view
:- 📝 **Anonymous Apex** - Execute anonymous Apex scripts from files with log saving and error diagnostics
- 🔧 **Debug Level Management** - Create, edit, and delete debug levels with an interactive buffer and syntax highlighting
- 🏷️ **Trace Flag Management** - Create new trace flags with interactive buffer, debug level picker with preview, and auto-conflict resolution
- 📦 **Schema Management** - Refresh org metadata type index and retrieve type details
- ⬇️  **Metadata Retrieval** - Retrieve metadata individually, by type, or refresh the current buffer from org
- ↔️  **Server Diff** - Diff local metadata against the server version in a dedicated tab with scroll-synced views
- 🔍 **Diagnostics** - Inline error display for deployment failures
- 🔍 **Code Analyzer** - Scan metadata files with sf code-analyzer and display violations as inline diagnostics
- 🌐 **SOQL Query Builder** - Interactive schema-aware query builder with field picker, WHERE/ORDER BY, subqueries, save/resume, and live execution
- 💾 **Cross-platform** - Works on Windows, macOS, and Linux
- ⚡ **Fast** - Asynchronous operations with progress indicators
- 🎨 **Rich UI** - Beautiful pickers and result buffers powered by Snacks.nvim

## 📋 Requirements

- [Neovim](https://neovim.io/) >= 0.11.0
- [Salesforce CLI](https://developer.salesforce.com/tools/salesforcecli) (`sf` command)
- [Snacks.nvim](https://github.com/folke/snacks.nvim) - For UI components
- **Optional:** [curl](https://curl.se/) - For batch REST API calls when rebuilding sObject cache (auto-detected, ~10x faster than sequential CLI)
- **Optional:** Progress is displayed via Neovim's built-in LSP statusline indicator. Add `%{%v:lua.vim.lsp.status()%}` to your statusline if not already present.

## 📦 Installation

### Using [lazy.nvim](https://github.com/folke/lazy.nvim)

```lua
{
  "kamilgolis/sf.nvim",
  dependencies = {
    "folke/snacks.nvim",
  },
  config = function()
    require("sf").setup({
      -- Your configuration here (see Configuration section)
    })
  end,
}
```

### Using [packer.nvim](https://github.com/wbthomason/packer.nvim)

```lua
use {
  "kamilgolis/sf.nvim",
  requires = {
    "folke/snacks.nvim",
  },
  config = function()
    require("sf").setup({
      -- Your configuration here
    })
  end,
}
```

## ⚙️ Configuration

### Default Configuration

```lua
require("sf").setup({
  -- Salesforce CLI executable path
  -- For Windows, use "sf.cmd"
  sf_cli_path = "sf",

  -- API version for deployments
  api_version = "65.0",

  -- Cache directory
  cache_path = "./.sf/sf.nvim",

  -- Deployment and test results
  deploy_file = "deploy.json",
  test_results_file = "test.json",
  coverage_results_file = "coverage.json",

  -- Debug logs
  log_list_file = "log-list.json",
  -- Metadata
  retrieve_file = "retrieve.json",
  metadata_types_file = "metadata-types.json",
  metadatas_dir = "metadatas",

  -- Debug level management
  debug_levels_dir = "debug-levels",

  -- Anonymous Apex
  apex_temp_dir = "apex",
  scripts_dir = "scripts",
  anonymous_log_dir = "anonymous",
  scan_dir = "scan",
  scan_results_file = "metadata.json",

  -- DAP (Apex Replay Debugger)
  dap_log_dir = nil, -- defaults to log_dir/dap
  dap = {
    adapter_path = nil, -- absolute path to apexReplayDebug.js
    port = 4712,
  },

  -- Debug mode
  debug = false,
  debug_inspect = false,
  logger_scope = {},
})
```

### Configuration Options

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `sf_cli_path` | `string` | `"sf"` | Path to SF CLI executable. Use `"sf.cmd"` on Windows |
| `api_version` | `string` | `"65.0"` | Salesforce API version for deployments |
| `cache_path` | `string` | `"./.sf/sf.nvim"` | Directory for cache files |
| `deploy_file` | `string` | `"deploy.json"` | Filename for deployment results |
| `test_results_file` | `string` | `"test.json"` | Filename for test results |
| `coverage_results_file` | `string` | `"coverage.json"` | Filename for coverage results |
| `log_list_file` | `string` | `"logList.json"` | Filename for cached log list |
| `log_dir` | `string` | `"logs"` | Directory for downloaded debug logs |
| `delta_dir` | `string` | `"delta"` | Directory for delta package |
| `metadata_types_file` | `string` | `"metadata-types.json"` | Filename for cached metadata types schema |
| `metadatas_dir` | `string` | `"metadatas"` | Directory for retrieved metadata files |
| `retrieve_file` | `string` | `"retrieve.json"` | Filename for retrieve results cache |
| `debug_levels_dir` | `string` | `"debug-levels"` | Directory for debug level config files |
| `apex_temp_dir` | `string` | `"apex"` | Directory for temp .apex files under cache_path |
| `scripts_dir` | `string` | `"scripts"` | Directory for persistent Apex scripts under project root |
| `anonymous_log_dir` | `string` | `"anonymous"` | Subdirectory under log_dir for anonymous Apex logs |
| `scan_dir` | `string` | `"scan"` | Subdirectory under cache_path for scan results |
| `scan_results_file` | `string` | `"metadata.json"` | Filename for code-analyzer output |
| `dap_log_dir` | `string` | `nil` | Directory for DAP debug logs (defaults to `log_dir/dap`) |
| `dap.lsp_client_name` | `string` | `"apex_ls"` | Apex LSP client name for breakpoint resolution (e.g. `apex_ls` or `apex_ls_ts`) |
| `debug` | `boolean` | `false` | Enable debug logging to file |
| `debug_inspect` | `boolean` | `false` | Show debug output on screen |
| `logger_scope` | `table` | `{}` | List of module source patterns to include in debug output (empty = log all modules). Example: `{"test/runner", "core/job_utils"}` |

### Debug Configuration

sf.nvim provides two-level debug control:

**File-Only Debug** (Recommended for debugging):
```lua
require("sf").setup({
  debug = true,           -- ✅ Logs everything to file
  debug_inspect = false,  -- ❌ Nothing shown on screen
})
```

**Full Debug** (For active development):
```lua
require("sf").setup({
  debug = true,          -- ✅ Logs everything to file
  debug_inspect = true,  -- ✅ Shows data on screen too
})
```

View debug logs: `:lua Snacks.debug.log()`
**Scope filtering** — limit debug output to specific modules:
```lua
require("sf").setup({
  debug = true,
  logger_scope = { "test/runner", "core/job_utils" }, -- only these modules
})
```

Available module names for `logger_scope`:
| Module path | Description |
|-------------|-------------|
| `apex/execute` | Anonymous Apex execution |
| `code_analyzer/scan` | Code Analyzer scan execution |
| `config` | Plugin configuration |
| `core/diagnostics` | Deploy diagnostics system |
| `core/job_utils` | CLI job creation and management |
| `core/utils` | Core utilities (project root, etc.) |
| `debug/level` | Debug level create/edit/delete |
| `faux/runner` | sObject cache rebuild orchestration |
| `debug/utils` | Debug level workflow (org/user/trace queries) |
| `deploy/utils` | Deployment utilities |
| `diff/runner` | Diff job orchestration |
| `log/list` | Log listing and picking |
| `log/utils` | Log processing utilities |
| `org/utils` | Org utilities |
| `retrieve/metadata` | Metadata retrieval |
| `schema/refresh` | Schema fetch from org |
| `schema/retrieve` | Schema record retrieval |
| `test/coverage` | Code coverage display |
| `test/runner` | Test execution runner |
| `trace/flag` | Trace flag create/edit/delete |

## 🎮 Commands

All commands are available under the `:Sf` command with subcommands:

### Org Management

```vim
:Sf org set          " Select and set default org via picker (with org details preview)
:Sf org open         " Open default org in browser
```

### Schema

```vim
:Sf schema refresh   " Refresh org metadata type list
:Sf schema retrieve  " Select and retrieve metadata of a type
:Sf schema cleanup   " Delete cached schema files (like `metadata-types.json` and all files under `metadatas` directory)
```
### Metadata Retrieval

```vim
:Sf retrieve metadata   " Select type, then pick items to retrieve
:Sf retrieve type       " Select type, retrieve all items at once
:Sf retrieve refresh    " Refresh current buffer from server (skips picker, uses buffer detection)
:Sf retrieve diff       " Diff current buffer against server version (new tab, scroll-synced)
```
### Deployment

```vim
:Sf deploy metadata         " Deploy current file
:Sf deploy metadata force   " Deploy current file (ignore conflicts)
:Sf deploy changed          " Deploy changed files (git-diff based)
:Sf deploy changed force    " Deploy changed files (ignore conflicts)
:Sf deploy selected         " Deploy selected files from quickfix list
:Sf deploy selected force   " Deploy selected files (ignore conflicts)
```

### Testing

```vim
:Sf test class    " Run all tests in current test class
:Sf test method   " Run test method at cursor position
:Sf test result   " Show last test results
:Sf test action   " Show available test actions via picker (alternative to LSP code actions)
```

### Coverage

```vim
:Sf coverage class    " Run coverage for current test class
:Sf coverage method   " Run coverage for test method at cursor
:Sf coverage result   " Show last coverage results
:Sf coverage on       " Enable coverage display (signs in gutter)
:Sf coverage off      " Disable coverage display
```

### Debug Logs

```vim
:Sf log list             " Fetch and list debug logs from org
:Sf log resume           " Show cached debug logs from `log-list.json` (falls back to list)
:Sf log debug            " Resume cached logs and copy selected to DAP directory
:Sf log analysis basic   " Analyze a selected log with basic tree view and per-token highlighting
:Sf log cleanup          " Delete cached log files and `log-list.json`
```

### Anonymous Apex

```vim
:Sf apex execute file     " Execute Apex from current buffer
:Sf apex execute new      " Create new blank Apex script in `scripts/`
:Sf apex execute list     " Browse and execute scripts from `scripts/`
:Sf apex execute cleanup  " Delete temp .apex files from cache
:Sf apex cache status     " Show sObject cache status
:Sf apex cache clear      " Clear sObject cache files
:Sf apex cache rebuild    " Rebuild sObject cache from org
```

### Debug Levels

```vim
:Sf debug level new      " Create a new debug level with interactive editor
:Sf debug level edit     " Edit an existing debug level
:Sf debug level delete   " Delete a debug level
```

### Debug Trace Flags

```vim
:Sf debug trace new     " Create a new trace flag with interactive editor
:Sf debug trace delete  " Delete a trace flag
```

### Code Analyzer

```vim
:Sf scan all        " Scan entire project with code-analyzer and show violations as diagnostics
:Sf scan metadata   " Scan current buffer with code-analyzer and show violations as diagnostics
:Sf scan resume     " Recreate diagnostics from last cached scan results
:Sf scan clear      " Clear all scan diagnostics
```

### SOQL Query Builder

```vim
:Sf soql open     " Open the SOQL query builder (pick sObject then build)
:Sf soql run      " Open a scratch buffer to write and execute raw SOQL
:Sf soql rerun    " Re-execute the last SOQL query
:Sf soql resume   " Browse saved .soql files and resume editing
:Sf soql clear    " Clear SOQL result files (keeps saved queries)
```

## 📖 Usage Examples

### Basic Workflow

1. **Set your default org:**
   ```vim
   :Sf org set
   ```

2. **Deploy your changes:**
   ```vim
   :Sf deploy metadata
   ```

3. **Run tests:**
   ```vim
   :Sf test class
   ```

4. **View coverage:**
   ```vim
   :Sf coverage class
   :Sf coverage on
   ```

### Keybindings Example

Add these to your Neovim configuration for quick access:

```lua
vim.keymap.set("n", "<leader>so", ":Sf org set<CR>", { desc = "Set Salesforce org" })
vim.keymap.set("n", "<leader>sO", ":Sf org open<CR>", { desc = "Open org in browser" })
vim.keymap.set("n", "<leader>sd", ":Sf deploy metadata<CR>", { desc = "Deploy current file" })
vim.keymap.set("n", "<leader>sD", ":Sf deploy changed<CR>", { desc = "Deploy changed files" })
vim.keymap.set("n", "<leader>st", ":Sf test class<CR>", { desc = "Run test class" })
vim.keymap.set("n", "<leader>sm", ":Sf test method<CR>", { desc = "Run test method" })
vim.keymap.set("n", "<leader>sc", ":Sf coverage class<CR>", { desc = "Run coverage" })
vim.keymap.set("n", "<leader>sC", ":Sf coverage on<CR>", { desc = "Toggle coverage display" })
vim.keymap.set("n", "<leader>sl", ":Sf log list<CR>", { desc = "List debug logs" })
vim.keymap.set("n", "<leader>sR", ":Sf log resume<CR>", { desc = "Resume cached log list" })
vim.keymap.set("n", "<leader>sr", ":Sf test result<CR>", { desc = "Show test results" })
vim.keymap.set("n", "<leader>stn", ":Sf debug trace new<CR>", { desc = "Create trace flag" })
vim.keymap.set("n", "<leader>ss", ":Sf schema retrieve<CR>", { desc = "Retrieve metadata info" })
vim.keymap.set("n", "<leader>srm", ":Sf retrieve metadata<CR>", { desc = "Retrieve selected metadata" })
vim.keymap.set("n", "<leader>sa", ":Sf test action<CR>", { desc = "Show test actions" })
vim.keymap.set("n", "<leader>sdd", ":Sf retrieve diff<CR>", { desc = "Diff against server" })
vim.keymap.set("n", "<leader>srf", ":Sf retrieve refresh<CR>", { desc = "Refresh from server" })
vim.keymap.set("n", "<leader>sa", ":Sf apex execute file<CR>", { desc = "Execute current Apex" })
vim.keymap.set("n", "<leader>sn", ":Sf apex execute new<CR>", { desc = "New Apex script" })
vim.keymap.set("n", "<leader>sL", ":Sf apex execute list<CR>", { desc = "List Apex scripts" })
vim.keymap.set("n", "<leader>sq", ":Sf soql open<CR>", { desc = "Open SOQL query builder" })
vim.keymap.set("n", "<leader>sqq", ":Sf soql run<CR>", { desc = "Run raw SOQL query" })
vim.keymap.set("n", "<leader>sqr", ":Sf soql rerun<CR>", { desc = "Re-run last SOQL query" })
vim.keymap.set("n", "<leader>sqs", ":Sf soql resume<CR>", { desc = "Resume saved SOQL query" })
vim.keymap.set("n", "<leader>sqc", ":Sf soql clear<CR>", { desc = "Clear SOQL results" })
```

## 🎨 Features in Detail

### Metadata Deployment

- **Current File**: Deploy the file you're currently editing
- **Changed Files**: Deploy all files modified since last commit (automatic git-diff detection)
- **Selected Files**: Deploy specific files via selection
- **Force Mode**: Ignore source conflicts during deployment
- **Diagnostics**: Inline error display for deployment failures

### Apex Testing

- **Class-Level**: Run all tests in the current class
- **Method-Level**: Run a specific test method at cursor
- **Results Buffer**: Beautiful UI showing test results with stack traces
- **Code Coverage**: Visual indicators in the gutter showing covered/uncovered lines

### Debug Logs

- **Interactive Picker**: Browse logs with rich metadata
- **Preview Panel**: View log details before selection
- **Formatted Display**: User, timestamp, duration, size, status
- **Log Retrieval**: Select a log to download and open it in a buffer
- **Local Cache**: Previously downloaded logs open instantly from cache
- **Rich Per-Token Highlighting**: Tags, line numbers (`[1]`, `[EXTERNAL]`), and event names are colored distinctly for visual scanning — no sidecar files needed
- **Tree View**: Rendered log entries are indented to show the call hierarchy with entry/exit nesting
- **Resume**: Re-open the last log list from cache without re-fetching
- **Cleanup**: Remove cached logs and log list file

### Anonymous Apex Execution

- **Execute Buffer**: Run the current `.apex` file from any location — content is copied to a temp file under `.sf/sf.nvim/apex/`
- **Scripts Directory**: Files in the `scripts/` directory (configurable) run directly with no temp copy
- **Log Saving**: On success, the Apex debug log is saved to `logs/anonymous/<timestamp>.log`
- **Split View**: Log opens in a vertical split alongside the script (`execute file`) or in a new buffer (`list` selection)
- **Error Diagnostics**: Compile and runtime errors display as inline diagnostics on the source file
- **Script Picker**: Browse and select scripts from `scripts/` with live content preview via `Sf apex execute list`

### Coverage Display

When enabled (`:Sf coverage on`), coverage signs appear in the gutter:
- ● Green: Line is covered
- ● Red: Line is not covered

### Schema Management

- **Refresh**: Pull the latest metadata type index from the org via `Sf schema refresh`

### Metadata Retrieval

- **Select Items**: Multi-select individual metadata items via picker with preview details
- **Retrieve by Type**: Retrieve all items of a selected type in one command
- **Refresh Current Buffer**: `Sf retrieve refresh` detects the metadata type from the current buffer and retrieves the server version directly — no pickers, no extra steps
- **Diff Against Server**: `Sf retrieve diff` retrieves the server version to a temp directory, converts it to source format, then opens a dedicated tab with a scroll-synced 2-pane diff view (left: server, right: local). Uses an in-memory scratch buffer with `sf://` URI scheme to avoid LSP interference
- **Manifest Mode**: For >10 items, generates a `retrieve-manifest.xml` automatically for efficiency

### SOQL Query Builder

The SOQL Query Builder provides an interactive, schema-aware interface for constructing SOQL queries without memorizing field names or syntax.

**Schema-Aware Field Selection:** Browse all fields of your selected sObject with type annotations and labels. Pick multiple fields at once via the multi-select picker. Build parent-relationship dotted fields (e.g. `Owner.Name`, `MyLookup__r.Custom__c`) through a guided 2-step picker.

**Visual Query Builder Buffer:** A dedicated floating window with the `sfsoqlbuilder` filetype and custom syntax highlighting. Each query clause has its own section with live updates:

| Key | Action |
|-----|--------|
| `F` | Select fields (multi-select picker with schema data) |
| `R` | Add parent-relationship dotted field |
| `W` | Add WHERE condition (field → operator → value) |
| `B` | Add ORDER BY clause (field → direction) |
| `S` | Add child-relationship subquery (nested builder) |
| `A` | Compile and execute the query (results in new buffer) |
| `C` | Copy compiled SOQL to system clipboard |
| `L` / `O` | Set LIMIT / OFFSET |
| `X` / `x` | Clear all fields / Remove selected fields |
| `E` | Bulk-edit fields in a floating text buffer |
| `s` | Save query to disk for later resumption |
| `d` | Delete the item at cursor (field/WHERE/ORDER BY/subquery) |
| `e` | Re-open a subquery builder for editing |
| `o` | Switch to a different sObject |
| `rf` | Refresh schema describe data |
| `q` | Close the builder |

**Child Subqueries:** Add nested subqueries on child relationships. Each subquery opens its own builder window with independent field selection, WHERE conditions, ORDER BY, and LIMIT. Save with `<BS>` to return to the parent builder.

**Save and Resume:** Save any query with `s` — it writes a `.soql` file with auto-dedup naming to the cache directory. Later, `:Sf soql resume` opens a picker of saved files, parses the SOQL back into a full QueryState (fields, WHERE, ORDER BY, LIMIT, subqueries), and opens the builder ready to edit.

**Live SOQL Preview:** The bottom of the builder buffer shows the compiled SOQL, updating automatically as you modify fields, conditions, or clauses. Copy it to clipboard with `C` for use in other tools.

**Execution:** `A` compiles the query and runs it via `sf data query` with an optional result format (human-readable table, CSV, or JSON). Results open in a new buffer for inspection.

### 🐛 Apex Replay Debugger (DAP)

- sf.nvim integrates with nvim-dap to provide Apex Replay Debugger support. This allows you to debug Apex code by replaying debug logs through the Salesforce Apex Debugger adapter.

#### Prerequisites

- [nvim-dap](https://github.com/mfussenegger/nvim-dap) plugin installed
- [Apex Language Server](https://github.com/forcedotcom/salesforcedx-vscode/tree/develop/packages/salesforcedx-vscode-apex) (`apex_ls`) — the official Java-based LSP for Apex. Install via [Mason](https://github.com/williamboman/mason.nvim) (`:MasonInstall apex-language-server`) or as a standalone JAR.
- [Apex Replay Debugger adapter](https://github.com/forcedotcom/salesforcedx-vscode/tree/develop/packages/salesforcedx-apex-replay-debugger) — the `apexReplayDebug.js` adapter script from the official Salesforce Extension Pack for VS Code.

#### Adapter Setup

The debug adapter is part of the [salesforcedx-vscode](https://github.com/forcedotcom/salesforcedx-vscode) monorepo, written in TypeScript. It must be compiled to JavaScript before use:

```bash
# Clone the repo
git clone https://github.com/forcedotcom/salesforcedx-vscode.git
cd salesforcedx-vscode

# Install dependencies and compile
npm install
npm run compile

# The compiled adapter is at:
# packages/salesforcedx-apex-replay-debugger/out/src/adapter/apexReplayDebug.js
```

The `adapter_path` config option must point to the compiled `.js` file. Example:

```lua
adapter_path = "/home/user/salesforcedx-vscode/packages/salesforcedx-apex-replay-debugger/out/src/adapter/apexReplayDebug.js"
```

#### Configuration

```lua
require("sf").setup({
  dap = {
    adapter_path = "/path/to/apexReplayDebug.js",   -- REQUIRED: absolute path to the compiled adapter
    port = 4712,                                    -- DAP adapter port (default)
    lsp_client_name = "apex_ls",                    -- LSP client name (apex_ls or apex_ls_ts)
  },
  dap_log_dir = nil,                                -- defaults to {cache_path}/logs/dap
})
```

If `adapter_path` is left as `nil`, all DAP functionality is disabled (no-op).

#### Workflow

1. Set breakpoints in your Apex code using nvim-dap (`:DapToggleBreakpoint`)
2. Enable debug logging for your user in Salesforce (`:Sf debug trace new`)
3. Reproduce the issue in Salesforce (execute the Apex code you want to debug)
4. Run `:Sf log debug` — this resumes cached logs, downloads the selected one, copies it to the DAP log directory, and automatically launches the Apex Replay Debugger session
5. Step through your code with standard nvim-dap controls

#### Manual DAP Launch

If you already have a debug log in the DAP directory, you can launch the debugger manually:

```vim
:lua require("dap").continue()
```

The `Sf log debug` command does everything automatically: select log → copy → launch.

#### How It Works

1. **Breakpoint Synchronization**: Breakpoints set in your Apex files using `:DapToggleBreakpoint` are automatically resolved through the Apex LSP to ensure they map to the correct locations in the debug log.

2. **Faux Class Generation**: sf.nvim automatically generates faux (stub) Apex classes to provide proper LSP support during debugging. This mechanism:
   - Extracts class definitions from Apex code files and debug logs
   - Creates lightweight stub classes with method signatures
   - Stores them in a cache directory for quick LSP resolution
   - Significantly improves IDE features like hover information, code completion, and breakpoint matching
   - Reduces LSP initialization time by caching sObject metadata

3. **Log-to-Debugger Bridge**: The `:Sf log debug` command orchestrates the entire workflow:
   - Fetches cached debug logs or retrieves new ones from your org
   - Presents an interactive picker to select the desired log
   - Copies the selected log to the DAP directory (configured via `dap_log_dir`)
   - Automatically launches the Apex Replay Debugger session with proper configuration
   - Sets up the nvim-dap adapter to connect on the configured port (default: 4712)

4. **Code Stepping**: Once the debugger session starts, use standard nvim-dap controls:
   - `:DapContinue` — Resume execution
   - `:DapStepOver` — Step over the current line
   - `:DapStepInto` — Step into function calls
   - `:DapStepOut` — Step out of current function
   - `:DapTerminate` — End the debugging session
   - Variable inspector, watches, and the call stack are available via nvim-dap's UI

5. **Configuration Independence**: If `adapter_path` is not set, DAP functionality is completely disabled (no errors, no overhead). This allows you to use sf.nvim without nvim-dap if you don't need debugging.

#### Implementation Details

- **Async Coroutine-Based Architecture**: All DAP operations (log fetching, copying, adapter launching) run asynchronously using Lua coroutines to prevent blocking the editor
- **Error Handling**: Graceful fallback if the adapter fails to start or if the log format is incompatible
- **Extensible Design**: The DAP adapter integration is cleanly separated, making it easy to add support for other Salesforce debugging adapters in the future

## 🛠️ Development

PRs are welcome.

### Code Style

This project uses [stylua](https://github.com/JohnnyMorganz/StyLua) for Lua code formatting:
- 120 character line width
- 2-space indentation
- Unix line endings

See `stylua.toml` for complete configuration.

## 🐛 Troubleshooting

### SF CLI Not Found

**Error:** `Salesforce CLI (sf) not found in PATH`

**Solution:**
- Ensure SF CLI is installed: `npm install -g @salesforce/cli` and it is in PATH
- On Windows, use `sf_cli_path = "sf.cmd"` in your configuration

### No Default Org

**Error:** `No default org set`

**Solution:**
- Run `:Sf org set` to select a default org
- Or use SF CLI: `sf config set target-org YOUR_ORG_ALIAS`

### Debug Double Backslashes in Paths (Windows)

Fixed in latest version. Ensure you're using `PathUtils.normalize()` for all path operations.

### Enable Debug Logging

```lua
require("sf").setup({
  debug = true,
  debug_inspect = false,  -- Only log to file, no screen output
})
```

View logs: `:lua Snacks.debug.log()`

## 🤝 Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

1. Fork the repository
2. Create your feature branch (`git checkout -b feature/amazing-feature`)
3. Commit your changes (`git commit -m 'Add some amazing feature'`)
4. Push to the branch (`git push origin feature/amazing-feature`)
5. Open a Pull Request

## 📝 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## 🙏 Acknowledgments

- [Snacks.nvim](https://github.com/folke/snacks.nvim) - For beautiful UI components
- [Salesforce CLI](https://developer.salesforce.com/tools/salesforcecli) - The backbone of this plugin

## 📚 Related Projects

- [salesforce.nvim](https://github.com/jonathanmorris180/salesforce.nvim) - Alternative Salesforce plugin
- [sf.nvim](https://github.com/xixiaofinland/sf.nvim) - Another Salesforce plugin for Neovim

<div align="center">

Made with ❤️ for Salesforce developers using Neovim

[Report Bug](https://github.com/kamilgolis/sf.nvim/issues) · [Request Feature](https://github.com/kamilgolis/sf.nvim/issues)

</div>
