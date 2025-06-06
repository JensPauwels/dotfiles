return {
	"nvim-treesitter/nvim-treesitter",
	config = function()
		require("nvim-treesitter.configs").setup({
			ensure_installed = { "c", "lua", "rust" },
			sync_install = false,
			auto_install = true,
			indent = {
				enable = true,
			},
			highlight = {
				enable = true,
				disable = { "c", "rust" },
				additional_vim_regex_highlighting = true,
			},
		})
	end,
}
