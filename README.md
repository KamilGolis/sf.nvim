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
- 📊 **Code Coverage** - Visual coverage indicators with detailed statistics
- 🔌 **Org Management** - Easy switching between Salesforce orgs
- 📝 **Debug Logs** - List and view debug logs with rich UI
- 🔍 **Diagnostics** - Inline error display for deployment failures
- 💾 **Cross-platform** - Works on Windows, macOS, and Linux
- ⚡ **Fast** - Asynchronous operations with progress indicators
- 🎨 **Rich UI** - Beautiful pickers and result buffers powered by Snacks.nvim

## 📋 Requirements

- [Neovim](https://neovim.io/) >= 0.9.0
- [Salesforce CLI](https://developer.salesforce.com/tools/salesforcecli) (`sf` command)
- [Snacks.nvim](https://github.com/folke/snacks.nvim) - For UI components
- [plenary.nvim](https://github.com/nvim-lua/plenary.nvim) - For async operations
- **Optional:** [sgd plugin](https://github.com/scolladon/sfdx-git-delta) - For delta deployments of changed files

## 📦 Installation

### Using [lazy.nvim](https://github.com/folke/lazy.nvim)

```lua
{
  "kamilgolis/sf.nvim",
  dependencies = {
    "folke/snacks.nvim",
    "nvim-lua/plenary.nvim",
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
    "nvim-lua/plenary.nvim",
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
  
  -- Cache directory for storing deployment/test results
  cache_path = "./.sf/sf.nvim",
  
  -- Debug mode - enables logging to file
  debug = false,
  
  -- Show debug output on screen (requires debug = true)
  -- When false, only logs to file
  debug_inspect = false,
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
| `delta_dir` | `string` | `"delta"` | Directory for delta package |
| `debug` | `boolean` | `false` | Enable debug logging to file |
| `debug_inspect` | `boolean` | `false` | Show debug output on screen |

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

## 🎮 Commands

All commands are available under the `:Sf` command with subcommands:

### Org Management

```vim
:Sf org set          " Select and set default org via picker
```

### Deployment

```vim
:Sf deploy metadata         " Deploy current file
:Sf deploy metadata force   " Deploy current file (ignore conflicts)
:Sf deploy changed          " Deploy changed files (requires sgd plugin)
:Sf deploy changed force    " Deploy changed files (ignore conflicts)
:Sf deploy selected         " Deploy selected files (requires sgd plugin)
:Sf deploy selected force   " Deploy selected files (ignore conflicts)
```

### Testing

```vim
:Sf test class    " Run all tests in current test class
:Sf test method   " Run test method at cursor position
:Sf test result   " Show last test results
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
:Sf log list    " List debug logs with interactive picker
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
vim.keymap.set("n", "<leader>sd", ":Sf deploy metadata<CR>", { desc = "Deploy current file" })
vim.keymap.set("n", "<leader>sD", ":Sf deploy changed<CR>", { desc = "Deploy changed files" })
vim.keymap.set("n", "<leader>st", ":Sf test class<CR>", { desc = "Run test class" })
vim.keymap.set("n", "<leader>sm", ":Sf test method<CR>", { desc = "Run test method" })
vim.keymap.set("n", "<leader>sc", ":Sf coverage class<CR>", { desc = "Run coverage" })
vim.keymap.set("n", "<leader>sC", ":Sf coverage on<CR>", { desc = "Toggle coverage display" })
vim.keymap.set("n", "<leader>sl", ":Sf log list<CR>", { desc = "List debug logs" })
vim.keymap.set("n", "<leader>sr", ":Sf test result<CR>", { desc = "Show test results" })
```

## 🏗️ Architecture

### Project Structure

```
sf.nvim/
├── lua/
│   └── sf/
│       ├── core/          # Core utilities
│       │   ├── diagnostics.lua
│       │   ├── indexes.lua
│       │   ├── job_utils.lua
│       │   ├── path_utils.lua
│       │   ├── process.lua
│       │   └── utils.lua
│       ├── deploy/        # Deployment functionality
│       │   ├── metadata.lua
│       │   └── utils.lua
│       ├── test/          # Testing functionality
│       │   ├── coverage.lua
│       │   ├── results_buffer.lua
│       │   └── runner.lua
│       ├── org/           # Org management
│       │   ├── connect.lua
│       │   └── utils.lua
│       ├── log/           # Debug log management
│       │   └── list.lua
│       ├── config.lua     # Configuration
│       ├── const.lua      # Constants
│       └── init.lua       # Plugin entry point
└── plugin/
    └── sf.lua             # Plugin commands and autocommands
```

### Key Modules

- **core/**: Shared utilities (path handling, job management, diagnostics)
- **deploy/**: Metadata deployment orchestration
- **test/**: Apex test execution and coverage display
- **org/**: Org connection management
- **log/**: Debug log listing and viewing

## 🎨 Features in Detail

### Metadata Deployment

- **Current File**: Deploy the file you're currently editing
- **Changed Files**: Deploy all files modified since last commit (requires sgd)
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

### Coverage Display

When enabled (`:Sf coverage on`), coverage signs appear in the gutter:
- ● Green: Line is covered
- ● Red: Line is not covered

## 🛠️ Development

### Running Tests

```bash
# Check code style
stylua --check .

# Format code
stylua .
```

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
- Ensure SF CLI is installed: `npm install -g @salesforce/cli`
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
- [plenary.nvim](https://github.com/nvim-lua/plenary.nvim) - For async operations
- [Salesforce CLI](https://developer.salesforce.com/tools/salesforcecli) - The backbone of this plugin

## 📚 Related Projects

- [salesforce.nvim](https://github.com/xixiaofinland/salesforce.nvim) - Alternative Salesforce plugin
- [sgd (sfdx-git-delta)](https://github.com/scolladon/sfdx-git-delta) - Delta deployment support

---

<div align="center">

Made with ❤️ for Salesforce developers using Neovim

[Report Bug](https://github.com/kamilgolis/sf.nvim/issues) · [Request Feature](https://github.com/kamilgolis/sf.nvim/issues)

</div>
