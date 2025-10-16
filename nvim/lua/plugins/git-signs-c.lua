return {
	"lewis6991/gitsigns.nvim",
	event = { "BufReadPre", "BufNewFile" }, -- Lazy load when opening files
	config = function()
		require("gitsigns").setup()
	end,
}
