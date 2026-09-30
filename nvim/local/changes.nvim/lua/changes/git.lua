-- Thin wrappers around the git CLI. Reads that can be slow on big repos
-- (status, show, diff, blame) have async variants; small mutating commands
-- stay synchronous so their order is predictable.
local M = {}

local function command(args)
	local cmd = { "git", "--no-pager", "-c", "core.quotepath=false" }
	vim.list_extend(cmd, args)
	return cmd
end

--- @param args string[]
--- @param opts? { cwd?: string, stdin?: string }
--- @return boolean ok, string stdout, string stderr
function M.run(args, opts)
	opts = opts or {}
	local res = vim.system(command(args), { cwd = opts.cwd, stdin = opts.stdin, text = true }):wait()
	return res.code == 0, res.stdout or "", res.stderr or ""
end

--- @param args string[]
--- @param opts? { cwd?: string, stdin?: string }
--- @param cb fun(ok: boolean, stdout: string, stderr: string)
function M.run_async(args, opts, cb)
	opts = opts or {}
	vim.system(command(args), { cwd = opts.cwd, stdin = opts.stdin, text = true }, function(res)
		vim.schedule(function()
			cb(res.code == 0, res.stdout or "", res.stderr or "")
		end)
	end)
end

--- Repository root for a path (file or directory). nil when not in a repo.
--- @param path? string
--- @return string|nil
function M.root(path)
	local dir = path
	if dir == nil or dir == "" then
		dir = vim.fn.getcwd()
	end
	if vim.fn.isdirectory(dir) == 0 then
		dir = vim.fs.dirname(dir)
	end
	local ok, out = M.run({ "rev-parse", "--show-toplevel" }, { cwd = dir })
	if not ok then
		return nil
	end
	return vim.trim(out)
end

--- @class changes.Entry
--- @field path string   path relative to the repo root
--- @field status string one letter: M A D U ?
--- @field staged boolean true = index vs HEAD, false = worktree vs index

local function by_path(a, b)
	return a.path < b.path
end

--- @param out string  output of `git status --porcelain=v1 -z --no-renames`
--- @return changes.Entry[] staged, changes.Entry[] unstaged
local function parse_status(out)
	local staged, unstaged = {}, {}
	for _, item in ipairs(vim.split(out, "\0", { plain = true, trimempty = true })) do
		local x, y, path = item:sub(1, 1), item:sub(2, 2), item:sub(4)
		if x == "?" then
			unstaged[#unstaged + 1] = { path = path, status = "?", staged = false }
		elseif x == "!" then
			-- ignored, never listed without --ignored anyway
		elseif x == "U" or y == "U" or (x == "A" and y == "A") or (x == "D" and y == "D") then
			unstaged[#unstaged + 1] = { path = path, status = "U", staged = false }
		else
			if x ~= " " then
				staged[#staged + 1] = { path = path, status = x, staged = true }
			end
			if y ~= " " then
				unstaged[#unstaged + 1] = { path = path, status = y, staged = false }
			end
		end
	end
	table.sort(staged, by_path)
	table.sort(unstaged, by_path)
	return staged, unstaged
end

local status_args = { "status", "--porcelain=v1", "-z", "--untracked-files=all", "--no-renames" }

--- Changed files, split into staged and unstaged groups.
--- @param root string
--- @return changes.Entry[] staged, changes.Entry[] unstaged
function M.status(root)
	local ok, out = M.run(status_args, { cwd = root })
	if not ok then
		return {}, {}
	end
	return parse_status(out)
end

--- @param root string
--- @param cb fun(staged: changes.Entry[], unstaged: changes.Entry[])
function M.status_async(root, cb)
	M.run_async(status_args, { cwd = root }, function(ok, out)
		if not ok then
			cb({}, {})
		else
			cb(parse_status(out))
		end
	end)
end

--- Files that differ between two revisions, or between a revision and the
--- working tree when `new` is nil (untracked files included in that case).
--- Entries are marked `staged = false` and carry `range = true`.
--- @param root string
--- @param old string
--- @param new string|nil
--- @param cb fun(entries: changes.Entry[])
function M.name_status_async(root, old, new, cb)
	local args = { "diff", "--name-status", "--no-renames", "-z", old }
	if new then
		args[#args + 1] = new
	end
	M.run_async(args, { cwd = root }, function(ok, out)
		local entries = {}
		if ok then
			local parts = vim.split(out, "\0", { plain = true, trimempty = true })
			for i = 1, #parts - 1, 2 do
				entries[#entries + 1] =
					{ path = parts[i + 1], status = parts[i]:sub(1, 1), staged = false, range = true }
			end
		end
		if new then
			table.sort(entries, by_path)
			cb(entries)
			return
		end
		M.run_async({ "ls-files", "--others", "--exclude-standard", "-z" }, { cwd = root }, function(ok2, out2)
			if ok2 then
				for _, path in ipairs(vim.split(out2, "\0", { plain = true, trimempty = true })) do
					entries[#entries + 1] = { path = path, status = "?", staged = false, range = true }
				end
			end
			table.sort(entries, by_path)
			cb(entries)
		end)
	end)
end

--- Contents of `rev:path`, or nil when it does not exist there.
--- @param root string
--- @param rev string  e.g. "HEAD" or ":0" (the index)
--- @param path string
--- @return string|nil
function M.show(root, rev, path)
	local ok, out = M.run({ "show", rev .. ":" .. path }, { cwd = root })
	if not ok then
		return nil
	end
	return out
end

--- @param cb fun(text: string|nil)
function M.show_async(root, rev, path, cb)
	M.run_async({ "show", rev .. ":" .. path }, { cwd = root }, function(ok, out)
		cb(ok and out or nil)
	end)
end

--- Contents of the file on disk, or nil when missing.
--- @return string|nil
function M.read_file(root, path)
	local f = io.open(root .. "/" .. path, "rb")
	if not f then
		return nil
	end
	local s = f:read("*a")
	f:close()
	return s
end

--- @param cb fun(sha: string|nil)
function M.rev_parse_async(root, rev, cb)
	M.run_async({ "rev-parse", "--verify", "--quiet", rev .. "^{commit}" }, { cwd = root }, function(ok, out)
		cb(ok and vim.trim(out) or nil)
	end)
end

--- @param cb fun(sha: string|nil)
function M.merge_base_async(root, a, b, cb)
	M.run_async({ "merge-base", a, b }, { cwd = root }, function(ok, out)
		cb(ok and vim.trim(out) or nil)
	end)
end

--- Local and remote branch names, most recently committed first.
--- @param root string
--- @return string[]
function M.refs(root)
	local ok, out = M.run(
		{ "for-each-ref", "--format=%(refname:short)", "--sort=-committerdate", "refs/heads", "refs/remotes" },
		{ cwd = root }
	)
	if not ok then
		return {}
	end
	local refs = {}
	for _, r in ipairs(vim.split(out, "\n", { trimempty = true })) do
		if not r:match("/HEAD$") then
			refs[#refs + 1] = r
		end
	end
	return refs
end

--- @return string
function M.user_name(root)
	local _, out = M.run({ "config", "user.name" }, { cwd = root })
	return vim.trim(out)
end

--- @class changes.Blame
--- @field uncommitted boolean
--- @field author string
--- @field time integer
--- @field summary string

--- Blame one line. `opts.contents` blames that text instead of the file on
--- disk (uncommitted lines come back as `uncommitted`); `opts.rev` blames
--- the file as of that commit.
--- @param root string
--- @param path string
--- @param lnum integer
--- @param opts { contents?: string, rev?: string }
--- @param cb fun(info: changes.Blame|nil)
function M.blame_line_async(root, path, lnum, opts, cb)
	local args = { "blame", "--porcelain", "-L", lnum .. "," .. lnum }
	if opts.rev then
		args[#args + 1] = opts.rev
	elseif opts.contents then
		args[#args + 1] = "--contents"
		args[#args + 1] = "-"
	end
	args[#args + 1] = "--"
	args[#args + 1] = path
	M.run_async(args, { cwd = root, stdin = opts.contents }, function(ok, out)
		if not ok then
			-- typically "no such path in HEAD": the file is new
			cb(opts.contents and { uncommitted = true } or nil)
			return
		end
		local sha = out:match("^(%x+) ")
		if not sha then
			cb(nil)
			return
		end
		local info = {
			uncommitted = sha:match("^0+$") ~= nil,
			author = out:match("\nauthor ([^\n]*)") or "",
			time = tonumber(out:match("\nauthor%-time (%d+)")) or 0,
			summary = out:match("\nsummary ([^\n]*)") or "",
		}
		cb(info)
	end)
end

--- @param cb fun(ok: boolean, stdout: string, stderr: string)
function M.commit_async(root, message, cb)
	M.run_async({ "commit", "-q", "-F", "-" }, { cwd = root, stdin = message }, cb)
end

--- @class changes.PatchSide
--- @field start integer   1-based line the block starts at; for an empty
---                        block, the line *after which* it would sit
--- @field lines string[]
--- @field noeol boolean   block includes the file's last line and that line
---                        has no trailing newline

--- Build a zero-context unified diff for one (possibly trimmed) hunk,
--- suitable for `git apply --unidiff-zero`.
---
--- Git positions a hunk by the line number of the side it is about to
--- rewrite, so the header must describe this hunk *as if it were the only
--- change in the file*: the "+" start is derived from the "-" start when
--- applying forward, and the other way round when applying in reverse.
--- @param path string
--- @param removed changes.PatchSide
--- @param added changes.PatchSide
--- @param reverse boolean  true when the patch will be applied with --reverse
--- @return string
function M.patch(path, removed, added, reverse)
	local sa, ca, sb, cb = removed.start, #removed.lines, added.start, #added.lines
	local head_a, head_b
	if reverse then
		head_b = sb
		if ca == 0 then
			head_a = sb - 1
		elseif cb == 0 then
			head_a = sb + 1
		else
			head_a = sb
		end
	else
		head_a = sa
		if cb == 0 then
			head_b = sa - 1
		elseif ca == 0 then
			head_b = sa + 1
		else
			head_b = sa
		end
	end
	local lines = {
		"--- a/" .. path,
		"+++ b/" .. path,
		string.format("@@ -%d,%d +%d,%d @@", head_a, ca, head_b, cb),
	}
	for _, l in ipairs(removed.lines) do
		lines[#lines + 1] = "-" .. l
	end
	if removed.noeol then
		lines[#lines + 1] = "\\ No newline at end of file"
	end
	for _, l in ipairs(added.lines) do
		lines[#lines + 1] = "+" .. l
	end
	if added.noeol then
		lines[#lines + 1] = "\\ No newline at end of file"
	end
	return table.concat(lines, "\n") .. "\n"
end

--- Apply a patch to the index.
--- @param root string
--- @param patch string
--- @param reverse boolean
--- @return boolean ok, string err
function M.apply_cached(root, patch, reverse)
	local args = { "apply", "--cached", "--unidiff-zero", "--whitespace=nowarn" }
	if reverse then
		args[#args + 1] = "--reverse"
	end
	args[#args + 1] = "-"
	local ok, _, err = M.run(args, { cwd = root, stdin = patch })
	return ok, err
end

function M.stage_file(root, path)
	local ok, _, err = M.run({ "add", "--", path }, { cwd = root })
	return ok, err
end

function M.unstage_file(root, path)
	local ok, _, err = M.run({ "reset", "-q", "--", path }, { cwd = root })
	return ok, err
end

--- Throw away worktree changes of a tracked file.
function M.checkout_file(root, path)
	local ok, _, err = M.run({ "checkout", "--", path }, { cwd = root })
	return ok, err
end

--- @class changes.Worktree
--- @field path string
--- @field branch string|nil  short branch name, nil when detached
--- @field head string        abbreviated commit
--- @field current boolean

--- All worktrees of the repository that `root` belongs to, main one first.
--- @param root string
--- @return changes.Worktree[]
function M.worktrees(root)
	local ok, out = M.run({ "worktree", "list", "--porcelain" }, { cwd = root })
	local list = {}
	if not ok then
		return list
	end
	local real_root = vim.uv.fs_realpath(root) or root
	local cur
	for _, line in ipairs(vim.split(out, "\n", { plain = true })) do
		local key, value = line:match("^(%S+)%s*(.*)$")
		if key == "worktree" then
			cur = { path = value, head = "", current = false }
			list[#list + 1] = cur
		elseif cur and key == "HEAD" then
			cur.head = value:sub(1, 8)
		elseif cur and key == "branch" then
			cur.branch = value:gsub("^refs/heads/", "")
		elseif cur and key == "bare" then
			cur.bare = true
		elseif line == "" then
			cur = nil
		end
	end
	local result = {}
	for _, wt in ipairs(list) do
		if not wt.bare then
			wt.current = (vim.uv.fs_realpath(wt.path) or wt.path) == real_root
			result[#result + 1] = wt
		end
	end
	return result
end

--- Short description of what HEAD points at in `root`: branch name, or
--- "detached @ <sha>".
--- @param root string
--- @return string
function M.head_label(root)
	local ok, out = M.run({ "rev-parse", "--abbrev-ref", "HEAD" }, { cwd = root })
	local name = ok and vim.trim(out) or ""
	if name == "" or name == "HEAD" then
		local _, sha = M.run({ "rev-parse", "--short", "HEAD" }, { cwd = root })
		return "detached @ " .. vim.trim(sha)
	end
	return name
end

--- Name of the current branch, or nil when detached.
--- @return string|nil
function M.current_branch(root)
	local ok, out = M.run({ "symbolic-ref", "--short", "-q", "HEAD" }, { cwd = root })
	if not ok or vim.trim(out) == "" then
		return nil
	end
	return vim.trim(out)
end

--- @class changes.Upstream
--- @field name string   e.g. "origin/main"
--- @field ahead integer
--- @field behind integer

--- Upstream of the current branch with ahead/behind counts, nil without one.
--- @return changes.Upstream|nil
function M.upstream(root)
	local ok, name = M.run({ "rev-parse", "--abbrev-ref", "--symbolic-full-name", "@{upstream}" }, { cwd = root })
	if not ok then
		return nil
	end
	local ok2, counts = M.run({ "rev-list", "--left-right", "--count", "@{upstream}...HEAD" }, { cwd = root })
	local behind, ahead = 0, 0
	if ok2 then
		behind, ahead = counts:match("(%d+)%s+(%d+)")
	end
	return { name = vim.trim(name), ahead = tonumber(ahead) or 0, behind = tonumber(behind) or 0 }
end

--- @param args string[]  extra arguments, e.g. { "--set-upstream", "origin", "main" }
--- @param cb fun(ok: boolean, stdout: string, stderr: string)
function M.push_async(root, args, cb)
	local cmd = { "push" }
	vim.list_extend(cmd, args)
	M.run_async(cmd, { cwd = root }, cb)
end

return M
