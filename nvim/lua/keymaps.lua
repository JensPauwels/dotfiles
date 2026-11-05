-- Global keys. Every one has a description: the menu (<leader><leader>) and
-- which-key list them from it, grouped by the <leader> prefix.
local map = function(mode, lhs, rhs, desc)
	vim.keymap.set(mode, lhs, rhs, { noremap = true, silent = true, desc = desc })
end

-- The menu: everything you can do here, fuzzy-searchable, with its key.
map("n", "<leader><leader>", function() require("menu").open() end, "Menu: all actions and their keys")

-- Window navigation
map("n", "<C-h>", "<C-w>h", "Window: left")
map("n", "<C-j>", "<C-w>j", "Window: down")
map("n", "<C-k>", "<C-w>k", "Window: up")
map("n", "<C-l>", "<C-w>l", "Window: right")

-- Clear highlight
map("n", "<Esc>", "<cmd>noh<CR>", "Edit: clear search highlight")

-- LSP
map("n", "<leader>r", vim.lsp.buf.rename, "Code: rename symbol")
map("n", "<leader>e", vim.diagnostic.open_float, "Code: show diagnostic / review thread")

-- Move lines (without touching your registers)
map("n", "<leader>k", "<cmd>move .-2<CR>==", "Edit: move line up")
map("n", "<leader>j", "<cmd>move .+1<CR>==", "Edit: move line down")
map("x", "<leader>k", ":move '<-2<CR>gv=gv", "Edit: move selection up")
map("x", "<leader>j", ":move '>+1<CR>gv=gv", "Edit: move selection down")
map("v", "r", '"_dP', "Edit: replace selection without yank")

-- Fuzzy finders (snacks). <leader>f… for everything, plus a few shortcuts.
local pick = function(name, opts)
	return function() Snacks.picker[name](opts) end
end
map("n", "<C-p>", pick("files"), "Find: files")
map("n", "<leader>/", pick("grep"), "Find: grep in the project")
map("n", "<leader>,", pick("buffers"), "Find: open buffers")
map("n", "<leader>ff", pick("files"), "Find: files")
map("n", "<leader>fg", pick("grep"), "Find: grep in the project")
map({ "n", "x" }, "<leader>fw", pick("grep_word"), "Find: grep the word / selection")
map("n", "<leader>fb", pick("buffers"), "Find: open buffers")
map("n", "<leader>fr", pick("recent"), "Find: recent files")
map("n", "<leader>f.", pick("resume"), "Find: resume the last finder")
map("n", "<leader>fl", pick("lines"), "Find: lines of this buffer")
map("n", "<leader>fs", pick("lsp_symbols"), "Find: symbols in this file")
map("n", "<leader>fS", pick("lsp_workspace_symbols"), "Find: symbols in the project")
map("n", "<leader>fd", pick("diagnostics_buffer"), "Find: diagnostics in this file")
map("n", "<leader>fD", pick("diagnostics"), "Find: diagnostics in the project")
map("n", "<leader>fh", pick("help"), "Find: help pages")
map("n", "<leader>fk", pick("keymaps"), "Find: all keymaps (raw)")
map("n", "<leader>fc", pick("commands"), "Find: commands")
map("n", "<leader>f:", pick("command_history"), "Find: command history")
map("n", "<leader>fj", pick("jumps"), "Find: jump list")
map("n", "<leader>fm", pick("marks"), "Find: marks")
map("n", "<leader>fu", pick("undo"), "Find: undo history")
map("n", "<leader>fq", pick("qflist"), "Find: quickfix list")
map("n", "<leader>fn", function() Snacks.notifier.show_history() end, "Find: notification history")

-- Tabs (gt / gT switch; <Tab> is left alone so <C-i> jumps forward)
map("n", "<leader>tt", "<cmd>tabnew<CR>", "Tabs: new")
map("n", "<leader>x", "<cmd>tabclose<CR>", "Tabs: close")
