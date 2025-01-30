return {
	"folke/snacks.nvim",
	priority = 1000,
	lazy = false,
	opts = {
		picker = {},
		bigfile = { enabled = true },
		lazygit = { enabled = true },
		debud = { enabled = true },
		rename = { enabled = true },
		notifier = { enabled = true },
		quickfile = { enabled = true },
		statuscolumn = { enabled = true },
		words = { enabled = true },
	},
	init = function()
		local Snacks = require("snacks")
		vim.api.nvim_create_autocmd("BufEnter", {
			group = vim.api.nvim_create_augroup("snacks_explorer_start_directory", { clear = true }),
			desc = "Start Snacks Explorer with directory",
			once = true,
			callback = function()
				local dir = vim.fn.argv(0) --[[@as string]]
				if dir ~= "" and vim.fn.isdirectory(dir) == 1 then
					Snacks.picker.explorer({ cwd = dir })
				end
			end,
		})
	end,
}
