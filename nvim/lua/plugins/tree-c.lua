return {
	"nvim-tree/nvim-tree.lua",
	dependencies = {
		"nvim-tree/nvim-web-devicons", -- optional, for file icons
	},
	opts = {
		filters = {
			dotfiles = false, -- Show dotfiles
			custom = { ".DS_Store", "thumbs.db" }, -- Add specific names to hide
		},
		git = {
			ignore = false, -- Hide gitignored files
		},
		renderer = {
			highlight_git = true, -- Highlight git changes
		},
		view = {
			adaptive_size = true, -- Automatically resize tree view
		},
	},
}
