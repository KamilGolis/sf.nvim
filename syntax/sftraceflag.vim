" Syntax highlighting for sftraceflag buffers (Trace Flag Editor)
" @license MIT

if exists("b:current_syntax")
  finish
endif

" ── Dividers ────────────────────────────────────────────
syntax match SfTraceFlagDivider /─\{2,}/

" ── Title ───────────────────────────────────────────────
syntax match SfTraceFlagTitle /\cTrace Flag —/

" ── Section headers ─────────────────────────────────────
syntax match SfTraceFlagSection /\(Traced Entity\|Start Date\|Expiration Date\|Debug Level\)/

" ── Bullet values ───────────────────────────────────────
syntax match SfTraceFlagValue /•\s*\zs.*$/

" ── Keybind hints ───────────────────────────────────────
syntax match SfTraceFlagKeybind /\[<CR>\].*\[<C-s>\]/

" ── Highlight links ─────────────────────────────────────
highlight default link SfTraceFlagDivider LineNr
highlight default link SfTraceFlagTitle Title
highlight default link SfTraceFlagSection Statement
highlight default link SfTraceFlagValue String
highlight default link SfTraceFlagKeybind Comment

let b:current_syntax = "sftraceflag"
