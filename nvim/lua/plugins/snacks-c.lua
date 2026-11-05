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
		{ "<C-t>", function() Snacks.terminal.toggle() end, desc = "Terminal: toggle", mode = { "n", "t" } },
		{
			"<leader>n",
			function()
				-- While reviewing a pull request (:PR review), the sidebar lists
				-- its changed files instead of the whole tree.
				if not require("pulls.review").tree() then
					Snacks.explorer()
				end
			end,
			desc = "Explorer: files (changed files while reviewing a PR)",
		},
		{ "<leader>N", function() Snacks.explorer() end, desc = "Explorer: always the full tree" },
		{ "<leader>s", function() Snacks.explorer.reveal() end, desc = "Explorer: reveal the current file" },
	},
}
