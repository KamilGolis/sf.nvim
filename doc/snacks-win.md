# Snacks.win — Complete Reference

`Snacks.win` is a window management layer over Neovim's `nvim_open_win`.
It handles floats and splits, backdrop, keymap binding, autocommand lifecycle,
auto-sizing, and buffer management.

A `Snacks.win` instance wraps one buffer + one window pair, tracks its
configuration, and provides methods for lifecycle, sizing, and customization.

---

## Quick Start

### 1. Simple float (default)

```lua
local win = Snacks.win({
  file = "README.md",
  width = 0.6,
  height = 0.6,
})
```

Creates a centered floating window at 60% of editor dimensions showing the
file. Closing with `q` (default keymap) wipes the scratch buffer.

### 2. Split at bottom

```lua
Snacks.win({
  position = "bottom",
  height = 0.3,
  width = 0.8,
  text = "Hello from a split!",
})
```

Opens a window at the bottom of the editor, 30% height. Splits are real Neovim
windows (not floats) — they participate in split navigation (`<C-w>h/j/k/l`).

### 3. Scratch buffer with custom keys and title

```lua
local win = Snacks.win({
  text = { "Line one", "Line two", "Line three" },
  title = " Scratch ",
  border = "rounded",
  keys = {
    q = "close",
    d = function(self)
      vim.api.nvim_buf_set_lines(self.buf, 0, -1, false, { "replaced" })
    end,
    ["?"] = "toggle_help",
  },
  footer_keys = true,
  enter = true,
})
```

### 4. Reusable wrapper function

```lua
local function show_debug_log(log_lines)
  return Snacks.win({
    text = log_lines,
    title = " Debug Log ",
    width = 0.8,
    height = 0.5,
    border = "rounded",
    ft = "log",
    enter = true,
    keys = {
      q = "close",
      s = "toggle_help",
    },
    on_win = function(self)
      vim.bo[self.buf].modifiable = false
    end,
  })
end
```

---

## Configuration Reference

All config fields. The table merges user options over base defaults, then
style-appropriate presets (see "Styles" below).

| Field | Type | Default | Description |
|---|---|---|---|
| `show` | `boolean` | `true` | Open the window immediately in the constructor. Set `false` to configure before calling `:show()`. |
| `position` | string | `"float"` | `"float"` — floating window. `"bottom"` / `"top"` / `"left"` / `"right"` — split. `"current"` — uses the current Neovim window. |
| `relative` | string | `"editor"` | `"editor"` — relative to editor area. `"win"` — relative to a specific window (`opts.win`). `"cursor"` — relative to cursor position. |
| `style` | `string` | — | Name of a style defined in `Snacks.config.styles[name]` to merge as a base layer. The style's options are resolved first, then user options overwrite. |
| `minimal` | `boolean` | `true` | Applies the `"minimal"` style: removes line numbers, signcolumn, cursorline, foldcolumn, colorcolumn, statuscolumn, winbar, wraps, spell, and listchars. Keeps UI clean. |
| `height` | `number \| fun(self): number` | `0.9` | `< 1` = fraction of parent. `0` = fill parent. `≥ 1` = absolute rows. Can be a function returning dynamic height. |
| `width` | `number \| fun(self): number` | `0.9` | Same convention as height. |
| `min_height` | `number` | — | Minimum height in rows (after border). Clamped to `≥ 1`. |
| `max_height` | `number` | — | Maximum height. Clamped to parent height. |
| `min_width` | `number` | — | Minimum width in columns. |
| `max_width` | `number` | — | Maximum width. Clamped to parent width. |
| `row` | `number \| fun(self): number` | — | `< 0` = offset from bottom. `< 1` and `> 0` = relative position. `nil` = centered. Can be a function. |
| `col` | `number \| fun(self): number` | — | Same convention as row. |
| `border` | see below | — | See Border section. |
| `backdrop` | `number \| false \| snacks.win.Backdrop` | `60` (float) / `false` (split) | Semi-transparent overlay behind floated windows. Number = blend percentage (0=opaque, 100=invisible). `false` = no backdrop. A table lets you set `bg`, `blend`, and `transparent`. |
| `buf` | `number` | — | Use an existing buffer by number. The window won't manage its lifetime. |
| `file` | `string` | — | File path to load into a new buffer. The buffer is set readonly, modifiable=false. |
| `text` | `string \| string[] \| fun(): (string[] \| string)` | — | Initial text content for scratch buffers. Can be a function returning content dynamically when `:show()` is called. |
| `enter` | `boolean` | `false` | Enter the window after opening (`nvim_set_current_win`). |
| `focusable` | `boolean` | `true` | When `false`, the window is skipped by `<C-w>w`, cannot be entered, and `enter` is forced to `false`. |
| `fixbuf` | `boolean` | `true` | When `true`, if another buffer is opened in this window, it swaps the buffer back and opens the intruder in a main window instead. |
| `ft` | `string` | — | Filetype to set. Won't override an existing filetype on the buffer (unlike `scratch_ft`). |
| `scratch_ft` | `string` | `"snacks_win"` | Filetype used for scratch buffers (when no explicit `bo.filetype` is set). |
| `wo` | `vim.wo` | (see winhighlight) | Window-local options. Default sets custom highlight groups on all Snacks windows (Normal, NormalNC, WinBar, Title, Footer, WinSeparator). |
| `bo` | `vim.bo` | `{}` | Buffer-local options. |
| `b` | `table<string, any>` | — | Buffer-local variables (`vim.b[buf][k] = v`). |
| `w` | `table<string, any>` | — | Window-local variables (`vim.w[win][k] = v`). |
| `keys` | `table` | `{ q = "close" }` | Key mappings. See Keys section. |
| `actions` | `table<string, Action.spec>` | — | Named actions that keymaps and `:execute()` can invoke. |
| `footer_keys` | `boolean \| string[]` | `false` | Show a footer row listing keymaps. `true` = all keys. `string[]` = only those keymaps (matched by normalized lhs). Generated from registered `keys`. |
| `resize` | `boolean` | `true` | Automatically recalculate dimensions on `VimResized`. |
| `stack` | `boolean` | — | When `true`, split windows with the same position are stacked perpendicularly instead of creating new splits. Useful for terminals. |
| `zindex` | `number` | `50` (float) / `1` (split) | Float stacking order. Higher = on top. |
| `win` | `number` | — | Parent window (used when `relative = "win"` or for split positioning). |

### Border values

| Value | Result |
|---|---|
| `true` | Uses Neovim's `winborder` option, or `"rounded"` fallback |
| `"none"` / `false` | No border |
| `"rounded"` / `"single"` / `"double"` / `"solid"` / `"shadow"` / `"bold"` | Standard Neovim border styles |
| `"top"` | Only a top line |
| `"bottom"` | Only a bottom line |
| `"left"` / `"right"` | Single side |
| `"top_bottom"` | Top and bottom lines only |
| `"hpad"` | Horizontal padding only (space left/right) |
| `"vpad"` | Vertical padding only (space top/bottom) |
| `string[]` | Custom Neovim border array (8 chars clockwise from top-left) |

Border adds 2 rows and 2 columns to the window dimensions (1 each side).

### Sizing math (from `win:dim()`)

```
parent = parent_size()  -- editor or parent window
ret.height = size(height, parent.height, border.top + border.bottom)
ret.width  = size(width,  parent.width,  border.left + border.right)
ret.row    = pos(row,    ret.height, parent.height, border.top, border.bottom)
ret.col    = pos(col,    ret.width,  parent.width,  border.left, border.right)
```

Where `size(s, parent, border_offset)`:
- `s == 0` → `parent - border_offset` (fill)
- `0 < s < 1` → `floor(parent * s) - border_offset` (fraction)
- `s ≥ 1` → `s` (absolute)

Where `pos(p, size, parent, ...)`:
- `p == nil` → center: `floor((parent - size) / 2) - border_from`
- `p < 0` → offset from bottom: `parent - size + p - border_from - border_to`
- `0 < p < 1` → fraction from top: `floor(parent * p) + border_from`
- `p ≥ 1` → absolute

---

## Styles

Styles are reusable preset configs stored in `Snacks.config.styles`.
The constructor resolves them via `Snacks.win.resolve({style} or {position})`.

### Built-in styles

```lua
-- float — default for position = "float"
Snacks.config.style("float", {
  position = "float",
  backdrop = 60,
  height = 0.9,
  width = 0.9,
  zindex = 50,
})

-- split — default for position != "float"
Snacks.config.style("split", {
  position = "bottom",
  height = 0.4,
  width = 0.4,
})

-- minimal — applied when minimal = true
Snacks.config.style("minimal", {
  wo = {
    cursorcolumn = false,
    cursorline = false,
    cursorlineopt = "both",
    colorcolumn = "",
    fillchars = "eob: ,lastline:…",
    foldcolumn = "0",
    list = false,
    listchars = "extends:…,tab:  ",
    number = false,
    relativenumber = false,
    signcolumn = "no",
    spell = false,
    winbar = "",
    statuscolumn = "",
    wrap = false,
    sidescrolloff = 0,
  },
})

-- help — used by :toggle_help()
Snacks.config.style("help", {
  position = "float",
  backdrop = false,
  border = "top",
  row = -1,
  width = 0,
  height = 0.3,
})
```

### Defining a custom style

```lua
-- In Snacks opts:
opts = {
  styles = {
    my_sidebar = {
      position = "left",
      width = 40,
      height = 0,  -- full height
      border = "none",
      minimal = true,
    },
  },
}

-- Usage:
Snacks.win({ style = "my_sidebar", text = "Sidebar content" })
```

Styles compose: if your config has a `style` field pointing to another style,
it resolves recursively (with cycle protection).

### Resolution order

1. Base defaults (`snacks.win` defaults table)
2. User `opts` — what you pass to `Snacks.win.new(opts)`
3. If `minimal = true`: merge with `"minimal"` style
4. If `position = "float"`: merge with `"float"` style, else `"split"` style
5. If `style = "name"`: merge with `Snacks.config.styles["name"]` (recursive through `style` chains)

Later layers override earlier ones via `vim.tbl_deep_extend("force", ...)`.

---

## Types

### `snacks.win.Keys`

```lua
---@class snacks.win.Keys: vim.api.keyset.keymap
---@field [1]? string     -- key sequence (lhs), e.g. "q", "<leader>f"
---@field [2]? string|string[]|fun(self: snacks.win): string?
---   ^ rhs: action name(s), or a callback receiving the win instance
---@field mode? string|string[]  -- default "n"
```

A keymap entry in the `keys` config table. Each entry's key in the config
table becomes the lhs automatically — the `[1]` field overrides it.

**Shorthand forms:**
- `q = "close"` — expands to `{ "q", "close", desc = "close" }`
- `d = function(self) ... end` — expands to `{ "d", function }`
- `q = { "<esc>", "close", mode = "i" }` — explicit spec with mode

The rhs (`[2]`) can be:
- A **string**: an action name (built-in like `"close"`, `"hide"`, `"toggle_help"`, or custom from `opts.actions`)
- A **string array**: chain of action names executed in sequence
- A **function**: `fun(self: snacks.win): boolean|string?` — called with the window instance. Return `true` to stop chain, or a string to return as key result.

**Deduplication:** The same normalized lhs + mode pair registered twice
produces a warning via `Snacks.notify.warn`.

**Key priority:** Keys are sorted in reverse alphanumeric order so
`<nowait>` mappings match before their longer prefixes.

### `snacks.win.Event`

```lua
---@class snacks.win.Event: vim.api.keyset.create_autocmd
---@field buf? true        -- scope to the instance's buffer
---@field win? true         -- scope to the instance's window
---@field callback? fun(self: snacks.win, ev): boolean?
```

Used with `win:on(event, cb, event_opts)`. The `buf` and `win` fields are
convenience flags: `buf = true` sets `buffer = self.buf`, `win = true` sets
`pattern = tostring(self.win)` (for WinClosed/WinResized).

The callback receives `(self, ev)` where `ev` is the standard autocmd args
table. Return `true` to delete the autocmd (one-shot).

Autocommands are registered under the window's augroup
(`"snacks_win_<id>"`) and are automatically cleaned up on close.

### `snacks.win.Backdrop`

```lua
---@class snacks.win.Backdrop
---@field bg? string            -- background color, default "#000000"
---@field blend? number         -- blend percentage, default 60
---@field transparent? boolean  -- default true — blend with actual bg
---@field win? snacks.win.Config -- overrides for the backdrop window
```

The backdrop is a full-editor floating window at `zindex - 1` behind the main
window. It is only created for floating windows.

**When backdrop is skipped** (no dimming overlay):
- Terminal doesn't support `termguicolors`
- `blend == 100` (completely transparent)
- User has transparent background (`Snacks.util.is_transparent()`)
- Window is not floating

### `snacks.win.Dim`

```lua
---@class snacks.win.Dim
---@field width number    -- inner width, without borders
---@field height number   -- inner height, without borders
---@field row number      -- 0-indexed row position
---@field col number      -- 0-indexed column position
---@field border? boolean -- whether border is present
```

Returned by `win:dim()` and `win:size()`. The `Dim` from `:dim()` is the
*inner* content area; `:size()` adds border.

### `snacks.win.Action`

```lua
---@alias snacks.win.Action.fn fun(self: snacks.win): (boolean|string?)
---@alias snacks.win.Action.spec snacks.win.Action|snacks.win.Action.fn
---@class snacks.win.Action
---@field action snacks.win.Action.fn
---@field desc? string
```

Actions are named behavior blocks registered via `opts.actions`. A keymap can
reference them by name. Actions chain: `{ "close", "cleanup" }` calls both in
order.

The action function receives `self`. Return `true` to stop the chain,
`"string"` to pass through as key result (for `expr = true` keymaps).

Two resolution paths:
1. Lookup `self.opts.actions[name]` — custom action
2. Fallback `self[name]` — method on the window instance

---

## Instance API

### `win:show()`

```lua
win:show() -> self
```

Opens or refreshes the window. If already open, calls `:update()`. Otherwise:
creates augroup, opens buffer, applies settings, opens the Neovim window,
applies window options, calls `on_win`, sets up syntax, registers events,
applies keymaps (`:map()`), and creates backdrop (`:drop()`).

Idempotent — safe to call multiple times on an already-open window.

### `win:close(opts)`

```lua
win:close(opts?) -> nil
--- opts.buf? boolean  -- default true: also wipe scratch buffer
```

Closes the window and optionally wipes the scratch buffer (buffers loaded via
`file` or `buf` are not wiped). If the window is the last one on the tab,
creates a `:vsplit` first. Retries on `E11` (command window open) and `E565`
(text lock) with backoff.

`win.closed` is set to `true`; `on_close` callback fires.

### `win:hide()`

```lua
win:hide() -> self
```

Close the window but keep the buffer (passes `{ buf = false }` to `:close()`).
Useful for toggle patterns where you want to preserve content.

### `win:toggle()`

```lua
win:toggle() -> self
```

If the window is valid, calls `:hide()`. Otherwise calls `:show()`.
Returns `self` for chaining.

### `win:destroy()`

```lua
win:destroy() -> nil
```

Calls `:close()` (no error on invalid state) and clears events, keys, and
meta tables. Full teardown.

### `win:focus()`

```lua
win:focus() -> nil
```

Sets the current window to this one. Safe to call on an invalid window
(no-op).

### `win:valid()`

```lua
win:valid() -> boolean
```

Returns `true` when `win`, `buf` exist, and the window still shows the
expected buffer (`nvim_win_get_buf(win) == buf`).

### `win:win_valid()`

```lua
win:win_valid() -> boolean
```

Returns `true` when `self.win` is a valid Neovim window handle.

### `win:buf_valid()`

```lua
win:buf_valid() -> boolean
```

Returns `true` when `self.buf` is a valid Neovim buffer handle.

### `win:is_floating()`

```lua
win:is_floating() -> boolean
```

Returns `true` if the window is a float (checks `zindex` in win_config).
Also requires the window to be valid.

### `win:on_current_tab()`

```lua
win:on_current_tab() -> boolean
```

Returns `true` if the window's tabpage is the current tabpage.

### `win:update()`

```lua
win:update() -> nil
```

Refreshes buffer options, window options, and (for floats) window config
(position, size, border, title). Called automatically on `VimResized`.

Safe to call on invalid windows (no-op because `:valid()` exits early).

### `win:set_title(title, pos)`

```lua
win:set_title(title, pos?) -> nil
---@param title string|{[1]:string, [2]:string}[]
---@param pos? "center"|"left"|"right"
```

Changes the window title dynamically. Calls `nvim_win_set_config` with the
new title. No-op if the window has no border or the relative window is
invalid. Skips update if title hasn't changed (deep-equal check).

The `title` can be a string or a highlight-group array (standard Neovim
title format `{ { "text", "Group" }, ... }`).

### `win:set_buf(buf)`

```lua
win:set_buf(buf) -> nil
---@param buf number
```

Replaces the buffer in the window. Asserts that the window is valid.
Applies window options after the swap.

### `win:text(from, to)`

```lua
win:text(from?, to?) -> string
--- from? number  1-indexed, inclusive
--- to? number    1-indexed, inclusive
```

Returns buffer content as a single string (joined with `\n`).
If called without args, returns the entire buffer.

### `win:lines(from, to)`

```lua
win:lines(from?, to?) -> string[]
```

Same as `text()` but returns an array of lines.

### `win:line(line)`

```lua
win:line(line) -> string
```

Returns a single line from the buffer (1-indexed). Empty string for
out-of-range.

### `win:scratch()`

```lua
win:scratch() -> nil
```

Creates a new scratch buffer (or reuses an existing one) and sets it as the
window's buffer. Sets filetype to `opts.scratch_ft` or `"snacks_win"`, loads
text from `opts.text` if present.

### `win:add_padding()`

```lua
win:add_padding() -> nil
```

Modifies window options to add an EOL space character (via `listchars`),
enables `list`, and sets `statuscolumn` to a space. Useful when you want
space at the end of each line for visual consistency.

### `win:on(event, cb, opts?)`

```lua
win:on(event, cb, opts?) -> nil
---@param event string|string[]
---@param cb fun(self: snacks.win, ev): boolean?
---@param opts? snacks.win.Event
```

Register an autocommand scoped to this window. Supports `buf = true` and
`win = true` convenience flags (see `snacks.win.Event`).

Autocommands are registered under the window's augroup and auto-cleaned on
close. If the window is not yet open, events are queued and registered when
`:show()` runs.

### `win:action(actions)`

```lua
win:action(actions) -> (fun(): boolean|string?, string)
---@param actions string|string[]
---@return fun() action_fn, string description
```

Resolves action name(s) to a callable function and a human-readable
description (underscores replaced with spaces). The returned function chains
multiple actions: stops early if any returns `true`, returns `nil` on
success, or passes a `string` result (for `expr` keymaps).

Resolution: looks up `self.opts.actions[name]` first, then `self[name]`
(method on the instance), then returns the name as-is (for passthrough to
vim's keymap system).

### `win:execute(actions)`

```lua
win:execute(actions) -> ?
```

Shortcut for `self:action(actions)()`.

### `win:toggle_help(opts?)`

```lua
win:toggle_help(opts?) -> nil
---@param opts? { col_width?: number, key_width?: number, win?: snacks.win.Config }
```

Toggles a help window overlaying the current window showing all registered
keymaps (including those from the buffer, not just `self.keys`). Uses the
`"help"` style by default.

### `win:redraw()`

```lua
win:redraw() -> nil
```

Calls `nvim__redraw` (or `:redraw` fallback) for this window.

### `win:scroll(up?)`

```lua
win:scroll(up?) -> nil
```

Scrolls the window content by one scroll unit. `true` = up (`<C-y>`),
`false`/`nil` = down (`<C-e>`).

### `win:hscroll(left?)`

```lua
win:hscroll(left?) -> nil
```

Horizontal scroll (`zh`/`zl`). `true` = left.

### `win:border()`

```lua
win:border() -> string|string[]|nil
```

Resolves and returns the actual border value. `true` resolves to
`vim.o.winborder` or `"rounded"`. Returns `nil` for `"none"`/`false`/empty.

### `win:has_border()`

```lua
win:has_border() -> boolean
```

Returns `true` if `win:border()` is non-nil.

### `win:border_size()`

```lua
win:border_size() -> { top: number, right: number, bottom: number, left: number }
```

Returns the border thickness in characters per side (0 or 1). Calculated by
checking which of the 8 border array slots are non-empty.

### `win:border_text_width()`

```lua
win:border_text_width() -> number
```

Returns the display width of the longest title or footer string. Useful for
layout calculations.

### `win:dim(parent?)`

```lua
win:dim(parent?) -> snacks.win.Dim
---@param parent? snacks.win.Dim
```

Calculates the inner content dimensions based on the current config.
Accepts an optional parent size override; defaults to `:parent_size()`.

Returns a `Dim` with `height`, `width`, `row`, `col`, and `border` fields.
The row/col are 0-indexed positions for `nvim_open_win`.

### `win:size()`

```lua
win:size() -> { height: number, width: number }
```

Returns the total window size including border (adds 2 to both dimensions
when border is active). Use this when you need the outer dimensions.

### `win:parent_size()`

```lua
win:parent_size() -> { height: number, width: number }
```

Returns the size of the parent container. For `relative = "win"`, returns
the parent window's dimensions. Otherwise returns `vim.o.lines` ×
`vim.o.columns`.

### `win:fixbuf()`

```lua
win:fixbuf() -> boolean|nil
```

Called automatically on `BufWinEnter`. If another buffer was opened in this
window, it tries to swap it into a main window, or closes the snacks window.
Returns `true` to delete the autocmd if the window is gone.

When `fixbuf = false`, updates `self.buf` to whatever buffer is currently in
the window.

### `win:map()`

```lua
win:map() -> nil
```

Applies all keymaps from `self.keys` to the buffer via `vim.keymap.set`.
Maps are set with `buffer = self.buf`, `nowait = true`.

Action strings are resolved through `:action()`. Function rhs are wrapped to
receive `self`.

---

## Module API

### `Snacks.win(opts)`

```lua
Snacks.win(opts?) -> snacks.win
-- shortcut for Snacks.win.new(opts)
```

The module is callable: `Snacks.win({...})` is identical to
`Snacks.win.new({...})`.

### `Snacks.win.new(opts)`

```lua
Snacks.win.new(opts?) -> snacks.win
```

Full constructor. Resolves config (styles, position, minimal), parses all
keymaps, registers autocommands for close/resize, and opens the window
immediately unless `show = false`.

### `Snacks.win.resolve(...)`

```lua
Snacks.win.resolve(...) -> snacks.win.Config
--@param ... snacks.win.Config|string|{}
```

Resolves one or more configs/styles by merging:
1. Each argument can be a config table or a style name string
2. Style name strings are replaced with `Snacks.config.styles[name]`
3. If a resolved table has a `style` field, that style is included recursively
4. All configs are merged with `vim.tbl_deep_extend("force", ...)`
5. The `style` field is stripped from the result

### `Snacks.win.zindex(opts)`

```lua
Snacks.win.zindex(opts?) -> number
---@param opts? { zindex?: number, tab?: number|boolean, all?: boolean, max?: number }
---@overload fun(zindex: number): number
```

Calculates the next available zindex, starting from `opts.zindex` (default
50). Scans windows on the tab (or all windows when `tab = false`), then
bumps past any existing zindex in the range up to `opts.max` (default 100).
Skips very high zindex windows (notifications, completion) via the `max`
cap. A snacks_win marker check means by default it only counts Snacks-owned
windows (`opts.all = true` counts everything).

### `Snacks.win.is_border(border)`

```lua
Snacks.win.is_border(border) -> boolean
```

Static check: returns `true` if the border value is non-nil, non-empty, and
not `"none"`.

---

## Patterns & Recipes

### Input-style window

```lua
Snacks.win({
  position = "float",
  border = true,
  height = 1,
  width = 60,
  enter = true,
  noautocmd = true,
  bo = { buftype = "prompt", filetype = "snacks_input" },
  wo = { cursorline = false },
  keys = {
    q = "cancel",  -- custom action
    ["<cr>"] = "confirm",
  },
  actions = {
    cancel = function(self)
      self:close()
    end,
    confirm = function(self)
      local text = vim.fn.getline(".")
      self:close()
      -- use text
    end,
  },
})
```

### Lazy show (create config without opening)

```lua
local win = Snacks.win.new({
  show = false,
  title = " Deferred ",
  text = { "Created now, shown later" },
})

-- Later:
win:show()
```

### Toggle with state

```lua
local my_panel = nil

function toggle_panel()
  if my_panel and my_panel:valid() then
    my_panel:close()
    my_panel = nil
  else
    my_panel = Snacks.win({
      position = "right",
      width = 40,
      height = 0,
      title = " Panel ",
      border = "rounded",
      enter = true,
      on_close = function()
        my_panel = nil
      end,
    })
  end
end
```

### Custom scrollable detail view

```lua
local function show_detail(lines, title)
  local win = Snacks.win({
    text = lines,
    title = " " .. (title or "Detail") .. " ",
    width = 0.6,
    height = 0.4,
    border = "rounded",
    ft = "markdown",
    enter = true,
    keys = {
      q = "close",
      j = function(self)
        self:scroll()
      end,
      k = function(self)
        self:scroll(true)
      end,
      ["?"] = "toggle_help",
    },
    on_win = function(self)
      vim.bo[self.buf].modifiable = false
    end,
  })
  return win
end
```

### Backdrop customization

```lua
-- Darker backdrop (less transparent)
Snacks.win({
  title = " Important ",
  backdrop = 20,  -- 20% blend = darker
})

-- No backdrop
Snacks.win({
  title = " Lightweight ",
  backdrop = false,
})

-- Custom backdrop bg
Snacks.win({
  title = " Custom tint ",
  backdrop = { bg = "#1a1a2e", blend = 40, transparent = false },
})
```

### Window with lifecycle callbacks

```lua
Snacks.win({
  text = "Processing...",
  on_buf = function(self)
    print("Buffer opened:", self.buf)
  end,
  on_win = function(self)
    vim.bo[self.buf].modifiable = false
    vim.bo[self.buf].filetype = "log"
  end,
  on_close = function(self)
    print("Window closed:", self.id)
    cleanup_resources()
  end,
})
```

### Using custom actions in keymaps

```lua
Snacks.win({
  text = { "Action demo" },
  actions = {
    greet = {
      action = function(self)
        vim.notify("Hello from win " .. self.id)
      end,
      desc = "Say hello",
    },
    double_greet = function(self)
      vim.notify("Hello again!")
    end,
  },
  keys = {
    g = "greet",
    d = { "greet", "double_greet", desc = "Greet twice" },
  },
  footer_keys = true,
})
```

### Help window with key visualization

```lua
Snacks.win({
  text = { "Press ? to see all keymaps" },
  keys = {
    q = "close",
    ["?"] = "toggle_help",
    ["<cr>"] = "close",
    d = function(self) vim.notify("action!") end,
  },
  footer_keys = { "q", "?", "<cr>", "d" },
  footer_pos = "left",
})
```

Calling `toggle_help` shows an overlay listing every registered keymap:

```
      q ➜ close                 ? ➜ toggle_help
  <cr> ➜ close                  d ➜ action!
```

---

## Highlight groups

Snacks.win registers these highlight groups (all prefixed with `Snacks`):

| Group | Links to | Used for |
|---|---|---|
| `SnacksNormal` | `NormalFloat` | Window body |
| `SnacksNormalNC` | `NormalFloat` | Non-current window body |
| `SnacksTitle` | `FloatTitle` | Border title |
| `SnacksFooter` | `FloatFooter` | Footer area |
| `SnacksWinBar` | `Title` | Winbar |
| `SnacksWinBarNC` | `SnacksWinBar` | Non-current winbar |
| `SnacksWinSeparator` | `WinSeparator` | Window separator |
| `SnacksBackdrop` | — | Backdrop background (`bg = "#000000"`) |
| `SnacksWinKey` | `Keyword` | Help: key name |
| `SnacksWinKeySep` | `NonText` | Help: separator `➜` |
| `SnacksWinKeyDesc` | `Function` | Help: key description |
| `SnacksFooterKey` | `DiagnosticVirtualTextInfo` | Footer: key name |
| `SnacksFooterDesc` | `DiagnosticInfo` | Footer: key description |

