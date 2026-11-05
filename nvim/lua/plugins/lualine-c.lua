return {
	"nvim-lualine/lualine.nvim",
	dependencies = { "nvim-tree/nvim-web-devicons" },
	event = "VeryLazy",
	opts = {
		options = {
			theme = "auto",
			globalstatus = true,
			section_separators = "",
			component_separators = "",
		},
		sections = {
			lualine_a = { "mode" },
			lualine_b = {
				"branch",
				"diff",
				-- "#123 4/9" (viewed/changed files) while reviewing a pull request
				{
					function() return require("pulls.review").status() end,
					cond = function() return package.loaded["pulls.review"] ~= nil end,
				},
			},
			lualine_c = { { "filename", path = 1 } },
			lualine_x = { "diagnostics", "filetype" },
			lualine_y = { "progress" },
			lualine_z = { "location" },
		},
	},
}
