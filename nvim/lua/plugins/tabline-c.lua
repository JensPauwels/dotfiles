 return {
 	"alvarosevilla95/luatab.nvim",
 	init = function()
 		vim.opt.termguicolors = true
 	end,
 	config = function()
 		require("luatab").setup({
 			windowCount = function()
 				return ""
 			end,
 		})
 	end,
 }

-- return {'akinsho/bufferline.nvim', version = "*", dependencies = 'nvim-tree/nvim-web-devicons'}

