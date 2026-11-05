-- Review a pull request in your own checkout: check its branch out (parking
-- your uncommitted work in a stash or a WIP commit first), list the changed
-- files in a sidebar that takes the place of the file explorer, show the
-- changes as gitsigns hunks against the merge base and review threads as
-- diagnostics. Files are ordinary buffers, so splits, gd and every other
-- LSP feature work as usual. :PR done puts everything back.
local api = vim.api
local gh = require("pulls.gh")
local P = require("pulls.patch")
local compose = require("pulls.compose")

local M = {}

--- Where sessions are kept so :PR done still works after a restart.
M.file = vim.fn.stdpath("data") .. "/pulls/review.json"

M.source = "pulls_review"

local ns = api.nvim_create_namespace("pulls.review")
local group = api.nvim_create_augroup("pulls.review", { clear = true })

--- @type table|nil the active review
local S = nil
local pending = 0

local function notify(msg, level)
	vim.notify(msg, level or vim.log.levels.INFO, { title = "pulls" })
end

local function realpath(p)
	return vim.uv.fs_realpath(p) or p
end

--- Run git in `root` and wait for it; local and fast, so synchronous.
local function git(root, args)
	local cmd = { "git", "-C", root }
	vim.list_extend(cmd, args)
	local r = vim.system(cmd, { text = true }):wait()
	return r.code == 0, vim.trim(r.stdout or ""), vim.trim(r.stderr or "")
end

--- Async git for network work (fetch).
local function git_async(root, args, cb)
	local cmd = { "git", "-C", root }
	vim.list_extend(cmd, args)
	pending = pending + 1
	vim.system(cmd, { text = true }, function(r)
		vim.schedule(function()
			pending = pending - 1
			cb(r.code == 0, vim.trim(r.stdout or ""), vim.trim(r.stderr or ""))
		end)
	end)
end

--- Wrap a gh callback so tests can wait for it.
local function tracked(cb)
	pending = pending + 1
	return function(...)
		pending = pending - 1
		cb(...)
	end
end

local function toplevel(dir)
	local ok, out = git(dir, { "rev-parse", "--show-toplevel" })
	return ok and realpath(out) or nil
end

local function current_branch(root)
	local ok, out = git(root, { "symbolic-ref", "--short", "-q", "HEAD" })
	if ok and out ~= "" then
		return out
	end
	local _, sha = git(root, { "rev-parse", "HEAD" })
	return sha
end

local function dirty(root)
	local _, out = git(root, { "status", "--porcelain" })
	return out ~= ""
end

local function modified_buffers()
	local out = {}
	for _, b in ipairs(api.nvim_list_bufs()) do
		if vim.bo[b].modified and vim.bo[b].buftype == "" and api.nvim_buf_get_name(b) ~= "" then
			out[#out + 1] = vim.fn.fnamemodify(api.nvim_buf_get_name(b), ":~:.")
		end
	end
	return out
end

--- Remote of `root` that points at `repo` (owner/name), or its URL.
function M.remote_for(root, repo)
	local _, out = git(root, { "remote", "-v" })
	for name, url in out:gmatch("(%S+)%s+(%S+)%s+%(fetch%)") do
		local slug = url:gsub("%.git$", ""):match("[:/]([^/:]+/[^/]+)$")
		if slug and slug:lower() == repo:lower() then
			return name
		end
	end
	return "https://github.com/" .. repo .. ".git"
end

--- owner/name on GitHub of the clone at `root` (origin first), from its
--- remotes, without asking GitHub. nil when none points at github.com.
function M.repo_of(root)
	local ok, out = git(root, { "remote", "-v" })
	if not ok then
		return nil
	end
	local found
	for name, url in out:gmatch("(%S+)%s+(%S+)%s+%(fetch%)") do
		local slug = url:match("github%.com[:/]([^/]+/[^/]+)$")
		if slug then
			slug = slug:gsub("%.git$", "")
			if name == "origin" then
				return slug
			end
			found = found or slug
		end
	end
	return found
end

-- Sessions on disk, keyed by repository root -------------------------------

local function read_sessions()
	local f = io.open(M.file, "rb")
	if not f then
		return {}
	end
	local ok, d = pcall(vim.json.decode, f:read("*a"))
	f:close()
	return ok and type(d) == "table" and d or {}
end

local function write_sessions(d)
	vim.fn.mkdir(vim.fs.dirname(M.file), "p")
	local f = io.open(M.file, "wb")
	if f then
		f:write(vim.json.encode(d))
		f:close()
	end
end

local function save(s)
	local d = read_sessions()
	d[s.root] = s and {
		repo = s.repo,
		number = s.number,
		orig = s.orig,
		stash = s.stash,
		wip = s.wip,
	} or nil
	write_sessions(d)
end

local function forget(root)
	local d = read_sessions()
	d[root] = nil
	write_sessions(d)
end

-- Parking your own work ----------------------------------------------------

--- Ask what to do with uncommitted changes; cb(parked) with
--- { stash = message } or { wip = { branch, sha } } or {} when clean.
--- cb(nil) when cancelled.
local function park(root, number, cb)
	if not dirty(root) then
		cb({})
		return
	end
	local branch = current_branch(root)
	local choices = {
		{ key = "stash", label = "Stash them (put back by :PR done)" },
		{ key = "commit", label = "Commit them as WIP on " .. branch },
		{ key = "cancel", label = "Cancel" },
	}
	vim.ui.select(choices, {
		prompt = "You have uncommitted changes on " .. branch,
		format_item = function(c)
			return c.label
		end,
	}, function(choice)
		if not choice or choice.key == "cancel" then
			cb(nil)
			return
		end
		if choice.key == "stash" then
			local msg = string.format("pulls.nvim: before reviewing #%d", number)
			local ok, _, err = git(root, { "stash", "push", "--include-untracked", "-m", msg })
			if not ok then
				notify("git stash failed: " .. err, vim.log.levels.ERROR)
				cb(nil)
				return
			end
			cb({ stash = msg })
			return
		end
		vim.ui.input({ prompt = "Commit message: ", default = "WIP" }, function(msg)
			if not msg or vim.trim(msg) == "" then
				cb(nil)
				return
			end
			git(root, { "add", "-A" })
			local ok, _, err = git(root, { "commit", "--no-verify", "-m", msg })
			if not ok then
				notify("git commit failed: " .. err, vim.log.levels.ERROR)
				cb(nil)
				return
			end
			local _, sha = git(root, { "rev-parse", "HEAD" })
			cb({ wip = { branch = branch, sha = sha } })
		end)
	end)
end

--- stash@{n} of our stash, or nil.
local function find_stash(root, msg)
	local _, out = git(root, { "stash", "list", "--format=%gd%x09%s" })
	for line in out:gmatch("[^\n]+") do
		local ref, subject = line:match("^(%S+)\t(.*)$")
		if subject and subject:find(msg, 1, true) then
			return ref
		end
	end
	return nil
end

--- Put the parked work back: pop the stash, or offer to undo the WIP commit.
local function unpark(root, parked)
	if parked.stash then
		local ref = find_stash(root, parked.stash)
		if not ref then
			notify("Could not find your stash (" .. parked.stash .. ")", vim.log.levels.WARN)
		else
			local ok, _, err = git(root, { "stash", "pop", ref })
			if not ok then
				notify("git stash pop failed, your changes are still in " .. ref .. ":\n" .. err, vim.log.levels.ERROR)
				return false
			end
		end
	elseif parked.wip then
		local _, head = git(root, { "rev-parse", "HEAD" })
		if head == parked.wip.sha then
			local answer = vim.fn.confirm(
				"Undo your WIP commit on " .. parked.wip.branch .. "? Its changes stay in the working tree.",
				"&Yes\n&No",
				1
			)
			if answer == 1 then
				git(root, { "reset", "HEAD~" })
			end
		end
	end
	return true
end

-- Changed files ------------------------------------------------------------

local function rel(path)
	if not S then
		return nil
	end
	local deleted = path:match("^pulls://base/(.+)$")
	if deleted then
		return deleted
	end
	return vim.fs.relpath(S.root, realpath(path))
end

--- Thread text for a diagnostic: every comment, oldest first.
local function thread_message(t)
	local parts = {}
	for _, c in ipairs(t.comments) do
		parts[#parts + 1] = "@" .. c.author .. " (" .. P.ago(c.created_at) .. "):\n" .. vim.trim(c.body)
	end
	return table.concat(parts, "\n\n")
end

--- Review threads of the file as diagnostics on the buffer.
local function decorate(buf)
	if not S or not api.nvim_buf_is_loaded(buf) then
		return
	end
	local path = rel(api.nvim_buf_get_name(buf))
	if not path then
		return
	end
	local diags = {}
	for _, t in ipairs(S.threads[path] or {}) do
		if t.line and t.side == "RIGHT" then
			diags[#diags + 1] = {
				lnum = t.line - 1,
				col = 0,
				severity = vim.diagnostic.severity.INFO,
				source = "PR #" .. S.number,
				message = thread_message(t),
				user_data = { thread = t.id },
			}
		end
	end
	vim.diagnostic.set(ns, buf, diags)
end

local function decorate_all()
	for _, b in ipairs(api.nvim_list_bufs()) do
		decorate(b)
	end
end

--- First changed line of a file (new side), for jumping to it.
local function first_change(f)
	for _, l in ipairs(f.lines) do
		if l.kind == "+" then
			return l.new
		end
	end
	for _, l in ipairs(f.lines) do
		if l.new then
			return l.new
		end
	end
	return 1
end

--- Line (new side) where each block of changes starts. A block of only
--- removed lines starts at the line that follows it. Files without any
--- (binary, deleted, renamed only) get line 1.
function M.change_starts(f)
	local out, last_new, in_block = {}, 0, false
	for _, l in ipairs(f.lines) do
		if l.kind == "+" or l.kind == "-" then
			if not in_block then
				local at = l.kind == "+" and l.new or (last_new + 1)
				if out[#out] ~= at then
					out[#out + 1] = at
				end
				in_block = true
			end
		else
			in_block = false
		end
		if l.new then
			last_new = l.new
		end
	end
	if f.status == "D" or #out == 0 then
		out = { 1 }
	end
	return out
end

local function index_files(diff)
	S.files, S.by_path = {}, {}
	for _, f in ipairs(P.parse(diff)) do
		f.first = first_change(f)
		f.changes = M.change_starts(f)
		f.commentable = {}
		for _, l in ipairs(f.lines) do
			if l.new and l.kind ~= "-" and l.kind ~= "@" then
				f.commentable[l.new] = true
			end
		end
		S.files[#S.files + 1] = f
		S.by_path[f.path] = f
	end
	S.tree = M.build_tree(S.files)
	-- ]f / [f walk the files in the order the sidebar shows them
	S.files = {}
	local function walk(n)
		for _, e in ipairs(n.entries) do
			if e.dir then
				walk(e.dir)
			else
				S.files[#S.files + 1] = e.file
			end
		end
	end
	walk(S.tree)
end

--- Directory tree of changed files, like the explorer: directories first,
--- then files, each sorted; chains of single directories are folded into
--- one entry ("packages/modules/vetting").
function M.build_tree(files)
	local root = { dirs = {}, files = {} }
	for _, f in ipairs(files) do
		local node = root
		local parts = vim.split(f.path, "/", { plain = true })
		for i = 1, #parts - 1 do
			node.dirs[parts[i]] = node.dirs[parts[i]] or { dirs = {}, files = {} }
			node = node.dirs[parts[i]]
		end
		table.insert(node.files, f)
	end
	local function finish(node, prefix)
		node.entries = {}
		local names = vim.tbl_keys(node.dirs)
		table.sort(names)
		for _, name in ipairs(names) do
			local d, label = node.dirs[name], name
			while #d.files == 0 and vim.tbl_count(d.dirs) == 1 do
				local k, child = next(d.dirs)
				label, d = label .. "/" .. k, child
			end
			local path = prefix .. label
			finish(d, path .. "/")
			table.insert(node.entries, { dir = d, label = label, path = path })
		end
		table.sort(node.files, function(a, b)
			return a.path < b.path
		end)
		for _, f in ipairs(node.files) do
			table.insert(node.entries, { file = f })
		end
	end
	finish(root, "")
	return root
end

-- The sidebar --------------------------------------------------------------


function M.items()
	if not S or not S.tree then
		return {}
	end
	local out = {}
	local top = {
		dir = true,
		top = true,
		label = string.format("#%d %s", S.number, S.title or ""),
		text = "",
		file = S.root,
	}
	out[1] = top
	local function threads_of(path)
		local n = 0
		for _, t in ipairs(S.threads[path] or {}) do
			if not t.outdated then
				n = n + 1
			end
		end
		return n
	end
	local function walk(node, parent)
		for i, e in ipairs(node.entries) do
			local last = i == #node.entries
			if e.dir then
				local item = { dir = true, label = e.label, text = e.path, file = S.root .. "/" .. e.path, parent = parent, last = last }
				out[#out + 1] = item
				walk(e.dir, item)
			else
				local f = e.file
				out[#out + 1] = {
					text = f.path,
					file = S.root .. "/" .. f.path,
					path = f.path,
					status = f.status,
					viewed = S.viewed[f.path] or false,
					additions = f.additions,
					deletions = f.deletions,
					threads = threads_of(f.path),
					first = f.first,
					parent = parent,
					last = last,
				}
			end
		end
	end
	walk(S.tree, top)
	for i, it in ipairs(out) do
		it.idx = i
	end
	return out
end

local function format(item, picker)
	local ret = vim.list_extend({}, Snacks.picker.format.tree(item, picker))
	if item.dir then
		local icons = picker.opts.icons.files or {}
		ret[#ret + 1] = { (item.top and "" or (icons.dir_open or "")) .. " ", "SnacksPickerDirectory" }
		ret[#ret + 1] = { item.label, item.top and "PullsTitle" or "SnacksPickerDirectory" }
		return ret
	end
	ret[#ret + 1] = { item.viewed and "✓ " or "  ", "PullsViewed" }
	ret[#ret + 1] = { item.status .. " ", "PullsStatus" .. item.status }
	vim.list_extend(ret, Snacks.picker.format.filename(item, picker))
	if item.additions > 0 then
		ret[#ret + 1] = { "+" .. item.additions .. " ", "PullsStatusA" }
	end
	if item.deletions > 0 then
		ret[#ret + 1] = { "-" .. item.deletions .. " ", "PullsStatusD" }
	end
	if item.threads > 0 then
		ret[#ret + 1] = { "󰆉 " .. item.threads, "PullsDim" }
	end
	return ret
end

local function has_snacks()
	return rawget(_G, "Snacks") ~= nil and Snacks.picker ~= nil
end

local function tree_picker()
	return has_snacks() and Snacks.picker.get({ source = M.source })[1] or nil
end

local function refresh_tree()
	local p = tree_picker()
	if p then
		p.opts.items = M.items()
		p.list:set_target() -- keep the cursor and scroll where they are
		p:find({ refresh = true })
	end
	vim.cmd.redrawstatus()
end

--- Put the sidebar's cursor on the file shown in the current window.
local function follow()
	local p = tree_picker()
	if not p then
		return
	end
	local buf = api.nvim_get_current_buf()
	if vim.bo[buf].filetype:match("^snacks_picker") then
		-- in the sidebar itself: follow the window files open in
		if not (p.main and api.nvim_win_is_valid(p.main)) then
			return
		end
		buf = api.nvim_win_get_buf(p.main)
	end
	local path = rel(api.nvim_buf_get_name(buf))
	if not path then
		return
	end
	for i, it in ipairs(p:items()) do
		if it.path == path then
			if p.list.cursor ~= i then
				p.list:view(i)
			end
			return
		end
	end
end
M._follow = follow

--- Deleted files have nothing on disk: show the base version instead.
local function prepare(item)
	if item.status == "D" then
		local buf = vim.fn.bufnr("pulls://base/" .. item.path)
		if buf == -1 then
			buf = api.nvim_create_buf(true, true)
			api.nvim_buf_set_name(buf, "pulls://base/" .. item.path)
			local _, text = git(S.root, { "show", S.base .. ":" .. item.path })
			api.nvim_buf_set_lines(buf, 0, -1, false, vim.split(text, "\n"))
			vim.bo[buf].modifiable = false
			vim.bo[buf].filetype = vim.filetype.match({ filename = item.path }) or ""
		end
		item.buf = buf
		item.pos = nil
		return
	end
	-- Start at the first change, unless you were already reading the file.
	local buf = vim.fn.bufnr(item.file)
	item.pos = (buf == -1 or not api.nvim_buf_is_loaded(buf)) and { item.first, 0 } or nil
end

local function opener(name)
	return function(picker, item, action)
		if not item or item.dir then
			return
		end
		for _, it in ipairs(picker:selected({ fallback = true })) do
			if it.dir then
				return
			end
			prepare(it)
		end
		if item then
			prepare(item)
		end
		require("snacks.picker.actions")[name](picker, item, action)
	end
end

--- Show or hide the changed-files sidebar.
function M.toggle_tree()
	if not S then
		return
	end
	if not has_snacks() then
		local items = {}
		for _, it in ipairs(vim.tbl_filter(function(i)
			return not i.dir
		end, M.items())) do
			items[#items + 1] = { filename = it.file, lnum = it.first, text = it.status .. (it.viewed and " ✓" or "") }
		end
		vim.fn.setqflist({}, " ", { title = string.format("#%d %s", S.number, S.title), items = items })
		vim.cmd("botright copen")
		return
	end
	local p = tree_picker()
	if p then
		p:close()
		return
	end
	-- The review sidebar takes the explorer's place.
	for _, e in ipairs(Snacks.picker.get({ source = "explorer" })) do
		e:close()
	end
	Snacks.picker.pick({
		source = M.source,
		title = "Changed files",
		formatters = { file = { filename_only = true } },
		items = M.items(),
		format = format,
		layout = { preset = "sidebar", preview = false },
		focus = "list",
		auto_close = false,
		jump = { close = false },
		matcher = { sort_empty = false },
		sort = { fields = { "score:desc", "idx" } },
		actions = {
			confirm = opener("jump"),
			edit_split = opener("edit_split"),
			edit_vsplit = opener("edit_vsplit"),
			pulls_viewed = function(_, item)
				if item and not item.dir then
					M.toggle_viewed(item.path)
				end
			end,
			pulls_overview = function()
				M.overview()
			end,
			pulls_browse = function()
				vim.ui.open(S.url)
			end,
		},
		on_show = function()
			vim.schedule(follow)
		end,
		win = {
			list = {
				keys = {
					["v"] = { "pulls_viewed", desc = "Toggle viewed" },
					["o"] = { "pulls_overview", desc = "PR overview and conversation" },
					["l"] = { "confirm", desc = "Open the file" },
					["<C-o>"] = { "pulls_browse", desc = "Open the PR in the browser" },
				},
			},
		},
	})
end

--- For <leader>n: the review sidebar when reviewing in this repository,
--- false otherwise (so the caller can open the normal explorer).
function M.tree()
	if not S then
		local root = toplevel(vim.fn.getcwd())
		local saved = root and read_sessions()[root]
		if not saved then
			return false
		end
		M.resume(root, saved)
	end
	M.toggle_tree()
	return true
end

-- Dependencies -------------------------------------------------------------

local managers = {
	{ lock = "bun.lock", cmd = { "bun", "install" } },
	{ lock = "bun.lockb", cmd = { "bun", "install" } },
	{ lock = "pnpm-lock.yaml", cmd = { "pnpm", "install" } },
	{ lock = "yarn.lock", cmd = { "yarn", "install" } },
	{ lock = "package-lock.json", cmd = { "npm", "install" } },
}

--- Install command for the repository, from its lockfile.
function M.install_cmd(root)
	for _, m in ipairs(managers) do
		if vim.uv.fs_stat(root .. "/" .. m.lock) then
			return m.cmd
		end
	end
	return nil
end

--- True when the pull request touches a lockfile or a package.json.
local function deps_changed(s)
	for _, f in ipairs(s.files or {}) do
		local name = vim.fs.basename(f.path)
		if name == "package.json" then
			return true
		end
		for _, m in ipairs(managers) do
			if name == m.lock then
				return true
			end
		end
	end
	return false
end

--- Restart the language servers working in `root`, so they see new packages.
local function restart_lsp(root)
	local names = {}
	for _, c in ipairs(vim.lsp.get_clients()) do
		if c.root_dir and vim.startswith(realpath(c.root_dir), root) then
			names[c.name] = true
		end
	end
	if next(names) == nil then
		return
	end
	if not pcall(vim.cmd, "lsp restart " .. table.concat(vim.tbl_keys(names), " ")) then
		pcall(vim.cmd, "LspRestart")
	end
end

--- Run the package manager's install in `root` (async), then restart LSP.
function M.install(root)
	root = root or (S and S.root) or toplevel(vim.fn.getcwd())
	local cmd = root and M.install_cmd(root)
	if not cmd then
		notify("No lockfile found, don't know how to install dependencies", vim.log.levels.WARN)
		return
	end
	local label = table.concat(cmd, " ")
	notify("Running " .. label .. "…")
	pending = pending + 1
	local ok, err = pcall(vim.system, cmd, { cwd = root, text = true }, function(r)
		vim.schedule(function()
			pending = pending - 1
			if r.code ~= 0 then
				local out = vim.trim((r.stderr or "") .. "\n" .. (r.stdout or ""))
				notify(label .. " failed:\n" .. out:sub(-800), vim.log.levels.ERROR)
				return
			end
			notify(label .. " done")
			restart_lsp(root)
		end)
	end)
	if not ok then
		pending = pending - 1
		notify("Could not run " .. label .. ": " .. tostring(err), vim.log.levels.ERROR)
	end
end

--- Offer an install when dependencies differ from what is installed.
--- `M.auto_install`: "ask" (default), true (always) or false (never).
M.auto_install = "ask"

local function offer_install(s, why)
	if M.auto_install == false or not deps_changed(s) then
		return
	end
	local cmd = M.install_cmd(s.root)
	if not cmd then
		return
	end
	if M.auto_install ~= true then
		local answer = vim.fn.confirm(why .. " Run `" .. table.concat(cmd, " ") .. "`?", "&Yes\n&No", 1)
		if answer ~= 1 then
			return
		end
	end
	M.install(s.root)
end

-- Loading ------------------------------------------------------------------

local function keymaps(on)
	local maps = {
		{ "n", "n", function() M.n(1) end, "Review: next change (search match while searching)" },
		{ "n", "N", function() M.n(-1) end, "Review: previous change (search match while searching)" },
		{ "n", "]f", function() M.next_file(1) end, "Review: next changed file" },
		{ "n", "[f", function() M.next_file(-1) end, "Review: previous changed file" },
		{ { "n", "x" }, "<leader>pc", function() M.comment() end, "Review: comment on line(s)" },
		{ "n", "<leader>pr", function() M.reply() end, "Review: reply to thread" },
		{ "n", "<leader>pv", function() M.toggle_viewed() end, "Review: toggle file viewed" },
		{ "n", "<leader>ps", function() M.submit() end, "Review: approve / request changes / comment" },
		{ "n", "<leader>po", function() M.overview() end, "Review: PR overview and conversation" },
		{ "n", "<leader>pd", function() M.done() end, "Review: finish and go back to your branch" },
		{ "n", "R", function() M.refresh() end, "Review: pull the PR's new commits and reload" },
	}
	for _, m in ipairs(maps) do
		if on then
			vim.keymap.set(m[1], m[2], m[3], { desc = m[4] })
		else
			pcall(vim.keymap.del, m[1], m[2])
		end
	end
end

--- While reviewing, gitsigns draws the pull request like the pulls tab
--- does: changed lines tinted, changed words marked, removed lines shown
--- inline. `M.colors = false` keeps gitsigns as you configured it.
M.colors = true

local gs_hl = {
	GitSignsAddLn = "PullsAdd",
	GitSignsChangeLn = "PullsAdd",
	GitSignsAddLnInline = "PullsAddWord",
	GitSignsChangeLnInline = "PullsAddWord",
	GitSignsDeleteVirtLn = "PullsDelete",
	GitSignsDeleteVirtLnInLine = "PullsDeleteWord",
}
local saved_gs -- toggles and highlights from before the review

local function colors(on)
	local ok, gs = pcall(require, "gitsigns")
	if not ok or not M.colors then
		return
	end
	if on and not saved_gs then
		local cfg = require("gitsigns.config").config
		saved_gs = { linehl = cfg.linehl, word_diff = cfg.word_diff, show_deleted = cfg.show_deleted, hl = {} }
		for name, link in pairs(gs_hl) do
			saved_gs.hl[name] = api.nvim_get_hl(0, { name = name })
			api.nvim_set_hl(0, name, { link = link })
		end
		gs.toggle_linehl(true)
		gs.toggle_word_diff(true)
		gs.toggle_deleted(true)
	elseif not on and saved_gs then
		for name, hl in pairs(saved_gs.hl) do
			hl.default = nil -- a default link would not replace ours
			api.nvim_set_hl(0, name, hl)
		end
		gs.toggle_linehl(saved_gs.linehl)
		gs.toggle_word_diff(saved_gs.word_diff)
		gs.toggle_deleted(saved_gs.show_deleted)
		saved_gs = nil
	end
end

local function set_base()
	local ok, gs = pcall(require, "gitsigns")
	if ok then
		colors(S ~= nil)
		gs.change_base(S and S.base or nil, true)
	end
end

--- Fetch diff, threads and viewed state; then decorate everything.
local function load(cb)
	local s = S
	local ok, diff = git(s.root, { "diff", "-M", "--no-color", "--no-ext-diff", s.base, "HEAD" })
	if not ok then
		notify("git diff failed", vim.log.levels.ERROR)
		return
	end
	index_files(diff)
	local left = 2
	local function done()
		left = left - 1
		if left == 0 and S == s then
			decorate_all()
			refresh_tree()
			if cb then
				cb()
			end
		end
	end
	gh.review_comments(s.repo, s.number, tracked(function(err, raw)
		if err then
			notify("Could not load review comments: " .. err, vim.log.levels.WARN)
		else
			s.threads = P.threads(raw)
		end
		done()
	end))
	gh.viewed_files(s.repo, s.number, tracked(function(err, res)
		if not err then
			s.viewed, s.pr_id = res.viewed, res.id
		end
		done()
	end))
end

--- Merge base of HEAD with the (freshly fetched) base branch.
local function find_base(s, cb)
	local remote = M.remote_for(s.root, s.repo)
	git_async(s.root, { "fetch", "--quiet", remote, s.base_ref }, function(fetched)
		local ref = fetched and "FETCH_HEAD" or (remote .. "/" .. s.base_ref)
		local ok, base = git(s.root, { "merge-base", ref, "HEAD" })
		if not ok then
			notify("Could not find the merge base with " .. s.base_ref, vim.log.levels.ERROR)
			return
		end
		cb(base)
	end)
end

local function activate(s, cb)
	S = s
	S.threads, S.viewed, S.files, S.by_path = {}, {}, {}, {}
	find_base(s, function(base)
		if S ~= s then
			return
		end
		s.base = base
		set_base()
		keymaps(true)
		api.nvim_clear_autocmds({ group = group })
		api.nvim_create_autocmd("BufReadPost", {
			group = group,
			callback = function(ev)
				decorate(ev.buf)
			end,
		})
		api.nvim_create_autocmd("BufEnter", {
			group = group,
			callback = function()
				if not vim.bo.filetype:match("^snacks_picker") then
					vim.schedule(follow)
				end
			end,
		})
		vim.cmd("silent! checktime")
		load(cb)
	end)
end

--- Fill in the PR fields of a session from `gh pr view`.
local function with_view(s, cb)
	gh.view(s.repo, s.number, tracked(function(err, pr)
		if err then
			notify("Could not load #" .. s.number .. ": " .. err, vim.log.levels.ERROR)
			return
		end
		s.title, s.url, s.base_ref, s.head_sha, s.head_ref = pr.title, pr.url, pr.baseRefName, pr.headRefOid, pr.headRefName
		require("pulls.recent").add(s.repo, pr)
		cb(pr)
	end))
end

--- Pick up a session saved by an earlier Neovim.
function M.resume(root, saved)
	local s = vim.tbl_extend("force", saved, { root = root })
	with_view(s, function()
		activate(s, function()
			M.toggle_tree()
		end)
	end)
	S = s
	S.title, S.threads, S.viewed, S.files = S.title or "", {}, {}, {}
end

--- Worktree (other than `root`) that has `branch` checked out, or nil.
local function worktree_with(root, branch)
	local _, out = git(root, { "worktree", "list", "--porcelain" })
	local path
	for line in (out .. "\n"):gmatch("([^\n]*)\n") do
		path = line:match("^worktree (.+)$") or path
		if line == "branch refs/heads/" .. branch and path and realpath(path) ~= root then
			return path
		end
	end
	return nil
end

--- `gh pr checkout`, or, when the branch is already checked out in another
--- worktree (git allows a branch in one place only), the head commit
--- detached.
local function checkout(root, repo, number, pr, cb)
	local function detached(where)
		local remote = M.remote_for(root, repo)
		git_async(root, { "fetch", "--quiet", remote, "pull/" .. number .. "/head" }, function(ok, _, err)
			if not ok then
				cb("git fetch failed: " .. err)
				return
			end
			local cok, _, cerr = git(root, { "checkout", "--quiet", "--detach", "FETCH_HEAD" })
			if not cok then
				cb(cerr)
				return
			end
			notify(string.format("%s is checked out in %s, so #%d is checked out detached at its head", pr.headRefName, vim.fn.fnamemodify(where, ":~"), number))
			cb(nil, true)
		end)
	end
	local other = worktree_with(root, pr.headRefName)
	if other then
		detached(other)
		return
	end
	gh.checkout(repo, number, root, tracked(function(err)
		local where = err and err:match("already used by worktree at '([^']+)'")
		if where then
			detached(where)
			return
		end
		cb(err)
	end))
end

--- Check out pull request `number` of the repository in the current
--- directory and start reviewing it.
--- @param number integer
--- @param opts? { root?: string }
function M.start(number, opts)
	opts = opts or {}
	local root = opts.root or toplevel(vim.fn.getcwd())
	if not root then
		notify("Not in a git repository", vim.log.levels.WARN)
		return
	end
	if S and S.root == root and S.number == number then
		if not tree_picker() then
			M.toggle_tree()
		end
		return
	end
	local unsaved = modified_buffers()
	if #unsaved > 0 then
		notify("Save or discard these first:\n" .. table.concat(unsaved, "\n"), vim.log.levels.WARN)
		return
	end
	local prev = S and S.root == root and S or nil
	if prev and dirty(root) then
		notify("You changed files on the branch of #" .. prev.number .. "; commit or stash them first", vim.log.levels.WARN)
		return
	end

	gh.current_repo(root, tracked(function(err, repo)
		if err then
			notify("Not a GitHub repository: " .. err, vim.log.levels.ERROR)
			return
		end
		local s = { root = root, repo = repo, number = number }
		with_view(s, function(pr)
			local function go(parked)
				if not parked then
					return
				end
				s.stash, s.wip = parked.stash, parked.wip
				s.orig = current_branch(root)
				if prev then
					s.stash, s.wip, s.orig = prev.stash, prev.wip, prev.orig
				end
				notify(string.format("Checking out #%d (%s)…", number, pr.headRefName))
				checkout(root, repo, number, pr, function(cerr, is_detached)
					s.detached = is_detached
					if cerr then
						notify("Checkout failed: " .. cerr, vim.log.levels.ERROR)
						if not prev then
							unpark(root, parked)
						end
						return
					end
					local _, head = git(root, { "rev-parse", "HEAD" })
					if head ~= pr.headRefOid and not s.detached then
						notify("Your local branch " .. pr.headRefName .. " differs from the pull request's head", vim.log.levels.WARN)
					end
					save(s)
					local p = tree_picker()
					if p then
						p:close()
					end
					activate(s, function()
						M.toggle_tree()
						notify(string.format("Reviewing #%d: %d files. <leader>pd when done", number, #s.files))
						offer_install(s, "#" .. number .. " changes dependencies.")
					end)
				end)
			end
			if prev then
				go({})
			else
				park(root, number, go)
			end
		end)
	end))
end

--- Pick up new commits of the pull request (and new comments): move the
--- checkout to its head, then rebuild files, hunks and threads.
function M.refresh()
	if not S then
		notify("Not reviewing anything", vim.log.levels.WARN)
		return
	end
	local s = S
	local old_head = s.head_sha
	notify("Refreshing #" .. s.number .. "…")
	with_view(s, function(pr)
		if S ~= s then
			return
		end
		local function reload()
			activate(s, function()
				local what = pr.headRefOid ~= old_head and "new commits" or "no new commits"
				notify(string.format("#%d: %s, %d files", s.number, what, #s.files))
			end)
		end
		local _, head = git(s.root, { "rev-parse", "HEAD" })
		if head == pr.headRefOid then
			reload()
			return
		end
		if #modified_buffers() > 0 or dirty(s.root) then
			notify("#" .. s.number .. " has new commits, but you have uncommitted changes here; commit or stash them first", vim.log.levels.WARN)
			return
		end
		checkout(s.root, s.repo, s.number, pr, function(err, is_detached)
			if err then
				notify("Could not update to the new commits: " .. err, vim.log.levels.ERROR)
				return
			end
			s.detached = is_detached
			reload()
		end)
	end)
end

--- Leave the review: back to your branch, your work restored.
function M.done()
	if not S then
		notify("Not reviewing anything", vim.log.levels.WARN)
		return
	end
	local s = S
	local unsaved = modified_buffers()
	if #unsaved > 0 then
		notify("Save or discard these first:\n" .. table.concat(unsaved, "\n"), vim.log.levels.WARN)
		return
	end
	if dirty(s.root) then
		notify("You changed files on the branch of #" .. s.number .. "; commit or stash them first", vim.log.levels.WARN)
		return
	end
	local ok, _, err = git(s.root, { "checkout", "--quiet", s.orig })
	if not ok then
		notify("git checkout " .. s.orig .. " failed: " .. err, vim.log.levels.ERROR)
		return
	end
	local p = tree_picker()
	if p then
		p:close()
	end
	S = nil
	forget(s.root)
	set_base()
	keymaps(false)
	api.nvim_clear_autocmds({ group = group })
	for _, b in ipairs(api.nvim_list_bufs()) do
		vim.diagnostic.reset(ns, b)
		if api.nvim_buf_get_name(b):match("^pulls://base/") then
			api.nvim_buf_delete(b, { force = true })
		end
	end
	unpark(s.root, s)
	vim.cmd("silent! checktime")
	notify("Back on " .. s.orig)
	offer_install(s, "#" .. s.number .. " had other dependencies than " .. s.orig .. ".")
end

-- Actions while reviewing --------------------------------------------------

local function need()
	if not S or not S.base then
		notify("Not reviewing a pull request (:PR review)", vim.log.levels.WARN)
		return nil
	end
	return S
end

--- Changed file of the current buffer, or nil.
local function current_file()
	local path = rel(api.nvim_buf_get_name(0))
	return path and S.by_path[path], path
end

--- Open changed file `idx` of S.files in the current (non-sidebar) window,
--- at `line` (default: its first change unless you were already reading it).
local function open_file(idx, line)
	local f = S.files[idx]
	local item = { file = S.root .. "/" .. f.path, path = f.path, status = f.status, first = f.first }
	-- Never take over the sidebar window.
	if vim.bo.filetype:match("^snacks_picker") then
		vim.cmd.wincmd("p")
	end
	prepare(item)
	if item.buf then
		api.nvim_win_set_buf(0, item.buf)
	else
		vim.cmd.edit(vim.fn.fnameescape(item.file))
	end
	local pos = line and { line, 0 } or item.pos
	if pos then
		pcall(api.nvim_win_set_cursor, 0, pos)
	end
	return f
end

local function file_index()
	local _, path = current_file()
	for i, f in ipairs(S.files) do
		if f.path == path then
			return i
		end
	end
	return 0
end

function M.next_file(dir)
	if not need() or #S.files == 0 then
		return
	end
	local idx, n = file_index(), #S.files
	local next_idx = idx == 0 and (dir > 0 and 1 or n) or ((idx - 1 + dir) % n) + 1
	local f = open_file(next_idx)
	notify(string.format("%d/%d  %s", next_idx, n, f.path))
end

--- Next (dir 1) or previous (-1) change of the pull request: within the
--- file, then on into the next / previous file, wrapping around at the end.
function M.next_change(dir)
	if not need() or #S.files == 0 then
		return
	end
	if vim.bo.filetype:match("^snacks_picker") then
		vim.cmd.wincmd("p")
	end
	local idx, n = file_index(), #S.files
	if idx > 0 then
		local cur = vim.fn.line(".")
		local changes = S.files[idx].changes
		local from, to, step = 1, #changes, 1
		if dir < 0 then
			from, to, step = #changes, 1, -1
		end
		for i = from, to, step do
			local at = changes[i]
			if (dir > 0 and at > cur) or (dir < 0 and at < cur) then
				vim.cmd("normal! m'")
				api.nvim_win_set_cursor(0, { math.min(at, api.nvim_buf_line_count(0)), 0 })
				return
			end
		end
	end
	local next_idx = idx == 0 and (dir > 0 and 1 or n) or ((idx - 1 + dir) % n) + 1
	local changes = S.files[next_idx].changes
	vim.cmd("normal! m'")
	local f = open_file(next_idx, dir > 0 and changes[1] or changes[#changes])
	if (dir > 0 and next_idx <= idx) or (dir < 0 and next_idx >= idx and idx > 0) then
		notify("Wrapped around: " .. f.path)
	else
		notify(string.format("%d/%d  %s", next_idx, n, f.path))
	end
end

--- n / N: repeat the search while one is highlighted, otherwise next /
--- previous change.
function M.n(dir)
	if vim.v.hlsearch == 1 and vim.fn.getreg("/") ~= "" then
		local ok, err = pcall(vim.cmd, "normal! " .. vim.v.count1 .. (dir > 0 and "n" or "N"))
		if not ok then
			local msg = tostring(err):gsub("^.-:E", "E")
			api.nvim_echo({ { msg, "ErrorMsg" } }, false, {})
		end
		return
	end
	for _ = 1, vim.v.count1 do
		M.next_change(dir)
	end
end

function M.comment(l1, l2)
	if not need() then
		return
	end
	local f, path = current_file()
	if not f then
		notify("This file is not part of #" .. S.number, vim.log.levels.WARN)
		return
	end
	if vim.bo.modified then
		notify("Save the file first; comments go on the pull request's lines", vim.log.levels.WARN)
		return
	end
	if not l1 then
		local mode = vim.fn.mode()
		if mode == "v" or mode == "V" or mode == "\22" then
			l1, l2 = vim.fn.line("v"), vim.fn.line(".")
			if l1 > l2 then
				l1, l2 = l2, l1
			end
			api.nvim_feedkeys(api.nvim_replace_termcodes("<Esc>", true, false, true), "nx", false)
		else
			l1 = vim.fn.line(".")
			l2 = l1
		end
	end
	l2 = l2 or l1
	if not f.commentable[l1] or not f.commentable[l2] then
		notify(
			string.format("Line %d is not part of the diff; GitHub only takes comments on changed lines and the lines around them", not f.commentable[l1] and l1 or l2),
			vim.log.levels.WARN
		)
		return
	end
	local s = S
	local where = path .. ":" .. (l1 ~= l2 and (l1 .. "-") or "") .. l2
	compose.open("Comment on " .. where, {}, function(text)
		gh.add_review_comment(s.repo, s.number, {
			body = text,
			commit_id = s.head_sha,
			path = path,
			line = l2,
			side = "RIGHT",
			start_line = l1,
			start_side = "RIGHT",
		}, tracked(function(err)
			if err then
				notify("Comment failed: " .. err, vim.log.levels.ERROR)
				return
			end
			notify("Comment sent")
			M.reload()
		end))
	end)
end

--- Thread on the cursor line of the current buffer.
local function thread_here()
	local lnum = vim.fn.line(".") - 1
	for _, d in ipairs(vim.diagnostic.get(0, { namespace = ns, lnum = lnum })) do
		if d.user_data and d.user_data.thread then
			return d.user_data.thread
		end
	end
	return nil
end

function M.reply()
	if not need() then
		return
	end
	local id = thread_here()
	if not id then
		notify("No review thread on this line", vim.log.levels.WARN)
		return
	end
	local s = S
	compose.open("Reply", {}, function(text)
		gh.reply(s.repo, s.number, id, text, tracked(function(err)
			if err then
				notify("Reply failed: " .. err, vim.log.levels.ERROR)
				return
			end
			notify("Reply sent")
			M.reload()
		end))
	end)
end

--- Tick GitHub's "Viewed" box of `path` (default: the current file).
function M.toggle_viewed(path)
	if not need() then
		return
	end
	if not path then
		local f = current_file()
		if not f then
			notify("This file is not part of #" .. S.number, vim.log.levels.WARN)
			return
		end
		path = f.path
	end
	if not S.pr_id then
		notify("Viewed state is not loaded", vim.log.levels.WARN)
		return
	end
	local s = S
	local want = not s.viewed[path]
	s.viewed[path] = want
	refresh_tree()
	gh.set_viewed(s.pr_id, path, want, tracked(function(err)
		if err then
			s.viewed[path] = not want
			refresh_tree()
			notify("Could not update viewed: " .. err, vim.log.levels.ERROR)
		end
	end))
end

function M.submit()
	if not need() then
		return
	end
	local s = S
	local events = {
		{ event = "approve", label = "Approve" },
		{ event = "request-changes", label = "Request changes" },
		{ event = "comment", label = "Comment" },
	}
	vim.ui.select(events, {
		prompt = "Review #" .. s.number,
		format_item = function(e)
			return e.label
		end,
	}, function(e)
		if not e then
			return
		end
		compose.open(e.label .. " #" .. s.number, { allow_empty = e.event == "approve" }, function(text)
			gh.review(s.repo, s.number, e.event, text, tracked(function(err)
				if err then
					notify("Review failed: " .. err, vim.log.levels.ERROR)
				else
					notify("Review sent")
				end
			end))
		end)
	end)
end

--- Description, checks and conversation in the pulls tab.
function M.overview()
	if not need() then
		return
	end
	require("pulls").open({ repo = S.repo, number = S.number })
end

--- Reload threads and viewed state (after commenting, or with :PR refresh).
function M.reload()
	if need() then
		load()
	end
end

function M.active()
	return S
end

function M.wait(ms)
	return vim.wait(ms or 10000, function()
		return pending == 0
	end, 10)
end

--- Lualine / statusline component.
function M.status()
	if not S then
		return ""
	end
	local seen = 0
	for _, f in ipairs(S.files or {}) do
		if S.viewed[f.path] then
			seen = seen + 1
		end
	end
	return string.format(" #%d %d/%d", S.number, seen, #(S.files or {}))
end

M._ns = ns

--- Drop the active review without touching git. Meant for tests.
function M._reset()
	S = nil
	keymaps(false)
	api.nvim_clear_autocmds({ group = group })
	for _, b in ipairs(api.nvim_list_bufs()) do
		vim.diagnostic.reset(ns, b)
	end
end

return M
