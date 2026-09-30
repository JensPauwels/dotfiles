return {
	"sindrets/diffview.nvim",
	cmd = { "DiffviewOpen", "DiffviewFileHistory", "DiffviewClose", "DiffviewToggleFiles", "DiffviewFocusFiles" },
	opts = {
		enhanced_diff_hl = true,
		view = {
			-- VSCode-like side-by-side diff
			default = { layout = "diff2_horizontal" },
			merge_tool = { layout = "diff3_horizontal" },
		},
	},
	keys = {
		{
			"<leader>gD",
			function()
				local lib = require("diffview.lib")
				if lib.get_current_view() then
					vim.cmd("DiffviewClose")
				else
					vim.cmd("DiffviewOpen")
				end
			end,
			desc = "Diffview: side-by-side working changes",
		},
		{ "<leader>gh", "<cmd>DiffviewFileHistory<cr>", desc = "Diffview: repo file history" },
		{ "<leader>gf", "<cmd>DiffviewFileHistory %<cr>", desc = "Diffview: current file history" },
	},
}
