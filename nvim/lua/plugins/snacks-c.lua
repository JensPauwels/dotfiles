return {
	"folke/snacks.nvim",
	priority = 1000,
	lazy = false,
	opts = {
		picker = {
			sources = {
				files = {
					hidden = true,
					ignored = true,
					exclude = { "node_modules", ".git", "dist", ".terraform", "vendor", "coverage", ".next", "build" },
				},
			},
		},
		bigfile = { enabled = true },
		lazygit = { enabled = true },
		debug = { enabled = true },
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
