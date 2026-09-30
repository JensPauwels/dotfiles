local H = require("helpers")

local function wait_blame()
	vim.wait(3000, function()
		return H.blame_text() ~= nil
	end, 20)
	return H.blame_text()
end

return {
	{
		"committed line shows author, age and summary",
		function()
			local root = H.repo()
			H.dirty(root)
			H.open(root)
			H.view("a%.lua")
			H.cursor(5)
			vim.cmd("doautocmd CursorMoved")
			H.match(wait_blame(), "^You, .* • init$")
		end,
	},

	{
		"uncommitted line says so",
		function()
			local root = H.repo()
			H.dirty(root)
			H.open(root)
			H.view("a%.lua")
			H.cursor(19)
			vim.cmd("doautocmd CursorMoved")
			H.eq(wait_blame(), "Not committed yet")
			H.view("new%.txt")
			H.cursor(1)
			vim.cmd("doautocmd CursorMoved")
			H.eq(wait_blame(), "Not committed yet")
		end,
	},

	{
		"range mode with two refs blames the new commit",
		function()
			local root = H.repo()
			H.git(root, "checkout", "-q", "-b", "feature")
			H.write(root, "a.lua", "changed\n")
			H.git(root, "commit", "-q", "-am", "feature commit")
			H.open(root)
			H.C.diff("main", "feature")
			H.wait()
			H.view("a%.lua")
			H.cursor(1)
			vim.cmd("doautocmd CursorMoved")
			H.match(wait_blame(), "feature commit$")
		end,
	},

	{
		"blame can be turned off",
		function()
			local root = H.repo()
			H.dirty(root)
			H.C.config.blame = false
			H.open(root)
			H.view("a%.lua")
			H.cursor(5)
			vim.cmd("doautocmd CursorMoved")
			vim.wait(200)
			H.eq(H.blame_text(), nil)
			H.C.config.blame = true
		end,
	},
}
