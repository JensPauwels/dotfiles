local Snacks = require("snacks")
local opts = { noremap = true, silent = true }

-- Basic navigation and split controls
vim.keymap.set("n", "<C-h>", "<C-w>h", opts)
vim.keymap.set("n", "<C-j>", "<C-w>j", opts)
vim.keymap.set("n", "<C-k>", "<C-w>k", opts)
vim.keymap.set("n", "<C-l>", "<C-w>l", opts)
vim.keymap.set("n", "tnew", "<cmd>tabnew<CR>", opts)

-- Highlight control
vim.keymap.set("n", "<Esc>", "<cmd>noh<CR>", opts)

-- LSP
vim.keymap.set("n", "<leader>r", vim.lsp.buf.rename, opts)
vim.keymap.set("n", "<leader>e", vim.diagnostic.open_float, opts)

-- Text movement
vim.keymap.set("n", "<Leader>k", "ddkP", opts)
vim.keymap.set("n", "<Leader>j", "ddp", opts)
vim.keymap.set("v", "r", '"_dP', opts)

-- Snacks
vim.keymap.set("n", "<leader>s", "<cmd>NvimTreeFindFile<CR>", opts)
vim.keymap.set("n", "<leader>n", Snacks.picker.explorer, opts)
vim.keymap.set("n", "<C-p>", Snacks.picker.files, opts)
vim.keymap.set("n", "<leader>ff", Snacks.picker.files, opts)
vim.keymap.set("n", "<leader>fg", Snacks.picker.grep, opts)
vim.keymap.set("n", "<leader>fb", Snacks.picker.buffers, opts)
vim.keymap.set("n", "<leader>da", Snacks.picker.diagnostics, opts)

-- Testing (neotest)
vim.keymap.set("n", "<leader>tf", function()
	require("neotest").run.run(vim.fn.expand("%"))
end, opts)

vim.keymap.set("n", "<leader>tn", function()
	require("neotest").run.run()
end, opts)

vim.keymap.set("n", "<leader>td", function()
	require("neotest").run.run({ strategy = "dap" })
end, opts)

-- Go coverage
vim.keymap.set("n", "<leader>gc", function()
	local dir = vim.fn.expand("%:p:h")
	local cmd = "GoCoverageOverlay " .. dir .. "/coverage.out"
	print("Generated command:", cmd)
	vim.cmd(cmd)
end, opts)

-- Rest client
vim.keymap.set("n", "<leader>tr", "<cmd>Rest run<CR>", opts)

-- LazyGit command
vim.api.nvim_create_user_command("LazyGit", function()
	Snacks.lazygit()
end, {})
