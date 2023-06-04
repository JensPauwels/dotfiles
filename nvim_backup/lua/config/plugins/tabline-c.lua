vim.opt.termguicolors = true

return {
	"alvarosevilla95/luatab.nvim",
	config = function()
		require("luatab").setup({
			windowCount = function()
				return ""
			end,
		})
	end,
}
