-- Set tab width to 2 spaces
vim.opt.tabstop = 2
vim.opt.shiftwidth = 2
vim.opt.expandtab = true

-- Enable relative line numbers
vim.opt.number = true
vim.opt.relativenumber = true

-- Set the leader to space
vim.g.mapleader = " "

-- Enable word wrapping
vim.opt.wrap = true

-- Enable auto indentation
vim.opt.autoindent = true

-- Ignore the casing
vim.o.ignorecase = true

-- Place a line at 100 characters
vim.cmd("set colorcolumn=100")

vim.o.completeopt = "menuone,noinsert,noselect"
