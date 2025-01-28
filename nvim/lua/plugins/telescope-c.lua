return {
	{
		"nvim-telescope/telescope.nvim",
		tag = "0.1.4",
		dependencies = { "nvim-lua/plenary.nvim" },
		config = function()
			require("telescope").setup({
				defaults = {
					prompt_prefix = "> ",
					selection_caret = "> ",
					path_display = { "smart" },
				},
			})
		end,
	},
}
