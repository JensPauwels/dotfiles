vim.keymap.set("n", "<leader>s", function()
	vim.api.nvim_command("NvimTreeFindFile")
end, {})

-- Keybind to open the file navigator
vim.keymap.set("n", "<leader>n", function()
	vim.api.nvim_command("NvimTreeToggle")
end, {})

-- Rename
vim.keymap.set("n", "<leader>r", function()
	vim.api.nvim_command("lua vim.lsp.buf.rename()")
end, {})

-- Keybind to replace
vim.keymap.set("v", "r", '"_dP', {})

-- Make split navigation easier.
vim.keymap.set("n", "<C-H>", "<C-W><C-H>", { noremap = true })
vim.keymap.set("n", "<C-J>", "<C-W><C-J>", { noremap = true })
vim.keymap.set("n", "<C-K>", "<C-W><C-K>", { noremap = true })
vim.keymap.set("n", "<C-L>", "<C-W><C-L>", { noremap = true })

-- Open a new tab
vim.keymap.set("n", "tnew", function()
	vim.api.nvim_command("tabnew")
end, { noremap = true })

-- Remove the previous highlight when pressing escape
vim.keymap.set("n", "<Esc>", function()
	vim.api.nvim_command("noh")
end, { noremap = true })

vim.api.nvim_set_keymap("n", "<Leader>k", "ddkP", { noremap = true })
vim.api.nvim_set_keymap("n", "<Leader>j", "ddp", { noremap = true })

-- Open a diagnostic screen with the current error
vim.keymap.set("n", "<Leader>e", function()
	vim.api.nvim_command("lua vim.diagnostic.open_float()")
end, { noremap = true })

-- Opens the snacks file finder
vim.keymap.set("n", "<C-p>", function()
	vim.api.nvim_command("lua Snacks.picker.files()")
end, { noremap = true })

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
