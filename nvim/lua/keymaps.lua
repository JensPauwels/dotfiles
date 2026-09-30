local map = function(mode, lhs, rhs, desc)
	vim.keymap.set(mode, lhs, rhs, { noremap = true, silent = true, desc = desc })
end

-- Window navigation
map("n", "<C-h>", "<C-w>h", "Window left")
map("n", "<C-j>", "<C-w>j", "Window down")
map("n", "<C-k>", "<C-w>k", "Window up")
map("n", "<C-l>", "<C-w>l", "Window right")

-- Clear highlight
map("n", "<Esc>", "<cmd>noh<CR>", "Clear search highlight")

-- LSP
map("n", "<leader>r", vim.lsp.buf.rename, "Rename symbol")
map("n", "<leader>e", vim.diagnostic.open_float, "Show diagnostic")

-- Move lines
map("n", "<leader>k", "ddkP", "Move line up")
map("n", "<leader>j", "ddp", "Move line down")
map("v", "r", '"_dP', "Replace selection without yank")

-- Pickers (snacks)
map("n", "<C-p>", function() Snacks.picker.files() end, "Find files")
map("n", "<leader>ff", function() Snacks.picker.files() end, "Find files")
map("n", "<leader>fg", function() Snacks.picker.grep() end, "Live grep")
map("n", "<leader>fb", function() Snacks.picker.buffers() end, "Buffers")
map("n", "<leader>fr", function() Snacks.picker.recent() end, "Recent files")
map("n", "<leader>da", function() Snacks.picker.diagnostics() end, "Diagnostics (workspace)")
map("n", "<leader>fn", function() Snacks.notifier.show_history() end, "Notification history")

-- Tests (neotest)
map("n", "<leader>tf", function() require("neotest").run.run(vim.fn.expand("%")) end, "Test file")
map("n", "<leader>tn", function() require("neotest").run.run() end, "Test nearest")
map("n", "<leader>td", function() require("neotest").run.run({ strategy = "dap" }) end, "Debug nearest test")

-- Go coverage
map("n", "<leader>cv", "<cmd>Coverage<CR>", "Toggle coverage")

-- Tabs
map("n", "<Tab>", "<cmd>tabnext<CR>", "Next tab")
map("n", "<leader>tt", "<cmd>tabnew<CR>", "New tab")
map("n", "<leader>x", "<cmd>tabclose<CR>", "Close tab")
