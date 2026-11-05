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
			map("n", "]h", gs.next_hunk, "Hunk: next")
			map("n", "[h", gs.prev_hunk, "Hunk: previous")

			-- Hunk actions
			map("n", "<leader>hp", gs.preview_hunk_inline, "Hunk: preview inline")
			map("n", "<leader>hd", function()
				gs.toggle_deleted()
				gs.toggle_linehl()
				gs.toggle_word_diff()
			end, "Hunk: toggle inline diff (colours)")
			map("n", "<leader>hr", gs.reset_hunk, "Hunk: reset")
			map("n", "<leader>hs", gs.stage_hunk, "Hunk: stage")
			map("v", "<leader>hs", function() gs.stage_hunk({ vim.fn.line("."), vim.fn.line("v") }) end, "Hunk: stage")
			map("v", "<leader>hr", function() gs.reset_hunk({ vim.fn.line("."), vim.fn.line("v") }) end, "Hunk: reset")
			map("n", "<leader>hb", gs.blame_line, "Hunk: blame line")
		end,
	},
}
