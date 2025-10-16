require "nvchad.mappings"

-- add yours here

local map = vim.keymap.set

map("i", "jk", "<ESC>")
map("n", "<C-p>", "<cmd>Telescope find_files<cr>")
map("n", "<leader>fg", "<cmd>Telescope live_grep<cr>", { desc = "Telescope live grep" })
map("n", "<leader>n", "<cmd>NvimTreeToggle<cr>", { desc = "Toggle nvim-tree" })
map("n", "<leader>s", "<cmd>NvimTreeFindFile<cr>", { desc = "Reveal file in nvim-tree" })
map("n", "<leader>gr", "<cmd>Telescope lsp_references<cr>", { desc = "LSP references" })

map("n", "<C-t>", function ()
  require("nvchad.themes").open()
end)

-- Lazygit
map("n", "<leader>gg", "<cmd>LazyGit<cr>", { desc = "Open LazyGit" })
