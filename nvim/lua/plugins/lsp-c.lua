return {
	{
		"williamboman/mason.nvim",
		cmd = "Mason",
		build = ":MasonUpdate",
		opts = {},
	},
	{
		"WhoIsSethDaniel/mason-tool-installer.nvim",
		dependencies = { "williamboman/mason.nvim" },
		event = "VeryLazy",
		opts = {
			ensure_installed = {
				"lua-language-server",
				"typescript-language-server",
				"gopls",
				"terraform-ls",
				"tailwindcss-language-server",
				"intelephense",
				"stylua",
				"goimports",
				"biome",
				"php-cs-fixer",
			},
		},
	},
	{
		"neovim/nvim-lspconfig",
		event = { "BufReadPre", "BufNewFile" },
		dependencies = { "williamboman/mason.nvim", "saghen/blink.cmp" },
		config = function()
			require("plugins.config.lsp-c").setup()
		end,
	},
}
