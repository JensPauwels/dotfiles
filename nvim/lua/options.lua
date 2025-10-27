require "nvchad.options"

vim.o.relativenumber = true -- enable relative line numbers
-- o.cursorlineopt ='both' -- to enable cursorline!

-- Don't sync clipboard with system clipboard
-- This keeps d/y in vim registers (usable with p), but separate from cmd+v
vim.o.clipboard = ""
vim.o.breakindent = true
vim.o.ignorecase = true
vim.o.smartcase = true

-- Keep signcolumn on by default
vim.o.signcolumn = 'yes'

-- Decrease update time
vim.o.updatetime = 250

-- Decrease mapped sequence wait time
vim.o.timeoutlen = 300
