return {
	"stevearc/conform.nvim",
	lazy = true,
	event = { "BufReadPre", "BufNewFile" },
	config = function()
		local conform = require("conform")
		conform.setup({
			formatters_by_ft = {
				go = { "goimports", "gofmt" },
				lua = { "stylua" },
				javascript = { "prettierd" },
				typescript = { "prettier" },
				php = { "php" },
			},
			format_on_save = {
				lsp_fallback = true,
				async = false,
				timeout_ms = 1000,
			},
			notify_on_error = true,
		})
	end,
}
