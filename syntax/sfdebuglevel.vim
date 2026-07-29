" Syntax highlighting for sfdebuglevel buffers (Debug Level Editor)
" @license MIT

if exists("b:current_syntax")
  finish
endif

" ── Dividers ────────────────────────────────────────────
syntax match SfDebugLevelDivider /─\{2,}/

" ── Title ───────────────────────────────────────────────
syntax match SfDebugLevelTitle /\cDebug Level —/

" ── Section headers ─────────────────────────────────────
syntax match SfDebugLevelSection /\(Log Level Name\|Log Categories\)/

" ── Field labels ────────────────────────────────────────
syntax match SfDebugLevelLabel /^\s\{3}\w.*$/

" ── Bullet values ───────────────────────────────────────
syntax match SfDebugLevelValue /•\s*\zs.*$/

" ── Read-only field ─────────────────────────────────────
syntax match SfDebugLevelReadOnly /(read-only)/

" ── Keybind hints ───────────────────────────────────────
syntax match SfDebugLevelKeybind /\[<CR>\].*\[<C-s>\]/

" ── Highlight links ─────────────────────────────────────
highlight default link SfDebugLevelDivider LineNr
highlight default link SfDebugLevelTitle Title
highlight default link SfDebugLevelSection Statement
highlight default link SfDebugLevelLabel Identifier
highlight default link SfDebugLevelValue String
highlight default link SfDebugLevelReadOnly Comment
highlight default link SfDebugLevelKeybind Comment

let b:current_syntax = "sfdebuglevel"
