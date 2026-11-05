-- Local plugin: GitHub pull requests in a tab (list, overview, inline diff,
-- review threads). Source lives in nvim/local/pulls.nvim, next to
-- changes.nvim; see that spec for why the path is resolved this way.
local here = vim.uv.fs_realpath(debug.getinfo(1, "S").source:sub(2)) or debug.getinfo(1, "S").source:sub(2)
local plugin_dir = vim.fn.fnamemodify(here, ":h:h:h") .. "/local/pulls.nvim"

return {
	dir = plugin_dir,
	name = "pulls.nvim",
	main = "pulls",
	cmd = "PR",
	opts = {
		panel_width = 50,
	},
	keys = {
		{ "<leader>gp", function() require("pulls").toggle() end, desc = "Pulls: GitHub pull requests" },
		{ "<leader>fp", function() require("pulls").pick() end, desc = "Pulls: pick a PR to review (checks it out)" },
	},
}
