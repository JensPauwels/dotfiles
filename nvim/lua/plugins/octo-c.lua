return {
	"pwntester/octo.nvim",
	dependencies = {
		"nvim-lua/plenary.nvim",
		"ibhagwan/fzf-lua",
		"nvim-tree/nvim-web-devicons",
	},
	config = function()
		require("octo").setup({
			picker = "fzf-lua", -- let's hope I can change this to snacks soon :D
		})
	end,
}
