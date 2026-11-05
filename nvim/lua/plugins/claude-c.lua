-- Local plugin: send the current file / lines / diagnostics to the Claude
-- Code pane in tmux. Source in nvim/local/claude.nvim.
local here = vim.uv.fs_realpath(debug.getinfo(1, "S").source:sub(2)) or debug.getinfo(1, "S").source:sub(2)
local plugin_dir = vim.fn.fnamemodify(here, ":h:h:h") .. "/local/claude.nvim"

return {
	dir = plugin_dir,
	name = "claude.nvim",
	main = "claude",
	cmd = "ClaudePane",
	opts = {},
	keys = {
		{ "<leader>aa", function() require("claude").send_here() end, mode = { "n", "x" }, desc = "AI: send these lines to Claude" },
		{ "<leader>af", function() require("claude").send_file() end, desc = "AI: send this file to Claude" },
		{ "<leader>ad", function() require("claude").send_diagnostics() end, mode = { "n", "x" }, desc = "AI: ask Claude about the errors here" },
		{ "<leader>ap", "<cmd>ClaudePane<CR>", desc = "AI: choose the Claude pane" },
	},
}
