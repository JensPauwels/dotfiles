return {
	-- "tiagovla/tokyodark.nvim",
	"EdenEast/nightfox.nvim",
	config = function(_, opts)
		vim.cmd([[colorscheme nightfox]])
		-- vim.cmd([[colorscheme tokyodark]])
	end,
}
