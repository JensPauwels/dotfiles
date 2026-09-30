local H = require("helpers")

return {
	{
		"stage only the selected added line",
		function()
			local root = H.repo()
			H.dirty(root)
			H.open(root)
			H.view("a%.lua")
			H.cursor(20) -- "inserted B"
			H.keys("Vs")
			local cached = H.git(root, "diff", "--cached", "-U0", "--", "a.lua")
			H.match(cached, "@@ %-19,0 %+20 @@[^\n]*\n%+inserted B")
			H.truthy(not cached:find("inserted A"))
			H.match(H.git(root, "diff", "-U0", "--", "a.lua"), "%+inserted A\n")
		end,
	},

	{
		"selection at the top of a change includes its removed lines",
		function()
			local root = H.repo()
			H.dirty(root)
			H.open(root)
			H.view("a%.lua")
			H.cursor(2)
			H.keys("Vs")
			H.match(H.git(root, "diff", "--cached", "-U0", "--", "a.lua"), "%-line2\n%+line2 changed")
		end,
	},

	{
		"selection spanning several changes stages all of them",
		function()
			local root = H.repo()
			H.dirty(root)
			H.open(root)
			H.view("a%.lua")
			vim.cmd("normal! zR")
			H.cursor(2)
			H.keys("V18js")
			H.match(
				H.git(root, "diff", "--cached", "-U0", "--", "a.lua"),
				"%-line2\n%+line2 changed\n.-%-line10\n.-%+inserted A\n%+inserted B"
			)
			H.eq(H.status(root), "M  a.lua\n M b.tf\n D gone.txt\nM  s.txt\n?? new.txt")
		end,
	},

	{
		"unstage only the selected line from the index",
		function()
			local root = H.repo()
			H.dirty(root)
			H.git(root, "add", "a.lua")
			H.open(root)
			H.view("a%.lua", true)
			H.cursor(20) -- "inserted B" in the index version
			H.keys("Vs")
			local cached = H.git(root, "diff", "--cached", "-U0", "--", "a.lua")
			H.match(cached, "%+inserted A\n")
			H.truthy(not cached:find("inserted B"), "B left the index")
			H.match(H.git(root, "diff", "-U0", "--", "a.lua"), "%+inserted B")
		end,
	},

	{
		"discard only the selected lines",
		function()
			local root = H.repo()
			H.dirty(root)
			H.open(root)
			H.view("a%.lua")
			H.cursor(19)
			H.keys("VX")
			local lines = vim.split(H.read(root, "a.lua"), "\n")
			H.eq(lines[19], "inserted B")
			H.eq(lines[20], "line20")
		end,
	},

	{
		"discarding a selection from the top restores removed lines",
		function()
			local root = H.repo()
			H.dirty(root)
			H.open(root)
			H.view("a%.lua")
			H.cursor(2)
			H.keys("VX")
			H.eq(vim.split(H.read(root, "a.lua"), "\n")[2], "line2")
		end,
	},
}
