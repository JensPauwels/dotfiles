return {
	"folke/which-key.nvim",
	event = "VeryLazy",
	opts = {
		preset = "modern",
		delay = 300,
		spec = {
			{ "<leader>a", group = "ai (Claude in tmux)" },
			{ "<leader>f", group = "find" },
			{ "<leader>g", group = "git" },
			{ "<leader>h", group = "hunk" },
			{ "<leader>p", group = "pull request (while reviewing)" },
			{ "<leader>t", group = "tabs" },
			{ "<leader>c", group = "code" },
		},
	},
}
