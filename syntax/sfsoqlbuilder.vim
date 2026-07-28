" Syntax highlighting for sfsoqlbuilder buffers (SOQL Query Builder)
" @license MIT

if exists("b:current_syntax")
  finish
endif

" ── Structural ──────────────────────────────────────────
syntax match SfSoqlDivider /─\{2,}/

" ── Title ───────────────────────────────────────────────
syntax match SfSoqlTitle /\cSOQL BUILDER.*/
syntax match SfSoqlTitle /\cSUBQUERY BUILDER.*/

" ── Section headers (keyword alone at end-of-line) ──────
syntax match SfSoqlHeader /SELECT\s*$/
syntax match SfSoqlHeader /FROM\s*$/
syntax match SfSoqlHeader /WHERE\s*$/
syntax match SfSoqlHeader /ORDER BY\s*$/
syntax match SfSoqlHeader /LIMIT:/
syntax match SfSoqlHeader /OFFSET:/

" ── Field items ─────────────────────────────────────────
syntax match SfSoqlFieldItem /•\s*\zs.*$/

" ── sObject name (3-space indent) ──────────────────────
syntax match SfSoqlObject /^\s\{3}[A-Za-z_][A-Za-z0-9_.@]*\s*$/

" ── Action hints ────────────────────────────────────────
syntax match SfSoqlKey /\[.\]/
syntax match SfSoqlAction /\[.\]\s*\zs.*$/

" ── WHERE / ORDER BY clause number ──────────────────────
syntax match SfSoqlClauseNumber /^\s*[0-9]\+\./

" ── WHERE operators ─────────────────────────────────────
syntax match SfSoqlWhereOperator /\s\(=\|<\|>\|<=\|>=\|!=\|<>\|LIKE\|IN\|NOT IN\|INCLUDES\|EXCLUDES\)\s/

" ── ORDER BY direction ──────────────────────────────────
syntax match SfSoqlOrderByDirection /^\s*[0-9]\+\.\s.*\zs\(ASC\|DESC\|NULLS FIRST\|NULLS LAST\)\s*$/

" ── LIMIT / OFFSET values ───────────────────────────────
syntax match SfSoqlLimitValue /LIMIT:\s*\zs.*$/
syntax match SfSoqlOffsetValue /OFFSET:\s*\zs.*$/

" ── Warnings ────────────────────────────────────────────
syntax match SfSoqlWarning /(no fields selected.*)/

" ── Subquery references ────────────────────────────────
syntax match SfSoqlSubquery /(SELECT\.\.\.FROM\.\.\.)/

" ── Preview section header ─────────────────────────────
syntax match SfSoqlPreviewHeader /SOQL Preview/
syntax match SfSoqlPreviewHeader /Subquery\ze\s*$/

" ── Highlight links (all default so users can override) ─
highlight default link SfSoqlDivider LineNr
highlight default link SfSoqlTitle Title
highlight default link SfSoqlHeader Statement
highlight default link SfSoqlFieldItem Identifier
highlight default link SfSoqlObject Type
highlight default link SfSoqlKey MoreMsg
highlight default link SfSoqlAction Comment
highlight default link SfSoqlClauseNumber Number
highlight default link SfSoqlWhereOperator Operator
highlight default link SfSoqlOrderByDirection Function
highlight default link SfSoqlLimitValue Number
highlight default link SfSoqlOffsetValue Number
highlight default link SfSoqlWarning WarningMsg
highlight default link SfSoqlSubquery Special
highlight default link SfSoqlPreviewHeader SpecialComment

let b:current_syntax = "sfsoqlbuilder"
