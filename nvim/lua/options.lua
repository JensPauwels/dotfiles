require "nvchad.options"

-- add yours here!

local o = vim.o

o.relativenumber = true -- enable relative line numbers
-- o.cursorlineopt ='both' -- to enable cursorline!

-- Don't sync clipboard with system clipboard
-- This keeps d/y in vim registers (usable with p), but separate from cmd+v
o.clipboard = ""
