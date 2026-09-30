local H = require("helpers")

local function with_remote(root)
	local remote = root .. "-remote.git"
	H.git(root, "init", "-q", "--bare", remote)
	H.git(root, "remote", "add", "origin", remote)
	return remote
end

local function header()
	return vim.wo[H.state().panel.win].winbar
end

return {
	{
		"first push sets the upstream after confirming",
		function()
			local root = H.repo()
			local remote = with_remote(root)
			H.open(root)
			H.match(header(), "main  %(no upstream%)")
			H.keys("P")
			H.wait()
			H.eq(vim.trim(H.git(root, "rev-parse", "--abbrev-ref", "@{upstream}")), "origin/main")
			H.eq(vim.trim(H.git(remote, "rev-parse", "main")), vim.trim(H.git(root, "rev-parse", "HEAD")))
			H.match(header(), "main  ↑0 ↓0")
			H.truthy(H.note("^Pushed main"))
		end,
	},

	{
		"header counts commits ahead and P pushes them",
		function()
			local root = H.repo()
			local remote = with_remote(root)
			H.git(root, "push", "-q", "-u", "origin", "main")
			H.write(root, "a.lua", "x\n")
			H.git(root, "commit", "-q", "-am", "local work")
			H.open(root)
			H.match(header(), "↑1 ↓0")
			H.keys("P")
			H.wait()
			H.match(header(), "↑0 ↓0")
			H.eq(vim.trim(H.git(remote, "log", "-1", "--format=%s", "main")), "local work")
		end,
	},

	{
		"declining the upstream prompt pushes nothing",
		function()
			local root = H.repo()
			local remote = with_remote(root)
			H.open(root)
			vim.fn.confirm = function()
				return 2
			end
			H.keys("P")
			H.wait()
			H.eq(vim.trim(H.git(remote, "branch", "--list")), "")
		end,
	},

	{
		"a rejected push reports the error",
		function()
			local root = H.repo()
			local remote = with_remote(root)
			H.git(root, "push", "-q", "-u", "origin", "main")
			-- move the remote ahead through a second clone
			local other = root .. "-other"
			H.git(root, "clone", "-q", remote, other)
			H.git(other, "config", "user.email", "o@example.com")
			H.git(other, "config", "user.name", "Other")
			H.write(other, "b.tf", "remote change\n")
			H.git(other, "commit", "-q", "-am", "remote work")
			H.git(other, "push", "-q")
			H.write(root, "a.lua", "x\n")
			H.git(root, "commit", "-q", "-am", "local work")
			H.open(root)
			H.keys("P")
			H.wait()
			H.truthy(H.note("^Push failed"))
			H.eq(vim.trim(H.git(remote, "log", "-1", "--format=%s", "main")), "remote work")
			vim.fn.delete(other, "rf")
		end,
	},
}
