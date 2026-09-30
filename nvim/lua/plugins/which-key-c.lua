return {
	"folke/which-key.nvim",
	event = "VeryLazy",
	opts = {
		preset = "modern",
		delay = 300,
		spec = {
			{ "<leader>f", group = "find" },
			{ "<leader>g", group = "git" },
			{ "<leader>h", group = "hunk" },
			{ "<leader>d", group = "debug" },
			{ "<leader>t", group = "test" },
			{ "<leader>c", group = "code" },
		},
	},
}
