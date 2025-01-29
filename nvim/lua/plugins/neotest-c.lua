return {
	"nvim-neotest/neotest",
	lazy = true,
	dependencies = {
		"nvim-neotest/nvim-nio",
		"nvim-neotest/neotest-go",
		"nvim-neotest/neotest-jest",

		"nvim-lua/plenary.nvim",
		"antoinemadec/FixCursorHold.nvim",
		"nvim-treesitter/nvim-treesitter",
		"olimorris/neotest-phpunit",
		"marilari88/neotest-vitest",
		"andythigpen/nvim-coverage",
	},
	config = function()
		require("coverage").setup({
			auto_reload = true,
			commands = true,
		})

		require("neotest").setup({
			adapters = {
				require("neotest-go")({
					args = { "-coverpkg=./...", "-coverprofile=coverage.out" },
				}),
				require("neotest-phpunit"),
				require("neotest-vitest"),
				require("neotest-jest")({
					env = { CI = true },
					cwd = function(path)
						return vim.fn.getcwd()
					end,
				}),
			},
		})
	end,
}
