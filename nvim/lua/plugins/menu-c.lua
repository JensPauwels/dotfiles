-- Local plugin: <leader><leader> opens a fuzzy menu of every action with its
-- key, the current buffer's own keys first. Source in nvim/local/menu.nvim.
local here = vim.uv.fs_realpath(debug.getinfo(1, "S").source:sub(2)) or debug.getinfo(1, "S").source:sub(2)
local plugin_dir = vim.fn.fnamemodify(here, ":h:h:h") .. "/local/menu.nvim"

return {
	dir = plugin_dir,
	name = "menu.nvim",
	main = "menu",
	cmd = "Menu",
	opts = {
		-- Commands without a key, so they can be found too.
		extras = {
			{ "Pulls", "Review a pull request by number", "PR review " },
			{ "Pulls", "Finish the review (back to your branch)", "PR done" },
			{ "Pulls", "Install dependencies, restart LSP", "PR install" },
			{ "Changes", "Inline diff of the working tree", "Changes" },
			{ "General", "Plugins (lazy.nvim)", "Lazy" },
			{ "General", "Language servers and tools (mason)", "Mason" },
			{ "General", "LSP info for this buffer", "checkhealth vim.lsp" },
		},
	},
}
