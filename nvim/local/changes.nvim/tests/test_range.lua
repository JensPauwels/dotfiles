local H = require("helpers")

local function feature_repo()
	local root = H.repo()
	H.git(root, "checkout", "-q", "-b", "feature")
	H.write(root, "a.lua", "line1 on feature\n" .. H.read(root, "a.lua"):gsub("^line1\n", ""))
	H.write(root, "f.txt", "feature file\n")
	H.git(root, "add", "-A")
	H.git(root, "commit", "-q", "-m", "feature work")
	H.git(root, "checkout", "-q", "main")
	H.write(root, "b.tf", "main moved on\n")
	H.git(root, "commit", "-q", "-am", "main work")
	H.git(root, "checkout", "-q", "feature")
	return root
end

return {
	{
		":Changes diff <ref> shows the branch against its merge base plus the worktree",
		function()
			local root = feature_repo()
			H.write(root, "s.txt", "uncommitted on feature\n")
			H.write(root, "u.txt", "untracked\n")
			H.open(root)
			H.C.diff("main")
			H.wait()
			H.eq(
				H.panel_lines(),
				{ " main..working tree (4)", "   M  a.lua", "   A  f.txt", "   M  s.txt", "   ?  u.txt" }
			)
			H.view("a%.lua")
			H.eq(H.marks()[1].del, { "line1" })
			H.match(vim.wo[0].winbar, "%(Working Tree%)")
			H.view("u%.txt")
			H.eq(H.view_lines(), { "untracked" })
		end,
	},

	{
		"two refs compare commits",
		function()
			local root = feature_repo()
			H.open(root)
			vim.cmd("Changes diff main feature")
			H.wait()
			H.eq(H.panel_lines(), { " main..feature (3)", "   M  a.lua", "   M  b.tf", "   A  f.txt" })
			H.view("b%.tf")
			H.eq(H.marks()[1].del, { "main moved on" })
			H.match(vim.wo[0].winbar, "%(feature%)")
		end,
	},

	{
		"staging is refused in range mode",
		function()
			local root = feature_repo()
			H.open(root)
			H.C.diff("main")
			H.wait()
			H.view("a%.lua")
			H.keys("s")
			H.truthy(H.note("only work on working changes"))
			H.eq(H.status(root), "")
		end,
	},

	{
		"b picker switches to a branch and back",
		function()
			local root = feature_repo()
			H.write(root, "s.txt", "dirty\n")
			H.open(root)
			H.ui_select("main")
			H.keys("b")
			H.eq(H.state().mode.kind, "range")
			H.eq(H.panel_lines()[1], " main..working tree (3)")
			H.ui_select("Working changes")
			H.keys("b")
			H.eq(H.state().mode.kind, "status")
			H.eq(H.panel_lines(), { " Changes (1)", "   M  s.txt" })
		end,
	},

	{
		"unknown ref reports an error",
		function()
			local root = feature_repo()
			H.open(root)
			H.C.diff("nope")
			H.wait()
			H.truthy(H.note("merge base"))
			H.eq(H.state().mode.kind, "status")
		end,
	},
}
