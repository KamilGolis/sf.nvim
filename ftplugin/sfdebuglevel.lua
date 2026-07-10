--- Apply basic syntax highlights to sfdebuglevel filetype buffers
-- @license MIT

vim.cmd([[
  syntax clear
  syntax match SfDebugLevelLabel /^\s\+\w.*$/ contains=@NoSpell
  syntax match SfDebugLevelAccordion /^\s*>/ contained
  syntax match SfDebugLevelValue /^\s*> \zs.*$/ contains=@NoSpell
  syntax match SfDebugLevelReadOnly /(read-only)$/ contained
  syntax match SfDebugLevelSeparator /^.*───.*$/
  syntax match SfDebugLevelFooter /^  Press.*$/

  highlight default link SfDebugLevelLabel Identifier
  highlight default link SfDebugLevelAccordion Special
  highlight default link SfDebugLevelValue String
  highlight default link SfDebugLevelReadOnly Comment
  highlight default link SfDebugLevelSeparator Comment
  highlight default link SfDebugLevelFooter Comment
]])
