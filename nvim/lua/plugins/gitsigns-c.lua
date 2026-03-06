return {
	"lewis6991/gitsigns.nvim",
	event = { "BufReadPre", "BufNewFile" },
	opts = {
		signs = {
			add = { text = "+" },
			change = { text = "~" },
			delete = { text = "_" },
			topdelete = { text = "-" },
			changedelete = { text = "~" },
		},
		current_line_blame = false,
		on_attach = function(bufnr)
			local gs = package.loaded.gitsigns

			local function map(mode, l, r, desc)
				vim.keymap.set(mode, l, r, { buffer = bufnr, desc = desc })
			end

			-- Navigation between hunks
			map("n", "]c", gs.next_hunk, "Next hunk")
			map("n", "[c", gs.prev_hunk, "Prev hunk")

			-- Actions
			map("n", "<leader>gp", gs.preview_hunk, "Preview hunk")
			map("n", "<leader>gr", gs.reset_hunk, "Reset hunk")
			map("n", "<leader>gb", gs.blame_line, "Blame line")
		end,
	},
}
