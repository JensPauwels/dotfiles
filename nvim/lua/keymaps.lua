local Snacks = require("snacks")
local opts = { noremap = true, silent = true }

vim.keymap.set("n", "<leader>s", function()
	vim.api.nvim_command("NvimTreeFindFile")
end, {})

-- Snacks keybindings
vim.keymap.set("n", "<leader>n", Snacks.picker.explorer, opts)

-- Rename
vim.keymap.set("n", "<leader>r", function()
	vim.api.nvim_command("lua vim.lsp.buf.rename()")
end, {})

-- Keybind to replace
vim.keymap.set("v", "r", '"_dP', {})

-- Make split navigation easier.
vim.keymap.set("n", "<C-H>", "<C-W><C-H>", opts)
vim.keymap.set("n", "<C-J>", "<C-W><C-J>", opts)
vim.keymap.set("n", "<C-K>", "<C-W><C-K>", opts)
vim.keymap.set("n", "<C-L>", "<C-W><C-L>", opts)

-- Open a new tab
vim.keymap.set("n", "tnew", function()
	vim.api.nvim_command("tabnew")
end, { noremap = true })

-- Remove the previous highlight when pressing escape
vim.keymap.set("n", "<Esc>", function()
	vim.api.nvim_command("noh")
end, { noremap = true })

vim.api.nvim_set_keymap("n", "<Leader>k", "ddkP", opts)
vim.api.nvim_set_keymap("n", "<Leader>j", "ddp", opts)

-- Open a diagnostic screen with the current error
vim.keymap.set("n", "<Leader>e", function()
	vim.api.nvim_command("lua vim.diagnostic.open_float()")
end, { noremap = true })

-- Opens the snacks file finder
vim.keymap.set("n", "<C-p>", Snacks.picker.files, opts)

-- Keymaps for testing
vim.keymap.set("n", "<Leader>tf", function()
	vim.api.nvim_command('lua require("neotest").run.run(vim.fn.expand("%"))')
end, { noremap = true })

vim.keymap.set("n", "<Leader>tn", function()
	vim.api.nvim_command('lua require("neotest").run.run()')
end, { noremap = true })

vim.keymap.set("n", "<Leader>gc", function()
	local current_file_dir = vim.fn.expand("%:p:h")
	local coverage_file = "/coverage.out"
	local command = string.format("GoCoverageOverlay %s%s", current_file_dir, coverage_file)
	print("Generated command:", command)
	vim.api.nvim_command(command)
end, { noremap = true })

vim.keymap.set("n", "<Leader>td", function()
	vim.api.nvim_command('lua require("neotest").run.run({strategy = "dap"})')
end, { noremap = true })

vim.api.nvim_create_user_command("LazyGit", function()
	Snacks.lazygit()
end, {})

vim.keymap.set("n", "<leader>ff", Snacks.picker.files, opts)
vim.keymap.set("n", "<leader>fg", Snacks.picker.grep, opts)
vim.keymap.set("n", "<leader>fb", Snacks.picker.buffers, opts)
