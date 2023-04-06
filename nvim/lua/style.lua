vim.cmd('colorscheme monokai-pro')
vim.cmd(':highlight LineNr guifg=#808691')
vim.cmd('highlight  DiagnosticUnderlineHint ctermfg=243 guifg=#65737e')
vim.cmd('highlight  DiagnosticUnderlineError guifg=#CB5551 guibg=#342C3C')
vim.api.nvim_set_hl(0, "ColorColumn", { ctermbg = 0, bg = "#161821" })
-- vim.g:lightline = {'colorscheme': 'monokaipro'}

-- vim.g.catppuccin_flavour = "mocha" -- latte, frappe, macchiato, mocha

