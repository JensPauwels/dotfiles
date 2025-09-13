return {
	"folke/snacks.nvim",
	priority = 1000,
	lazy = false,
	opts = {
		picker = {
			files = {
				hidden = true,
			},
		},
		bigfile = { enabled = true },
		lazygit = { enabled = true },
		debud = { enabled = true },
		rename = { enabled = true },
		notifier = {
			enabled = true,
			history = true,
		},
		quickfile = { enabled = true },
		statuscolumn = { enabled = true },
		words = { enabled = true },
	},
}
