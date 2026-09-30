local H = require("helpers")

return {
	{
		"c commits what is staged",
		function()
			local root = H.repo()
			H.dirty(root)
			H.open(root)
			H.ui_input("my commit message")
			H.keys("c")
			H.eq(vim.trim(H.git(root, "log", "-1", "--format=%s")), "my commit message")
			H.truthy(not H.status(root):find("s.txt"))
			H.eq(H.panel_lines()[1], " Changes (4)")
			H.truthy(H.note("Committed: my commit message"))
		end,
	},

	{
		"c with nothing staged warns",
		function()
			local root = H.repo()
			H.write(root, "a.lua", "x\n")
			H.open(root)
			H.keys("c")
			H.truthy(H.note("Nothing staged"))
		end,
	},

	{
		"an empty message aborts",
		function()
			local root = H.repo()
			H.dirty(root)
			H.open(root)
			H.ui_input("")
			H.keys("c")
			H.eq(vim.trim(H.git(root, "log", "-1", "--format=%s")), "init")
		end,
	},
}
