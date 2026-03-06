return {
	"nvim-treesitter/nvim-treesitter",
	build = ":TSUpdate",
	config = function()
		require("nvim-treesitter.configs").setup({
			ensure_installed = {
				"typescript",
				"tsx",
				"javascript",
				"go",
				"gomod",
				"gosum",
				"hcl",
				"terraform",
				"lua",
				"html",
				"css",
				"json",
				"yaml",
				"markdown",
				"markdown_inline",
			},
			sync_install = false,
			auto_install = true,
			indent = {
				enable = true,
			},
			highlight = {
				enable = true,
				disable = { "c", "rust" },
				additional_vim_regex_highlighting = false,
			},
		})
	end,
}
