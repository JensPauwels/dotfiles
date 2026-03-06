return {
	"nvim-tree/nvim-tree.lua",
	dependencies = {
		"nvim-tree/nvim-web-devicons",
	},
	cmd = { "NvimTreeToggle", "NvimTreeFindFile" },
	keys = {
		{ "<leader>n", "<cmd>NvimTreeToggle<CR>", desc = "Toggle NvimTree" },
		{ "<leader>s", "<cmd>NvimTreeFindFile<CR>", desc = "Find file in NvimTree" },
	},
	config = function()
		require("nvim-tree").setup({
			sort = {
				sorter = "case_sensitive",
			},
			view = {
				width = 30,
			},
			renderer = {
				group_empty = true,
				icons = {
					show = {
						file = true,
						folder = true,
						folder_arrow = true,
						git = true,
					},
				},
			},
			filters = {
				dotfiles = false,
			},
		})
	end,
}
