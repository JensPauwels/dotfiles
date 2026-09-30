-- Local plugin: VSCode-style inline git diff view. Source lives in
-- nvim/local/changes.nvim so it can be moved to its own repo later.
--
-- ~/.config/nvim only symlinks init.lua and lua/, so resolve the plugin
-- directory from this file's real location instead of stdpath("config").
local here = vim.uv.fs_realpath(debug.getinfo(1, "S").source:sub(2)) or debug.getinfo(1, "S").source:sub(2)
local plugin_dir = vim.fn.fnamemodify(here, ":h:h:h") .. "/local/changes.nvim"

return {
	dir = plugin_dir,
	name = "changes.nvim",
	main = "changes",
	cmd = "Changes",
	opts = {
		context = 3,
		panel_width = 40,
	},
	keys = {
		{ "<leader>gd", function() require("changes").toggle() end, desc = "Changes: inline diff of working tree" },
	},
}
