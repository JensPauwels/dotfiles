local H = require("helpers")

return {
	{
		"stage an insertion hunk",
		function()
			local root = H.repo()
			H.dirty(root)
			H.open(root)
			H.view("a%.lua")
			H.cursor(19)
			H.keys("s")
			H.match(
				H.git(root, "diff", "--cached", "-U0", "--", "a.lua"),
				"@@ %-19,0 %+20,2 @@[^\n]*\n%+inserted A\n%+inserted B"
			)
			H.match(vim.wo[0].winbar, "2 changes")
			H.eq(H.panel_lines()[1], " Staged (2)")
		end,
	},

	{
		"stage a pure deletion and a modification",
		function()
			local root = H.repo()
			H.dirty(root)
			H.open(root)
			H.view("a%.lua")
			H.cursor(9)
			H.keys("s")
			H.match(H.git(root, "diff", "--cached", "-U0", "--", "a.lua"), "@@ %-10 %+9,0 @@[^\n]*\n%-line10")
			H.cursor(2)
			H.keys("s")
			H.match(H.git(root, "diff", "--cached", "-U0", "--", "a.lua"), "%-line2\n%+line2 changed")
		end,
	},

	{
		"unstage hunks from the Staged group",
		function()
			local root = H.repo()
			H.dirty(root)
			H.git(root, "add", "a.lua")
			H.open(root)
			H.view("a%.lua", true)
			H.match(vim.wo[0].winbar, "%(Index%)  ·  3 changes")
			H.cursor(19) -- the insertion (index has no line10, so it starts at 19)
			H.keys("s")
			local cached = H.git(root, "diff", "--cached", "-U0", "--", "a.lua")
			H.truthy(not cached:find("inserted"), "insertion left the index")
			H.match(cached, "%-line10")
			H.view("a%.lua", true)
			H.cursor(9)
			H.keys("s")
			H.match(H.git(root, "diff", "--cached", "-U0", "--", "a.lua"), "^diff.-%-line2\n%+line2 changed\n$")
		end,
	},

	{
		"untracked and deleted files stage as a whole",
		function()
			local root = H.repo()
			H.dirty(root)
			H.open(root)
			H.view("new%.txt")
			H.keys("s")
			H.view("gone%.txt")
			H.keys("s")
			H.match(H.status(root), "A  new.txt")
			H.match(H.status(root), "D  gone.txt")
		end,
	},

	{
		"panel s stages and unstages whole files",
		function()
			local root = H.repo()
			H.dirty(root)
			H.open(root)
			H.select("b%.tf")
			H.keys("s")
			H.match(H.status(root), "M  b.tf")
			H.select("s%.txt", true)
			H.keys("s")
			H.match(H.status(root), " M s.txt")
		end,
	},

	{
		"discard a hunk writes the file",
		function()
			local root = H.repo()
			H.dirty(root)
			H.open(root)
			H.view("b%.tf")
			H.keys("X")
			H.eq(H.read(root, "b.tf"), "hostnames = [var.oauth2_redirect_domain]\n\tindented\tline\n")
			H.truthy(not H.status(root):find("b.tf"))
		end,
	},

	{
		"discard a hunk in a loaded buffer updates and saves it",
		function()
			local root = H.repo()
			H.dirty(root)
			vim.cmd("edit " .. root .. "/a.lua")
			local buf = vim.api.nvim_get_current_buf()
			H.open(root)
			H.view("a%.lua")
			H.cursor(2)
			H.keys("X")
			H.eq(vim.api.nvim_buf_get_lines(buf, 1, 2, false), { "line2" })
			H.eq(vim.bo[buf].modified, false)
			H.eq(vim.split(H.read(root, "a.lua"), "\n")[2], "line2")
		end,
	},

	{
		"panel X discards a file and deletes an untracked one",
		function()
			local root = H.repo()
			H.dirty(root)
			H.open(root)
			H.select("a%.lua")
			H.keys("X")
			H.truthy(not H.status(root):find("a.lua"))
			H.select("new%.txt")
			H.keys("X")
			H.eq(H.read(root, "new.txt"), nil)
		end,
	},

	{
		"staged changes are never discarded",
		function()
			local root = H.repo()
			H.dirty(root)
			H.open(root)
			H.view("s%.txt", true)
			H.keys("X")
			H.truthy(H.note("Unstage with s first"))
			H.match(H.status(root), "M  s.txt")
		end,
	},

	{
		"s outside a change warns",
		function()
			local root = H.repo()
			H.dirty(root)
			H.open(root)
			H.view("a%.lua")
			H.cursor(5)
			H.keys("s")
			H.truthy(H.note("No change under the cursor"))
		end,
	},
}
