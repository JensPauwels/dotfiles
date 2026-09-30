local H = require("helpers")

return {
	{
		"w switches to another worktree",
		function()
			local root = H.repo()
			local wt = root .. "-wt"
			H.git(root, "worktree", "add", "-q", "-b", "feature", wt)
			H.write(wt, "f.txt", "only here\n")
			H.write(root, "a.lua", "main change\n")
			H.open(root)
			H.match(vim.wo[H.state().panel.win].winbar, "main")
			H.eq(H.panel_lines(), { " Changes (1)", "   M  a.lua" })
			H.ui_select("feature")
			H.keys("w")
			H.match(vim.wo[H.state().panel.win].winbar, "feature")
			H.eq(H.panel_lines(), { " Changes (1)", "   ?  f.txt" })
			H.view("f%.txt")
			H.keys("s")
			H.match(H.status(wt), "A  f.txt")
			H.eq(H.status(root), " M a.lua", "main worktree untouched")
			H.keys("gf")
			H.eq(vim.fn.expand("%:p"), wt .. "/f.txt")
			H.C.open()
			vim.cmd("Changes worktree " .. root)
			H.wait()
			H.eq(H.panel_lines(), { " Changes (1)", "   M  a.lua" })
			H.git(root, "worktree", "remove", "--force", wt)
		end,
	},

	{
		"single worktree is reported",
		function()
			local root = H.repo()
			H.open(root)
			H.keys("w")
			H.truthy(H.note("only one worktree"))
		end,
	},
}
