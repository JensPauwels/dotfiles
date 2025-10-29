require("nvchad.mappings")

-- add yours here

vim.keymap.set("i", "jk", "<ESC>")
vim.keymap.set("n", "<C-p>", "<cmd>Telescope find_files<cr>")
vim.keymap.set("n", "<leader>fg", "<cmd>Telescope live_grep<cr>", { desc = "Telescope live grep" })
vim.keymap.set("n", "<leader>n", "<cmd>NvimTreeToggle<cr>", { desc = "Toggle nvim-tree" })
vim.keymap.set("n", "<leader>s", "<cmd>NvimTreeFindFile<cr>", { desc = "Reveal file in nvim-tree" })
vim.keymap.set("n", "<leader>gr", "<cmd>Telescope lsp_references<cr>", { desc = "LSP references" })
vim.keymap.set("n", "<leader>e", vim.diagnostic.open_float, { desc = "[E]xpand diagnostic message" })
vim.keymap.set("n", "<leader>ca", "<cmd>LspTypescriptSourceAction<cr>", { desc = "Code actions" })
vim.keymap.set("n", "<leader>da", "<cmd>Telescope diagnostics<cr>", { desc = "Telescope diagnostics" })
vim.keymap.set("n", "<Esc>", "<cmd>nohlsearch<CR>")
vim.keymap.set("n", "<C-t>", function()
  require("nvchad.themes").open()
end)

-- Lazygit
vim.keymap.set("n", "<leader>gg", "<cmd>LazyGit<cr>", { desc = "Open LazyGit" })
