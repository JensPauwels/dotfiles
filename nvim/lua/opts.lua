-- Set tab width to 2 spaces
vim.opt.tabstop = 2
vim.opt.shiftwidth = 2

-- vim.opt.tabstop = 2
-- vim.opt.shiftwidth = 2
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

-- Make the buffer on the right active when splitting
vim.o.splitright = true

-- Make the buffer on the bottom active when splitting
vim.o.splitbelow = true

vim.o.completeopt = "menuone,noinsert,noselect"

vim.o.smartindent = true

vim.o.lazyredraw = true

vim.g.loaded_netrw = 1
vim.g.loaded_netrwPlugin = 1
