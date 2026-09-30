return {
	"folke/snacks.nvim",
	priority = 1000,
	lazy = false,
	---@type snacks.Config
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
		explorer = { enabled = true },
		terminal = { enabled = true },
		rename = { enabled = true },
		notifier = { enabled = true, history = true },
		quickfile = { enabled = true },
		statuscolumn = { enabled = true },
		words = { enabled = true },
		input = { enabled = true },
		image = { enabled = false },
	},
	keys = {
		{ "<C-t>", function() Snacks.terminal.toggle() end, desc = "Toggle terminal", mode = { "n", "t" } },
		{ "<leader>n", function() Snacks.explorer() end, desc = "File explorer" },
		{ "<leader>s", function() Snacks.explorer.reveal() end, desc = "Reveal current file in explorer" },
	},
}
