--- Apply basic syntax highlights to sftraceflag filetype buffers
-- @license MIT

vim.cmd([[
  syntax clear
  syntax match SfTraceFlagLabel /^\s\+\w.*$/ contains=@NoSpell
  syntax match SfTraceFlagAccordion /^\s*>/ contained
  syntax match SfTraceFlagValue /^\s*> \zs.*$/ contains=@NoSpell
  syntax match SfTraceFlagSeparator /^.*───.*$/
  syntax match SfTraceFlagFooter /^  Press.*$/

  highlight default link SfTraceFlagLabel Identifier
  highlight default link SfTraceFlagAccordion Special
  highlight default link SfTraceFlagValue String
  highlight default link SfTraceFlagSeparator Comment
  highlight default link SfTraceFlagFooter Comment
]])
