return {
	{
		"nvim-telescope/telescope.nvim",
		tag = "0.1.4",
		dependencies = { "nvim-lua/plenary.nvim" },
		config = function()
			extensions = {
				["ui-select"] = {
					require("telescope.themes").get_dropdown({}),
				},
			}
			require("telescope").load_extension("ui-select")
			require("telescope").setup({
				pickers = {
					find_files = {
						theme = "dropdown",
					},
				},
			})
		end,
	},
	{
		"nvim-telescope/telescope-ui-select.nvim",
	},
}
