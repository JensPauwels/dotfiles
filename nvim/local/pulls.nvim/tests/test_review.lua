local H = require("helpers")
local R = require("pulls.review")
local api = vim.api

local function sh(cwd, ...)
	local r = vim.system({ ... }, { cwd = cwd, text = true }):wait()
	assert(r.code == 0, table.concat({ ... }, " ") .. ": " .. (r.stderr or ""))
	return vim.trim(r.stdout or "")
end

local function write(path, text)
	vim.fn.mkdir(vim.fs.dirname(path), "p")
	local f = assert(io.open(path, "wb"))
	f:write(text)
	f:close()
end

local function read(path)
	local f = io.open(path, "rb")
	if not f then
		return nil
	end
	local s = f:read("*a")
	f:close()
	return s
end

local function lines(t)
	return table.concat(t, "\n") .. "\n"
end

-- 13 lines; the pull request changes lines 2, 3 and 12, so lines 7 and 8
-- are outside every hunk.
local base_app = lines({ "a", "b", "c", "d", "e", "f", "g", "h", "i", "j", "k", "l", "m" })
local head_app = lines({ "a", "B", "C", "d", "e", "f", "g", "h", "i", "j", "k", "L", "m" })

--- A clone of acme/widgets on `main`, with the pull request's branch
--- `feature` (pushed to its origin). The current directory becomes the clone.
local function clone()
	local tmp = vim.uv.fs_realpath(vim.fn.tempname()) or vim.fn.tempname()
	vim.fn.mkdir(tmp, "p")
	tmp = vim.uv.fs_realpath(tmp)
	local bare = tmp .. "/remote/acme/widgets.git"
	vim.fn.mkdir(bare, "p")
	sh(bare, "git", "init", "-q", "--bare", "-b", "main")
	local root = tmp .. "/widgets"
	vim.fn.mkdir(root, "p")
	sh(root, "git", "init", "-q", "-b", "main")
	sh(root, "git", "config", "user.email", "t@example.com")
	sh(root, "git", "config", "user.name", "T")
	sh(root, "git", "remote", "add", "origin", bare)
	write(root .. "/src/app.lua", base_app)
	write(root .. "/docs/gone.md", "bye\n")
	sh(root, "git", "add", "-A")
	sh(root, "git", "commit", "-q", "-m", "base")
	local base = sh(root, "git", "rev-parse", "HEAD")
	sh(root, "git", "checkout", "-q", "-b", "feature")
	write(root .. "/src/app.lua", head_app)
	write(root .. "/docs/new.md", "hello\n")
	vim.fn.delete(root .. "/docs/gone.md")
	sh(root, "git", "add", "-A")
	sh(root, "git", "commit", "-q", "-m", "head")
	sh(root, "git", "push", "-q", "origin", "main", "feature", "feature:refs/pull/7/head")
	sh(root, "git", "checkout", "-q", "main")
	vim.env.PULLS_FAKE_BRANCH = "feature"
	vim.cmd("silent! %bwipe!")
	vim.cmd("cd " .. vim.fn.fnameescape(root))
	return root, base
end

local function wait()
	assert(R.wait(10000), "timed out")
end

--- Answer the next vim.ui.select with the choice whose label matches `pat`.
local function choose(pat)
	vim.ui.select = function(items, opts, cb)
		for _, it in ipairs(items) do
			if opts.format_item(it):find(pat) then
				cb(it)
				return
			end
		end
		error("no choice matching " .. pat)
	end
end

local function branch(root)
	return sh(root, "git", "rev-parse", "--abbrev-ref", "HEAD")
end

local function start(number)
	R.start(number or 7)
	wait()
	return assert(R.active(), "review did not start")
end

local function paths(s)
	local out = {}
	for _, f in ipairs(s.files) do
		out[#out + 1] = f.status .. " " .. f.path
	end
	return out
end

return {
	{
		"a clean tree is checked out straight away; files come from the merge base",
		function()
			local root, base = clone()
			local s = start()
			H.eq(branch(root), "feature")
			H.eq(s.base, base)
			H.eq(s.orig, "main")
			H.eq(paths(s), { "D docs/gone.md", "A docs/new.md", "M src/app.lua" })
			H.truthy(H.call("pr", "checkout"), "gh pr checkout ran")
			-- without snacks.nvim the files go to the quickfix list
			H.eq(#vim.fn.getqflist(), 3)
			H.eq(vim.fn.getqflist()[3].lnum, 2, "starts at the first change")
		end,
	},

	{
		"dirty tree, stash: changes come back after :PR done",
		function()
			local root = clone()
			write(root .. "/src/app.lua", "mine\n")
			write(root .. "/scratch.txt", "untracked\n")
			choose("^Stash")
			start()
			H.eq(branch(root), "feature")
			H.eq(read(root .. "/scratch.txt"), nil, "untracked files are stashed too")
			H.match(sh(root, "git", "stash", "list"), "before reviewing #7")
			R.done()
			H.eq(R.active(), nil)
			H.eq(branch(root), "main")
			H.eq(read(root .. "/src/app.lua"), "mine\n")
			H.eq(read(root .. "/scratch.txt"), "untracked\n")
			H.eq(sh(root, "git", "stash", "list"), "")
		end,
	},

	{
		"dirty tree, WIP commit: :PR done offers to undo it",
		function()
			local root, base = clone()
			write(root .. "/src/app.lua", "mine\n")
			choose("^Commit")
			vim.ui.input = function(opts, cb)
				H.eq(opts.default, "WIP")
				cb("parking")
			end
			start()
			H.eq(sh(root, "git", "log", "-1", "--format=%s", "main"), "parking")
			R.done()
			H.eq(branch(root), "main")
			H.eq(sh(root, "git", "rev-parse", "HEAD"), base, "WIP commit undone")
			H.eq(read(root .. "/src/app.lua"), "mine\n")
		end,
	},

	{
		"branch already checked out in another worktree: the head is checked out detached",
		function()
			local root, base = clone()
			local other = vim.fn.tempname()
			sh(root, "git", "worktree", "add", "-q", other, "feature")
			local s = start()
			H.eq(branch(root), "HEAD", "detached")
			H.eq(sh(root, "git", "rev-parse", "HEAD"), sh(root, "git", "rev-parse", "feature"))
			H.eq(H.call("pr", "checkout"), nil, "gh is not asked to check the branch out")
			H.eq(s.base, base)
			H.eq(#s.files, 3)
			H.truthy(H.note("checked out detached"))
			R.done()
			H.eq(branch(root), "main")
			sh(root, "git", "worktree", "remove", "--force", other)
		end,
	},

	{
		"gh reporting the worktree conflict also falls back to detached",
		function()
			local root = clone()
			local other = vim.fn.tempname()
			sh(root, "git", "worktree", "add", "-q", other, "feature")
			-- git does not know: pretend the worktree list is empty
			vim.env.PULLS_FAKE_BRANCH = "feature" -- the fake gh runs git checkout, which fails
			local real = vim.system
			vim.system = function(cmd, ...)
				if cmd[4] == "worktree" and cmd[5] == "list" then
					cmd = { "true" }
				end
				return real(cmd, ...)
			end
			local ok, err = pcall(start)
			vim.system = real
			assert(ok, err)
			H.eq(branch(root), "HEAD")
			H.truthy(H.call("pr", "checkout"))
			sh(root, "git", "worktree", "remove", "--force", other)
		end,
	},

	{
		"dirty tree, cancel: nothing happens",
		function()
			local root = clone()
			write(root .. "/src/app.lua", "mine\n")
			choose("^Cancel")
			R.start(7)
			wait()
			H.eq(R.active(), nil)
			H.eq(branch(root), "main")
			H.eq(H.call("pr", "checkout"), nil)
			H.eq(read(root .. "/src/app.lua"), "mine\n")
		end,
	},

	{
		"unsaved buffers block the checkout",
		function()
			local root = clone()
			vim.cmd.edit(root .. "/src/app.lua")
			api.nvim_buf_set_lines(0, 0, 1, false, { "unsaved" })
			R.start(7)
			wait()
			H.eq(R.active(), nil)
			H.truthy(H.note("Save or discard"))
			vim.cmd("bwipe!")
		end,
	},

	{
		"review threads are diagnostics on the real file; reply goes to the thread",
		function()
			local root = clone()
			start()
			vim.cmd.edit(root .. "/src/app.lua")
			local d = vim.diagnostic.get(0, { namespace = R._ns })
			H.eq(#d, 1, "the LEFT-side thread has no line in the new file")
			H.eq(d[1].lnum, 2)
			H.match(d[1].message, "Why 4%?")
			api.nvim_win_set_cursor(0, { 3, 0 })
			R.reply()
			H.send("because")
			wait()
			local c = H.call("api", "-X")
			H.eq(c[4], "repos/acme/widgets/pulls/7/comments/1/replies")
			H.eq(H.arg(c, "body"), "because")
		end,
	},

	{
		"comment on a line or a range of the diff; lines outside it are refused",
		function()
			local root = clone()
			start()
			vim.cmd.edit(root .. "/src/app.lua")
			R.comment(2, 3)
			H.send("hm")
			wait()
			local c = H.call("api", "-X")
			H.eq(c[4], "repos/acme/widgets/pulls/7/comments")
			H.eq(H.arg(c, "path"), "src/app.lua")
			H.eq(H.arg(c, "line"), "3")
			H.eq(H.arg(c, "start_line"), "2")
			H.eq(H.arg(c, "side"), "RIGHT")
			H.eq(H.arg(c, "commit_id"), "abc123")
			local before = #H.calls()
			R.comment(7, 7)
			H.truthy(H.note("Line 7 is not part of the diff"))
			H.eq(#H.calls(), before)
		end,
	},

	{
		"]f / [f walk the changed files; a deleted file shows its base version",
		function()
			local root = clone()
			start()
			vim.cmd("cclose")
			R.next_file(1)
			H.eq(api.nvim_buf_get_name(0), "pulls://base/docs/gone.md")
			H.eq(api.nvim_buf_get_lines(0, 0, -1, false)[1], "bye")
			R.next_file(1)
			H.eq(api.nvim_buf_get_name(0), root .. "/docs/new.md")
			R.next_file(1)
			H.eq(api.nvim_buf_get_name(0), root .. "/src/app.lua")
			H.eq(api.nvim_win_get_cursor(0)[1], 2)
			R.next_file(1)
			H.eq(api.nvim_buf_get_name(0), "pulls://base/docs/gone.md", "wraps around")
			R.next_file(-1)
			H.eq(api.nvim_buf_get_name(0), root .. "/src/app.lua")
		end,
	},

	{
		"toggle viewed marks the current file on GitHub",
		function()
			local root = clone()
			local s = start()
			vim.cmd.edit(root .. "/src/app.lua")
			R.toggle_viewed()
			wait()
			H.eq(s.viewed["src/app.lua"], true)
			local c = H.call("api", "graphql")
			H.match(H.arg(c, "query"), "markFileAsViewed")
			H.eq(H.arg(c, "path"), "src/app.lua")
			H.eq(R.status(), " #7 2/3")
		end,
	},

	{
		":PR done refuses while the PR branch has uncommitted changes",
		function()
			local root = clone()
			start()
			write(root .. "/src/app.lua", "edited during review\n")
			R.done()
			H.truthy(R.active())
			H.eq(branch(root), "feature")
			H.truthy(H.note("commit or stash them first"))
		end,
	},

	{
		"a review survives a restart: <leader>n picks it up and :PR done still restores",
		function()
			local root = clone()
			write(root .. "/src/app.lua", "mine\n")
			choose("^Stash")
			start()
			R._reset() -- as if Neovim restarted
			H.truthy(R.tree())
			wait()
			local s = assert(R.active())
			H.eq(s.number, 7)
			H.eq(#s.files, 3)
			R.done()
			H.eq(branch(root), "main")
			H.eq(read(root .. "/src/app.lua"), "mine\n")
		end,
	},

	{
		"<leader>n falls through to the explorer when nothing is being reviewed",
		function()
			clone()
			H.eq(R.tree(), false)
		end,
	},

	{
		"the sidebar is a tree: directories first, single-directory chains folded",
		function()
			local root = clone()
			local s = start()
			local out = {}
			for _, it in ipairs(R.items()) do
				local depth, n = 0, it.parent
				while n do
					depth, n = depth + 1, n.parent
				end
				out[#out + 1] = string.rep("  ", depth) .. (it.dir and (it.label .. "/") or (it.status .. " " .. vim.fs.basename(it.path)))
			end
			H.eq(out, { "#7 Add widgets/", "  docs/", "    D gone.md", "    A new.md", "  src/", "    M app.lua" })
			H.eq(paths(s), { "D docs/gone.md", "A docs/new.md", "M src/app.lua" }, "]f follows the tree")
			local folded = R.build_tree({ { path = "packages/modules/vetting/src/a.ts" }, { path = "README.md" } })
			H.eq(folded.entries[1].label, "packages/modules/vetting/src")
			H.eq(folded.entries[2].file.path, "README.md")
		end,
	},

	{
		"dependency changes offer an install, then the language servers restart",
		function()
			local root = clone()
			-- the pull request touches a package.json
			sh(root, "git", "checkout", "-q", "feature")
			write(root .. "/package.json", "{}\n")
			write(root .. "/bun.lock", "{}\n")
			sh(root, "git", "add", "-A")
			sh(root, "git", "commit", "-q", "-m", "deps")
			sh(root, "git", "push", "-q", "origin", "feature")
			sh(root, "git", "checkout", "-q", "main")
			local orig = R.install_cmd
			R.install_cmd = function()
				return { "sh", "-c", "echo yes > installed" }
			end
			local asked
			vim.fn.confirm = function(msg)
				asked = msg
				return 1
			end
			local ok, err = pcall(start)
			R.wait()
			R.install_cmd = orig
			assert(ok, err)
			H.match(asked, "#7 changes dependencies")
			H.eq(read(root .. "/installed"), "yes\n")
			H.truthy(H.note("done"))
		end,
	},

	{
		"change starts: added, changed and removed-only blocks",
		function()
			local f = H.patch.parse(table.concat({
				"diff --git a/x b/x",
				"--- a/x",
				"+++ b/x",
				"@@ -1,8 +1,7 @@",
				" a",
				"-b",
				"+B",
				" c",
				"-d",
				" e",
				" f",
				"+g",
				" h",
				"",
			}, "\n"))[1]
			H.eq(R.change_starts(f), { 2, 4, 6 })
		end,
	},

	{
		"n / N walk the changes across files; while searching they search",
		function()
			local root = clone()
			start()
			vim.cmd("cclose")
			vim.cmd.edit(root .. "/src/app.lua")
			api.nvim_win_set_cursor(0, { 1, 0 })
			vim.cmd("nohlsearch")
			vim.v.hlsearch = 0
			H.keys("n")
			H.eq(api.nvim_win_get_cursor(0)[1], 2)
			H.keys("n")
			H.eq(api.nvim_win_get_cursor(0)[1], 12)
			H.keys("n")
			H.eq(api.nvim_buf_get_name(0), "pulls://base/docs/gone.md", "wraps to the first file")
			H.keys("n")
			H.eq(api.nvim_buf_get_name(0), root .. "/docs/new.md")
			H.keys("N")
			H.eq(api.nvim_buf_get_name(0), "pulls://base/docs/gone.md")
			H.keys("N")
			H.eq(api.nvim_buf_get_name(0), root .. "/src/app.lua")
			H.eq(api.nvim_win_get_cursor(0)[1], 12, "previous file starts at its last change")
			H.keys("N")
			H.eq(api.nvim_win_get_cursor(0)[1], 2)
			-- with a highlighted search, n searches
			api.nvim_win_set_cursor(0, { 1, 0 })
			vim.fn.setreg("/", "k")
			vim.v.hlsearch = 1
			H.keys("n")
			H.eq(api.nvim_win_get_cursor(0)[1], 11)
		end,
	},

	{
		"R picks up new commits pushed to the pull request",
		function()
			local root = clone()
			local s = start()
			H.eq(#s.files, 3)
			-- someone pushes a new commit to the branch
			local other = vim.fn.tempname()
			sh(vim.fn.getcwd(), "git", "clone", "-q", "-b", "feature", sh(root, "git", "remote", "get-url", "origin"), other)
			sh(other, "git", "config", "user.email", "t@example.com")
			sh(other, "git", "config", "user.name", "T")
			write(other .. "/src/extra.lua", "new\n")
			sh(other, "git", "add", "-A")
			sh(other, "git", "commit", "-q", "-m", "more")
			sh(other, "git", "push", "-q", "origin", "feature")
			local pushed = sh(other, "git", "rev-parse", "HEAD")
			H.keys("R")
			wait()
			H.eq(sh(root, "git", "rev-parse", "HEAD"), pushed)
			H.eq(paths(s), { "D docs/gone.md", "A docs/new.md", "M src/app.lua", "A src/extra.lua" })
			H.truthy(H.note("#7: new commits, 4 files") or H.note("4 files"))
			H.eq(R.active(), s)
		end,
	},

	{
		"R refuses to move a dirty checkout",
		function()
			local root = clone()
			start()
			write(root .. "/src/app.lua", "edited\n")
			R.refresh()
			wait()
			H.truthy(H.note("uncommitted changes here"))
			H.eq(read(root .. "/src/app.lua"), "edited\n")
		end,
	},

	{
		"keymaps exist only while reviewing",
		function()
			clone()
			start()
			H.truthy(vim.fn.maparg("]f", "n") ~= "")
			H.truthy(vim.fn.maparg("<leader>pc", "x") ~= "")
			H.truthy(vim.fn.maparg("n", "n") ~= "")
			R.done()
			H.eq(vim.fn.maparg("]f", "n"), "")
			H.eq(vim.fn.maparg("n", "n"), "", "n searches again")
		end,
	},
}
