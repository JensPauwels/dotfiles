return {
	"nvim-tree/nvim-tree.lua",
	cmd = { "NvimTreeToggle", "NvimTreeFindFile" }, -- Lazy load on command
	keys = {
		{ "<leader>n", "<cmd>NvimTreeToggle<CR>", desc = "Toggle NvimTree" },
		{ "<leader>s", "<cmd>NvimTreeFindFile<CR>", desc = "Find file in NvimTree" },
	},
	opts = function()
		require("nvim-tree").setup({
			sort = {
				sorter = "case_sensitive",
			},
			view = {
				width = 30,
			},
			renderer = {
				group_empty = true,
			},
			filters = {
				dotfiles = true,
			},
		})
	end,
}
