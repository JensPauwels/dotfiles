return {
	"nvim-lualine/lualine.nvim",
	config = function()
		require("lualine").setup({
			options = {
				theme = "tokyodark",
			},
			options = {
				section_separators = { "", "" },
				component_separators = { "", "" },
			},
			sections = {
				lualine_a = {},
				lualine_b = {},
				lualine_c = {
					{ "filename", path = 1 }, -- Shows folder and file
				},
				lualine_x = {},
				lualine_y = {},
				lualine_z = { "branch" },
			},
			inactive_sections = {
				lualine_a = {},
				lualine_b = {},
				lualine_c = {
					{ "filename", path = 1 }, -- Shows folder and file in inactive mode
				},
				lualine_x = { "branch" },
				lualine_y = {},
				lualine_z = {},
			},
		})
	end,
}
