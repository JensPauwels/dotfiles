-- changes.nvim: a VSCode-style "inline diff" view of your git changes.
--
-- Left: the list of changed files (staged and unstaged, or the files that
-- differ from a branch). Right: the selected file rendered as one buffer
-- with removed lines shown in red in place, added lines in green, and
-- unchanged code folded away as "hidden lines". Hunks, selections and whole
-- files can be staged, unstaged and discarded from there.

local api = vim.api
local git = require("changes.git")
local diff = require("changes.diff")

local M = {}

M.config = {
	context = 3, -- unchanged lines kept visible around each change
	panel_width = 40,
	algorithm = "histogram", -- any algorithm accepted by vim.diff()
	sign = "+", -- gutter sign for added lines
	blame = true, -- show blame for the cursor line at the end of the line
	blame_delay = 250, -- ms the cursor has to rest before blame is fetched
}

local ns = api.nvim_create_namespace("changes")
local ns_blame = api.nvim_create_namespace("changes.blame")

--- @class changes.Mode
--- @field kind "status"|"range"
--- @field ref? string      first ref given by the user (range)
--- @field ref2? string     second ref given by the user (range)
--- @field old? string      resolved commit for the old side (range)
--- @field new? string      resolved commit for the new side, nil = worktree
--- @field label? string    section title

--- @class changes.State
--- @field tab integer
--- @field prev_tab integer
--- @field root string
--- @field user string
--- @field mode changes.Mode
--- @field gen integer      bumped whenever async results become stale
--- @field pending integer  async git calls in flight
--- @field panel { buf: integer, win: integer }
--- @field view { buf: integer, win: integer }
--- @field augroup integer
--- @field blame_timer uv.uv_timer_t
--- @field staged changes.Entry[]
--- @field unstaged changes.Entry[]
--- @field entries changes.Entry[]
--- @field line_entry table<integer, changes.Entry>
--- @field current changes.Entry|nil
--- @field file table|nil
--- @field hunk_lines integer[]
local state = nil

local function notify(msg, level)
	vim.notify(msg, level or vim.log.levels.INFO, { title = "changes" })
end

local function confirm(msg)
	return vim.fn.confirm(msg, "&Yes\n&No", 2) == 1
end

local function is_open()
	return state ~= nil and api.nvim_tabpage_is_valid(state.tab)
end

--- Wrap an async callback so it is counted in `state.pending` and dropped
--- when the view was closed or superseded in the meantime.
local function track(s, gen, cb)
	s.pending = s.pending + 1
	return function(...)
		s.pending = s.pending - 1
		if state ~= s or (gen and s.gen ~= gen) then
			return
		end
		cb(...)
	end
end

-- ---------------------------------------------------------------------------
-- Highlights
-- ---------------------------------------------------------------------------

local function set_hl()
	local links = {
		ChangesAdd = "DiffAdd",
		ChangesDelete = "DiffDelete",
		ChangesAddWord = "DiffText",
		ChangesDeleteWord = "DiffText",
		ChangesSignAdd = "Added",
		ChangesTitle = "Title",
		ChangesDim = "Comment",
		ChangesBlame = "Comment",
		ChangesStatusA = "Added",
		ChangesStatusM = "Changed",
		ChangesStatusD = "Removed",
		ChangesStatusU = "DiagnosticError",
		ChangesStatusUntracked = "Added",
	}
	for name, target in pairs(links) do
		api.nvim_set_hl(0, name, { link = target, default = true })
	end
end

-- ---------------------------------------------------------------------------
-- File panel
-- ---------------------------------------------------------------------------

local function set_winbar(win, text)
	if api.nvim_win_is_valid(win) then
		vim.wo[win].winbar = text:gsub("%%", "%%%%")
	end
end

local function render_panel()
	local s = state
	local lines, marks, line_entry = {}, {}, {}

	local function section(title, entries)
		if #entries == 0 then
			return
		end
		if #lines > 0 then
			lines[#lines + 1] = ""
		end
		lines[#lines + 1] = string.format(" %s (%d)", title, #entries)
		marks[#marks + 1] = { #lines, 0, -1, "ChangesTitle" }
		for _, e in ipairs(entries) do
			lines[#lines + 1] = string.format("   %s  %s", e.status, e.path)
			line_entry[#lines] = e
			e.lnum = #lines
			marks[#marks + 1] =
				{ #lines, 3, 4, e.status == "?" and "ChangesStatusUntracked" or "ChangesStatus" .. e.status }
			local dir = e.path:match("^(.*/)")
			if dir then
				marks[#marks + 1] = { #lines, 6, 6 + #dir, "ChangesDim" }
			end
		end
	end

	if s.mode.kind == "status" then
		section("Staged", s.staged)
		section("Changes", s.unstaged)
	else
		section(s.mode.label, s.unstaged)
	end
	if #lines == 0 then
		lines = { "", s.mode.kind == "status" and "   Working tree clean" or "   No differences" }
		marks[#marks + 1] = { 2, 0, -1, "ChangesDim" }
	end

	local buf = s.panel.buf
	vim.bo[buf].modifiable = true
	api.nvim_buf_set_lines(buf, 0, -1, false, lines)
	vim.bo[buf].modifiable = false
	api.nvim_buf_clear_namespace(buf, ns, 0, -1)
	local head = git.head_label(s.root)
	local up = git.upstream(s.root)
	if up then
		head = string.format("%s  ↑%d ↓%d", head, up.ahead, up.behind)
	elseif git.current_branch(s.root) then
		head = head .. "  (no upstream)"
	end
	set_winbar(s.panel.win, string.format("  %s  ·  %s", vim.fs.basename(s.root), head))
	for _, m in ipairs(marks) do
		local end_col = m[3]
		if end_col == -1 then
			end_col = #lines[m[1]]
		end
		api.nvim_buf_set_extmark(buf, ns, m[1] - 1, m[2], { end_col = end_col, hl_group = m[4] })
	end
	s.line_entry = line_entry
end

-- ---------------------------------------------------------------------------
-- Diff view
-- ---------------------------------------------------------------------------

--- Text of the file in the working tree: the loaded buffer when there is
--- one (so unsaved edits show up), the file on disk otherwise.
--- @return string|nil text, integer|nil bufnr
local function worktree_text(root, path)
	local full = root .. "/" .. path
	local b = vim.fn.bufnr(full)
	if b > 0 and api.nvim_buf_is_loaded(b) then
		local lines = api.nvim_buf_get_lines(b, 0, -1, false)
		local eol = vim.bo[b].fixendofline or vim.bo[b].endofline
		return table.concat(lines, "\n") .. (eol and "\n" or ""), b
	end
	return git.read_file(root, path), nil
end

local function set_syntax(buf, path, src_buf)
	local ft = src_buf and vim.bo[src_buf].filetype or ""
	if ft == "" then
		ft = vim.filetype.match({ filename = path }) or ""
	end
	if vim.b[buf].changes_ft == ft then
		return
	end
	vim.b[buf].changes_ft = ft
	pcall(vim.treesitter.stop, buf)
	vim.bo[buf].syntax = ""
	if ft == "" then
		return
	end
	local lang = vim.treesitter.language.get_lang(ft) or ft
	local ok = pcall(vim.treesitter.language.add, lang) and pcall(vim.treesitter.start, buf, lang)
	if not ok then
		vim.bo[buf].syntax = ft
	end
end

local function side_label(entry)
	local s = state
	if s.mode.kind == "range" then
		return s.mode.new and ("(" .. s.mode.ref2 .. ")") or "(Working Tree)"
	end
	return entry.staged and "(Index)" or "(Working Tree)"
end

--- @param opts? { line?: integer, col?: integer }
local function render_view(opts)
	opts = opts or {}
	local s = state
	local f = s.file
	local buf, win = s.view.buf, s.view.win
	api.nvim_buf_clear_namespace(buf, ns_blame, 0, -1)

	if not f then
		vim.bo[buf].modifiable = true
		api.nvim_buf_set_lines(buf, 0, -1, false, { "", "  Nothing to show." })
		vim.bo[buf].modifiable = false
		api.nvim_buf_clear_namespace(buf, ns, 0, -1)
		api.nvim_buf_set_extmark(buf, ns, 1, 0, { end_col = 18, hl_group = "ChangesDim" })
		set_winbar(win, "")
		s.hunk_lines = {}
		return
	end

	local lines = f.new
	if f.binary then
		lines = { "  (binary file)" }
	elseif #lines == 0 then
		lines = { "" }
	end

	vim.bo[buf].modifiable = true
	api.nvim_buf_set_lines(buf, 0, -1, false, lines)
	vim.bo[buf].modifiable = false
	vim.bo[buf].modified = false
	api.nvim_buf_clear_namespace(buf, ns, 0, -1)
	pcall(api.nvim_buf_set_name, buf, "changes://" .. f.entry.path)

	local ts = f.bufnr and vim.bo[f.bufnr].tabstop or vim.o.tabstop
	vim.bo[buf].tabstop = ts
	if f.binary then
		vim.b[buf].changes_ft = nil
		pcall(vim.treesitter.stop, buf)
		vim.bo[buf].syntax = ""
	else
		set_syntax(buf, f.entry.path, f.bufnr)
	end

	local info = vim.fn.getwininfo(win)[1]
	local width = info and (info.width - info.textoff) or 80
	local last_row = api.nvim_buf_line_count(buf) - 1

	s.hunk_lines = {}
	for i, h in ipairs(f.hunks) do
		local sa, ca, sb, cb = h[1], h[2], h[3], h[4]
		s.hunk_lines[i] = math.max(sb, 1)
		local pairs_n = math.min(ca, cb)

		for l = sb, sb + cb - 1 do
			api.nvim_buf_set_extmark(buf, ns, l - 1, 0, {
				line_hl_group = "ChangesAdd",
				sign_text = M.config.sign,
				sign_hl_group = "ChangesSignAdd",
				priority = 10,
			})
		end

		for k = 1, pairs_n do
			local r = diff.word_diff(f.old[sa + k - 1], f.new[sb + k - 1])
			if r and r.b_s <= r.b_e then
				api.nvim_buf_set_extmark(buf, ns, sb + k - 2, r.b_s - 1, {
					end_col = r.b_e,
					hl_group = "ChangesAddWord",
					priority = 20,
				})
			end
		end

		if ca > 0 then
			local virt = {}
			for k = 1, ca do
				local a = diff.expand_tabs(f.old[sa + k - 1], ts)
				local chunks
				if k <= pairs_n then
					local b = diff.expand_tabs(f.new[sb + k - 1], ts)
					local r = diff.word_diff(a, b)
					if r and r.a_s <= r.a_e then
						chunks = {}
						local pre, mid, post = a:sub(1, r.a_s - 1), a:sub(r.a_s, r.a_e), a:sub(r.a_e + 1)
						if pre ~= "" then
							chunks[#chunks + 1] = { pre, "ChangesDelete" }
						end
						chunks[#chunks + 1] = { mid, "ChangesDeleteWord" }
						if post ~= "" then
							chunks[#chunks + 1] = { post, "ChangesDelete" }
						end
					end
				end
				chunks = chunks or { { a, "ChangesDelete" } }
				local pad = width - vim.fn.strdisplaywidth(a)
				if pad > 0 then
					chunks[#chunks + 1] = { string.rep(" ", pad), "ChangesDelete" }
				end
				virt[#virt + 1] = chunks
			end
			local row, above
			if cb > 0 then
				row, above = sb - 1, true
			elseif sb == 0 then
				row, above = 0, true
			else
				row, above = sb - 1, false
			end
			row = math.min(row, last_row)
			api.nvim_buf_set_extmark(buf, ns, row, 0, { virt_lines = virt, virt_lines_above = above })
		end
	end

	api.nvim_win_call(win, function()
		vim.cmd("silent! normal! zE")
		if not f.binary then
			for _, r in ipairs(diff.hidden_ranges(f.hunks, #f.new, M.config.context)) do
				vim.cmd(string.format("silent! %d,%dfold", r[1], r[2]))
			end
		end
	end)

	local n = #f.hunks
	set_winbar(
		win,
		string.format("  %s  %s  ·  %d change%s", f.entry.path, side_label(f.entry), n, n == 1 and "" or "s")
	)

	local line = opts.line or s.hunk_lines[1] or 1
	line = math.max(1, math.min(line, api.nvim_buf_line_count(buf)))
	local col = opts.line and opts.col or 0
	col = math.max(0, math.min(col, #(api.nvim_buf_get_lines(buf, line - 1, line, false)[1] or "")))
	api.nvim_win_set_cursor(win, { line, col })
	api.nvim_win_call(win, function()
		vim.cmd("normal! zv")
	end)
end

--- Fetch old/new contents for an entry, compute hunks and draw it.
--- @param entry changes.Entry
--- @param opts? { line?: integer, col?: integer }
local function load_entry(entry, opts)
	local s = state
	local gen = s.gen
	local root, path = s.root, entry.path
	local mode = s.mode

	-- Describe where each side comes from: a revision, "" or the worktree.
	local old_rev, new_rev, old_empty, new_empty
	if mode.kind == "range" then
		old_rev, old_empty = mode.old, entry.status == "A" or entry.status == "?"
		new_rev, new_empty = mode.new, entry.status == "D"
	elseif entry.staged then
		old_rev, old_empty = "HEAD", entry.status == "A"
		new_rev, new_empty = ":0", entry.status == "D"
	else
		old_rev = entry.status == "U" and "HEAD" or ":0"
		old_empty = entry.status == "?"
		new_rev, new_empty = nil, entry.status == "D"
	end

	local texts, bufnr = {}, nil
	local waiting = 0
	local function finish()
		if waiting > 0 then
			return
		end
		local old_text, new_text = texts.old or "", texts.new or ""
		local f = { entry = entry, bufnr = bufnr }
		f.binary = old_text:find("\0", 1, true) ~= nil or new_text:find("\0", 1, true) ~= nil
		if f.binary then
			f.old, f.new, f.hunks = {}, {}, {}
		else
			f.old, f.old_noeol = diff.split(old_text)
			f.new, f.new_noeol = diff.split(new_text)
			f.hunks = diff.hunks(old_text, new_text, M.config.algorithm)
		end
		s.file = f
		render_view(opts)
	end

	local function fetch(key, rev, empty)
		if empty then
			texts[key] = ""
		elseif rev == nil then
			texts[key], bufnr = worktree_text(root, path)
		else
			waiting = waiting + 1
			git.show_async(
				root,
				rev,
				path,
				track(s, gen, function(text)
					texts[key] = text
					waiting = waiting - 1
					finish()
				end)
			)
		end
	end
	fetch("old", old_rev, old_empty)
	fetch("new", new_rev, new_empty)
	finish()
end

--- @param entry changes.Entry|nil
--- @param opts? { line?: integer, col?: integer, focus?: boolean }
local function select_entry(entry, opts)
	opts = opts or {}
	local s = state
	s.current = entry
	s.gen = s.gen + 1
	if entry then
		if api.nvim_win_is_valid(s.panel.win) then
			pcall(api.nvim_win_set_cursor, s.panel.win, { entry.lnum, 0 })
		end
		load_entry(entry, opts)
	else
		s.file = nil
		render_view()
	end
	if opts.focus and api.nvim_win_is_valid(s.view.win) then
		api.nvim_set_current_win(s.view.win)
	end
end

--- After a refresh, pick the entry closest to the one that was shown.
local function find_entry(prev)
	local s = state
	if not prev then
		return s.entries[1]
	end
	local after, last
	for _, e in ipairs(s.entries) do
		if e.path == prev.path and e.staged == prev.staged then
			return e
		end
		if e.staged == prev.staged then
			last = e
			if not after and e.path > prev.path then
				after = e
			end
		end
	end
	return after or last or s.entries[1]
end

--- Re-read git and redraw. Keeps the current file and cursor position.
--- @param opts? { keep?: boolean }
function M.refresh(opts)
	opts = opts or {}
	if not is_open() then
		return
	end
	local s = state
	s.gen = s.gen + 1
	local gen = s.gen
	local prev = s.current
	local line, col
	if opts.keep and api.nvim_win_is_valid(s.view.win) then
		line, col = unpack(api.nvim_win_get_cursor(s.view.win))
	end

	local function done(staged, unstaged)
		s.staged, s.unstaged = staged, unstaged
		s.entries = {}
		for _, list in ipairs({ s.staged, s.unstaged }) do
			for _, e in ipairs(list) do
				s.entries[#s.entries + 1] = e
				e.index = #s.entries
			end
		end
		render_panel()
		local target = find_entry(prev)
		local same = target and prev and target.path == prev.path and target.staged == prev.staged
		select_entry(target, { line = same and line or nil, col = same and col or nil })
	end

	if s.mode.kind == "range" then
		git.name_status_async(
			s.root,
			s.mode.old,
			s.mode.new,
			track(s, gen, function(entries)
				done({}, entries)
			end)
		)
	else
		git.status_async(s.root, track(s, gen, done))
	end
end

--- Block until all async git work has finished. Meant for tests.
--- @param ms? integer
--- @return boolean
function M.wait(ms)
	return vim.wait(ms or 5000, function()
		return state == nil or state.pending == 0
	end, 10)
end

-- ---------------------------------------------------------------------------
-- Modes: working changes, or a diff against a ref
-- ---------------------------------------------------------------------------

--- Show working changes (staged / unstaged).
function M.status()
	if not is_open() then
		M.open()
		return
	end
	local s = state
	s.mode = { kind = "status" }
	s.current, s.file = nil, nil
	M.refresh()
end

--- Show what differs from `ref`: with one ref, the merge base of that ref
--- and HEAD against the working tree (everything this branch changed,
--- committed or not). With two refs, the two commits against each other.
--- @param ref string
--- @param ref2? string
function M.diff(ref, ref2)
	if not is_open() then
		M.open()
	end
	local s = state
	s.gen = s.gen + 1
	local gen = s.gen
	local function apply(old, new)
		s.mode = {
			kind = "range",
			ref = ref,
			ref2 = ref2,
			old = old,
			new = new,
			label = ref2 and (ref .. ".." .. ref2) or (ref .. "..working tree"),
		}
		s.current, s.file = nil, nil
		M.refresh()
	end
	if ref2 then
		git.rev_parse_async(
			s.root,
			ref,
			track(s, gen, function(old)
				if not old then
					notify("Unknown revision: " .. ref, vim.log.levels.ERROR)
					return
				end
				git.rev_parse_async(
					s.root,
					ref2,
					track(s, gen, function(new)
						if not new then
							notify("Unknown revision: " .. ref2, vim.log.levels.ERROR)
							return
						end
						apply(old, new)
					end)
				)
			end)
		)
	else
		git.merge_base_async(
			s.root,
			ref,
			"HEAD",
			track(s, gen, function(base)
				if not base then
					notify("Cannot find a merge base between " .. ref .. " and HEAD", vim.log.levels.ERROR)
					return
				end
				apply(base, nil)
			end)
		)
	end
end

local function pick_ref()
	local s = state
	local refs = git.refs(s.root)
	local items = { { label = "Working changes", kind = "status" } }
	for _, r in ipairs(refs) do
		items[#items + 1] = { label = r, kind = "ref" }
	end
	vim.ui.select(items, {
		prompt = "Compare with",
		format_item = function(item)
			local cur = (item.kind == "status" and s.mode.kind == "status")
				or (item.kind == "ref" and s.mode.kind == "range" and s.mode.ref == item.label and not s.mode.ref2)
			return (cur and "● " or "  ") .. item.label
		end,
	}, function(item)
		if not item then
			return
		end
		if item.kind == "status" then
			M.status()
		else
			M.diff(item.label)
		end
	end)
end

--- Point the view at another worktree of the same repository.
--- @param path string
function M.set_root(path)
	if not is_open() then
		return
	end
	local root = git.root(path)
	if not root then
		notify(path .. " is not a git worktree", vim.log.levels.ERROR)
		return
	end
	local s = state
	if root == s.root then
		return
	end
	s.root = root
	s.user = git.user_name(root)
	s.current, s.file = nil, nil
	if s.mode.kind == "range" then
		-- HEAD differs per worktree, so the merge base has to be redone.
		M.diff(s.mode.ref, s.mode.ref2)
	else
		M.refresh()
	end
	if api.nvim_win_is_valid(s.panel.win) then
		api.nvim_set_current_win(s.panel.win)
	end
end

local function pick_worktree()
	local s = state
	local list = git.worktrees(s.root)
	if #list <= 1 then
		notify("This repository has only one worktree")
		return
	end
	local width = 0
	for _, wt in ipairs(list) do
		width = math.max(width, #(wt.branch or ("detached @ " .. wt.head)))
	end
	vim.ui.select(list, {
		prompt = "Worktree",
		format_item = function(wt)
			local label = wt.branch or ("detached @ " .. wt.head)
			return string.format(
				"%s %-" .. width .. "s  %s",
				wt.current and "●" or " ",
				label,
				vim.fn.fnamemodify(wt.path, ":~")
			)
		end,
	}, function(wt)
		if wt and not wt.current then
			M.set_root(wt.path)
		end
	end)
end

-- ---------------------------------------------------------------------------
-- Blame
-- ---------------------------------------------------------------------------

local function blame_line()
	local s = state
	if not is_open() or not M.config.blame then
		return
	end
	local f = s.file
	if not f or f.binary or #f.new == 0 or not api.nvim_win_is_valid(s.view.win) then
		return
	end
	local row = api.nvim_win_get_cursor(s.view.win)[1]
	if row > #f.new then
		return
	end
	local gen = s.gen
	local opts
	if s.mode.kind == "range" and s.mode.new then
		opts = { rev = s.mode.new }
	else
		opts = { contents = table.concat(f.new, "\n") .. (f.new_noeol and "" or "\n") }
	end
	git.blame_line_async(
		s.root,
		f.entry.path,
		row,
		opts,
		track(s, gen, function(info)
			if not info or not api.nvim_win_is_valid(s.view.win) then
				return
			end
			if api.nvim_win_get_cursor(s.view.win)[1] ~= row then
				return
			end
			local text
			if info.uncommitted then
				text = "Not committed yet"
			else
				local who = (s.user ~= "" and info.author == s.user) and "You" or info.author
				text = string.format("%s, %s • %s", who, diff.relative_time(info.time), info.summary)
			end
			api.nvim_buf_clear_namespace(s.view.buf, ns_blame, 0, -1)
			api.nvim_buf_set_extmark(s.view.buf, ns_blame, row - 1, 0, {
				virt_text = { { "   " .. text, "ChangesBlame" } },
				virt_text_pos = "eol",
				hl_mode = "combine",
			})
		end)
	)
end

local function schedule_blame()
	local s = state
	if not s or not M.config.blame then
		return
	end
	api.nvim_buf_clear_namespace(s.view.buf, ns_blame, 0, -1)
	s.blame_timer:stop()
	s.blame_timer:start(M.config.blame_delay, 0, vim.schedule_wrap(blame_line))
end

-- ---------------------------------------------------------------------------
-- Actions
-- ---------------------------------------------------------------------------

local function read_only_mode()
	if state.mode.kind == "range" then
		notify(
			"Staging and discarding only work on working changes. Press b and pick 'Working changes'.",
			vim.log.levels.WARN
		)
		return true
	end
	return false
end

local function hunk_at_cursor()
	local s = state
	if not s.file or s.file.binary then
		return nil
	end
	local line = api.nvim_win_get_cursor(s.view.win)[1]
	for i, h in ipairs(s.file.hunks) do
		local sb, cb = h[3], h[4]
		local first, last = sb, sb + cb - 1
		if cb == 0 then
			first, last = math.max(sb, 1), sb + 1
		end
		if line >= first and line <= last then
			return i, h
		end
	end
	return nil
end

local function goto_hunk(dir)
	local s = state
	local lines = s.hunk_lines or {}
	if #lines == 0 then
		return
	end
	local cur = api.nvim_win_get_cursor(s.view.win)[1]
	local target
	if dir > 0 then
		for _, l in ipairs(lines) do
			if l > cur then
				target = l
				break
			end
		end
		target = target or lines[1]
	else
		for i = #lines, 1, -1 do
			if lines[i] < cur then
				target = lines[i]
				break
			end
		end
		target = target or lines[#lines]
	end
	api.nvim_win_set_cursor(s.view.win, { target, 0 })
	vim.cmd("normal! zv")
end

local function goto_file(dir)
	local s = state
	local n = #s.entries
	if n == 0 then
		return
	end
	local idx = s.current and s.current.index or 0
	idx = ((idx - 1 + dir) % n) + 1
	local in_view = api.nvim_get_current_win() == s.view.win
	select_entry(s.entries[idx], { focus = in_view })
end

local function whole_file_only(entry)
	return entry.status == "?" or entry.status == "D" or entry.status == "A" or entry.status == "U"
end

--- Line range to act on: the visual selection, or the whole hunk under the
--- cursor in normal mode. nil when the cursor is not on a change.
--- @return integer|nil l1, integer|nil l2
local function selected_lines()
	local mode = api.nvim_get_mode().mode
	if mode:match("^[vV\22]") then
		local l1, l2 = vim.fn.line("v"), vim.fn.line(".")
		vim.cmd("normal! \27")
		return math.min(l1, l2), math.max(l1, l2)
	end
	local _, h = hunk_at_cursor()
	if not h then
		return nil
	end
	local sb, cb = h[3], h[4]
	if cb == 0 then
		return math.max(sb, 1), sb + 1
	end
	return sb, sb + cb - 1
end

--- Stage (or unstage, in the Staged group) the hunks that overlap the
--- selection. Partial hunks are trimmed to the selected lines.
local function stage_selection()
	local s = state
	local f = s.file
	if not f or f.binary or read_only_mode() then
		return
	end
	local e = f.entry
	local l1, l2 = selected_lines()
	if not l1 then
		notify("No change under the cursor", vim.log.levels.WARN)
		return
	end
	local ok, err = true, ""

	if whole_file_only(e) then
		if e.staged then
			ok, err = git.unstage_file(s.root, e.path)
		else
			ok, err = git.stage_file(s.root, e.path)
		end
	else
		local pieces = {}
		for _, h in ipairs(f.hunks) do
			local removed, added = diff.partial_hunk(h, f.old, f.old_noeol, f.new, f.new_noeol, l1, l2)
			if removed then
				pieces[#pieces + 1] = { removed = removed, added = added }
			end
		end
		if #pieces == 0 then
			notify("No change under the cursor", vim.log.levels.WARN)
			return
		end
		-- Each piece is applied on its own, so later pieces have to account
		-- for the lines the earlier ones added to or removed from the index.
		local delta = 0
		for _, p in ipairs(pieces) do
			if e.staged then
				p.added.start = p.added.start + delta
				delta = delta + #p.removed.lines - #p.added.lines
			else
				p.removed.start = p.removed.start + delta
				delta = delta + #p.added.lines - #p.removed.lines
			end
			local patch = git.patch(e.path, p.removed, p.added, e.staged)
			ok, err = git.apply_cached(s.root, patch, e.staged)
			if not ok then
				break
			end
		end
	end
	if not ok then
		notify(err, vim.log.levels.ERROR)
	end
	M.refresh({ keep = true })
end

local function write_file(full, lines, noeol)
	local fh, err = io.open(full, "wb")
	if not fh then
		return false, err
	end
	fh:write(table.concat(lines, "\n"))
	if not noeol and #lines > 0 then
		fh:write("\n")
	end
	fh:close()
	return true
end

--- Discard the hunks (trimmed to the selection) in the working tree.
local function revert_selection()
	local s = state
	local f = s.file
	if not f or f.binary or read_only_mode() then
		return
	end
	local e = f.entry
	if e.staged then
		notify("Unstage with s first; staged changes are never discarded from here", vim.log.levels.WARN)
		return
	end
	local l1, l2 = selected_lines()
	if not l1 then
		notify("No change under the cursor", vim.log.levels.WARN)
		return
	end
	local full = s.root .. "/" .. e.path

	if e.status == "?" then
		if confirm("Delete untracked file " .. e.path .. "?") then
			vim.fn.delete(full)
		end
	elseif e.status == "D" then
		if confirm("Restore " .. e.path .. " from the index?") then
			local ok, err = git.checkout_file(s.root, e.path)
			if not ok then
				notify(err, vim.log.levels.ERROR)
			end
		end
	else
		local edits = {}
		for _, h in ipairs(f.hunks) do
			local removed, _, a1, a2, include_removed =
				diff.partial_hunk(h, f.old, f.old_noeol, f.new, f.new_noeol, l1, l2)
			if removed then
				local cb = h[4]
				edits[#edits + 1] = {
					start0 = cb > 0 and a1 - 1 or h[3],
					end0 = cb > 0 and a2 or h[3],
					lines = include_removed and removed.lines or {},
				}
			end
		end
		if #edits == 0 then
			notify("No change under the cursor", vim.log.levels.WARN)
			return
		end
		if not confirm(string.format("Discard %d change%s in %s?", #edits, #edits == 1 and "" or "s", e.path)) then
			return
		end
		if f.bufnr and api.nvim_buf_is_loaded(f.bufnr) then
			for i = #edits, 1, -1 do
				api.nvim_buf_set_lines(f.bufnr, edits[i].start0, edits[i].end0, false, edits[i].lines)
			end
			api.nvim_buf_call(f.bufnr, function()
				vim.cmd("silent! update")
			end)
		else
			local lines = vim.list_slice(f.new, 1, #f.new)
			for i = #edits, 1, -1 do
				local ed = edits[i]
				for _ = ed.start0 + 1, ed.end0 do
					table.remove(lines, ed.start0 + 1)
				end
				for k = #ed.lines, 1, -1 do
					table.insert(lines, ed.start0 + 1, ed.lines[k])
				end
			end
			local ok, err = write_file(full, lines, f.new_noeol)
			if not ok then
				notify(err, vim.log.levels.ERROR)
			end
		end
	end
	vim.cmd("silent! checktime")
	M.refresh({ keep = true })
end

local function panel_entry()
	local s = state
	local line = api.nvim_win_get_cursor(s.panel.win)[1]
	return s.line_entry[line]
end

local function panel_stage()
	local s = state
	local e = panel_entry()
	if not e or read_only_mode() then
		return
	end
	local ok, err
	if e.staged then
		ok, err = git.unstage_file(s.root, e.path)
	else
		ok, err = git.stage_file(s.root, e.path)
	end
	if not ok then
		notify(err, vim.log.levels.ERROR)
	end
	M.refresh({ keep = true })
end

local function panel_discard()
	local s = state
	local e = panel_entry()
	if not e or read_only_mode() then
		return
	end
	if e.staged then
		notify("Unstage with s first; staged changes are never discarded from here", vim.log.levels.WARN)
		return
	end
	if e.status == "?" then
		if confirm("Delete untracked file " .. e.path .. "?") then
			vim.fn.delete(s.root .. "/" .. e.path)
		end
	else
		if confirm("Discard all changes in " .. e.path .. "?") then
			local ok, err = git.checkout_file(s.root, e.path)
			if not ok then
				notify(err, vim.log.levels.ERROR)
			end
		end
	end
	vim.cmd("silent! checktime")
	M.refresh({ keep = true })
end

--- Commit what is staged, asking for the message with vim.ui.input.
function M.commit()
	if not is_open() then
		return
	end
	local s = state
	if read_only_mode() then
		return
	end
	if #s.staged == 0 then
		notify("Nothing staged. Stage files or hunks with s first.", vim.log.levels.WARN)
		return
	end
	local summary = string.format("%d file%s staged", #s.staged, #s.staged == 1 and "" or "s")
	vim.ui.input({ prompt = "Commit message (" .. summary .. "): " }, function(msg)
		if not msg or vim.trim(msg) == "" then
			return
		end
		git.commit_async(
			s.root,
			msg,
			track(s, nil, function(ok, out, err)
				if ok then
					notify("Committed: " .. vim.trim(msg):match("^[^\n]*"))
				else
					notify(err ~= "" and err or out, vim.log.levels.ERROR)
				end
				M.refresh({ keep = true })
			end)
		)
	end)
end

--- Push the current branch. Offers to set an upstream when there is none.
function M.push()
	if not is_open() then
		return
	end
	local s = state
	local branch = git.current_branch(s.root)
	if not branch then
		notify("HEAD is detached, nothing to push", vim.log.levels.WARN)
		return
	end
	local args = {}
	if not git.upstream(s.root) then
		if
			not confirm(string.format("'%s' has no upstream. Push it with --set-upstream origin %s?", branch, branch))
		then
			return
		end
		args = { "--set-upstream", "origin", branch }
	end
	notify("Pushing " .. branch .. "...")
	git.push_async(
		s.root,
		args,
		track(s, nil, function(ok, out, err)
			local text = vim.trim(err ~= "" and err or out)
			local last = text:match("([^\n]+)$") or ""
			if ok then
				notify("Pushed " .. branch .. (last ~= "" and (": " .. last) or ""))
			else
				notify("Push failed: " .. text, vim.log.levels.ERROR)
			end
			M.refresh({ keep = true })
		end)
	)
end

local function open_file()
	local s = state
	local f = s.file
	if not f then
		return
	end
	local line = api.nvim_win_get_cursor(s.view.win)[1]
	local full = s.root .. "/" .. f.entry.path
	if s.prev_tab and api.nvim_tabpage_is_valid(s.prev_tab) then
		api.nvim_set_current_tabpage(s.prev_tab)
	else
		vim.cmd("tabnew")
		s.prev_tab = api.nvim_get_current_tabpage()
	end
	vim.cmd("edit " .. vim.fn.fnameescape(full))
	pcall(api.nvim_win_set_cursor, 0, { line, 0 })
	vim.cmd("normal! zv")
end

--- LSP hover for the symbol under the cursor. The diff buffer has no
--- language server, so the request goes to the servers attached to the real
--- file, at the same line and column. Loading that file (hidden) is enough
--- to make the servers attach; they may need a moment to start.
local function hover()
	local s = state
	local f = s.file
	if not f or f.binary then
		return
	end
	local full = s.root .. "/" .. f.entry.path
	if vim.fn.filereadable(full) == 0 then
		notify("File does not exist in the working tree", vim.log.levels.WARN)
		return
	end
	local pos = api.nvim_win_get_cursor(s.view.win)
	local row, col = pos[1] - 1, pos[2]
	local buf = vim.fn.bufadd(full)
	if not api.nvim_buf_is_loaded(buf) then
		vim.fn.bufload(buf)
	end
	local view_line = api.nvim_buf_get_lines(s.view.buf, row, row + 1, false)[1]
	local real_line = api.nvim_buf_get_lines(buf, row, row + 1, false)[1]
	if view_line ~= real_line then
		notify(
			"This line differs from the working tree file, so the language server cannot answer for it",
			vim.log.levels.WARN
		)
		return
	end

	local attempts = 0
	local function try()
		if not is_open() or api.nvim_get_current_buf() ~= s.view.buf then
			return
		end
		local clients = vim.lsp.get_clients({ bufnr = buf, method = "textDocument/hover" })
		if #clients == 0 then
			attempts = attempts + 1
			if attempts == 2 then
				notify("Waiting for a language server to attach to " .. f.entry.path .. "...")
			elseif attempts > 20 then
				notify("No language server with hover support for " .. f.entry.path, vim.log.levels.WARN)
				return
			end
			vim.defer_fn(try, 500)
			return
		end
		local pending, contents = #clients, {}
		for _, client in ipairs(clients) do
			local params = {
				textDocument = { uri = vim.uri_from_bufnr(buf) },
				position = {
					line = row,
					character = vim.lsp.util.character_offset(buf, row, col, client.offset_encoding),
				},
			}
			client:request("textDocument/hover", params, function(err, result)
				pending = pending - 1
				if not err and result and result.contents then
					local lines = vim.lsp.util.convert_input_to_markdown_lines(result.contents)
					if #lines > 0 then
						if #contents > 0 then
							contents[#contents + 1] = "---"
						end
						vim.list_extend(contents, lines)
					end
				end
				if pending == 0 then
					if #contents == 0 then
						notify("No hover information available")
						return
					end
					if not api.nvim_win_is_valid(s.view.win) or api.nvim_win_get_cursor(s.view.win)[1] - 1 ~= row then
						return -- cursor moved on while waiting
					end
					vim.lsp.util.open_floating_preview(contents, "markdown", {
						border = "rounded",
						focus_id = "changes_hover",
						max_width = math.min(100, vim.o.columns - 4),
					})
				end
			end, buf)
		end
	end
	try()
end

local help_lines = {
	" File panel",
	"   j / k          move between files (diff follows)",
	"   <CR> / l       focus the diff",
	"   s              stage / unstage file",
	"   X              discard file changes",
	"   b              compare with a branch, or back to working changes",
	"   w              switch to another worktree",
	"",
	" Diff",
	"   ]c / [c        next / previous change",
	"   <Tab> / <S-Tab> next / previous file",
	"   s              stage / unstage change under cursor",
	"   V + s          stage / unstage only the selected lines",
	"   X              discard change under cursor (V + X for lines)",
	"   <CR> / gf      open the file at this line",
	"   <leader>k / K  hover info from the language server",
	"   zo / za / zR   unfold hidden lines",
	"   -              back to the file panel",
	"",
	" Everywhere",
	"   c              commit what is staged",
	"   P              push the current branch",
	"   R              refresh",
	"   q              close",
	"   ?              this help",
}

local function show_help()
	local buf = api.nvim_create_buf(false, true)
	api.nvim_buf_set_lines(buf, 0, -1, false, help_lines)
	vim.bo[buf].modifiable = false
	vim.bo[buf].bufhidden = "wipe"
	local width = 0
	for _, l in ipairs(help_lines) do
		width = math.max(width, #l)
	end
	local win = api.nvim_open_win(buf, true, {
		relative = "editor",
		width = width + 2,
		height = #help_lines,
		row = math.floor((vim.o.lines - #help_lines) / 2),
		col = math.floor((vim.o.columns - width) / 2),
		style = "minimal",
		border = "rounded",
		title = " changes ",
		title_pos = "center",
	})
	for _, lhs in ipairs({ "q", "<Esc>", "?" }) do
		vim.keymap.set("n", lhs, function()
			api.nvim_win_close(win, true)
		end, { buffer = buf, nowait = true })
	end
end

-- ---------------------------------------------------------------------------
-- Open / close
-- ---------------------------------------------------------------------------

local function map(buf, lhs, rhs, desc, mode)
	vim.keymap.set(mode or "n", lhs, rhs, { buffer = buf, nowait = true, silent = true, desc = "changes: " .. desc })
end

local function setup_keymaps()
	local s = state
	local p, v = s.panel.buf, s.view.buf

	for _, b in ipairs({ p, v }) do
		map(b, "q", M.close, "close")
		map(b, "R", function()
			M.refresh({ keep = true })
		end, "refresh")
		map(b, "?", show_help, "help")
		map(b, "g?", show_help, "help")
		map(b, "c", M.commit, "commit staged changes")
		map(b, "P", M.push, "push")
		map(b, "<Tab>", function()
			goto_file(1)
		end, "next file")
		map(b, "<S-Tab>", function()
			goto_file(-1)
		end, "previous file")
	end

	local function focus_view()
		local e = panel_entry()
		if e then
			local cur = s.current == e and api.nvim_win_get_cursor(s.view.win) or nil
			select_entry(e, { focus = true, line = cur and cur[1] or nil, col = cur and cur[2] or nil })
		end
	end
	map(p, "<CR>", focus_view, "open diff")
	map(p, "l", focus_view, "open diff")
	map(p, "o", focus_view, "open diff")
	map(p, "s", panel_stage, "stage / unstage file")
	map(p, "X", panel_discard, "discard file")
	map(p, "b", pick_ref, "compare with branch")
	map(p, "w", pick_worktree, "switch worktree")

	map(v, "]c", function()
		goto_hunk(1)
	end, "next change")
	map(v, "[c", function()
		goto_hunk(-1)
	end, "previous change")
	map(v, "]h", function()
		goto_hunk(1)
	end, "next change")
	map(v, "[h", function()
		goto_hunk(-1)
	end, "previous change")
	map(v, "s", stage_selection, "stage / unstage change", { "n", "x" })
	map(v, "X", revert_selection, "discard change", { "n", "x" })
	map(v, "<CR>", open_file, "open file")
	map(v, "gf", open_file, "open file")
	map(v, "<leader>k", hover, "hover info")
	map(v, "K", hover, "hover info")
	map(v, "-", function()
		api.nvim_set_current_win(s.panel.win)
	end, "focus file panel")
end

local function setup_autocmds()
	local s = state
	local group = api.nvim_create_augroup("changes.view", { clear = true })
	s.augroup = group

	api.nvim_create_autocmd("CursorMoved", {
		group = group,
		buffer = s.panel.buf,
		callback = function()
			if not is_open() then
				return
			end
			local e = panel_entry()
			if e and e ~= s.current then
				select_entry(e)
			end
		end,
	})

	api.nvim_create_autocmd("CursorMoved", {
		group = group,
		buffer = s.view.buf,
		callback = schedule_blame,
	})

	api.nvim_create_autocmd("WinClosed", {
		group = group,
		callback = function(ev)
			local win = tonumber(ev.match)
			if state and (win == state.panel.win or win == state.view.win) then
				vim.schedule(M.close)
			end
		end,
	})

	api.nvim_create_autocmd("TabClosed", {
		group = group,
		callback = function()
			if state and not api.nvim_tabpage_is_valid(state.tab) then
				vim.schedule(M.close)
			end
		end,
	})

	api.nvim_create_autocmd({ "BufWritePost", "FocusGained" }, {
		group = group,
		callback = function(ev)
			if not is_open() then
				return
			end
			if ev.event == "BufWritePost" then
				local name = api.nvim_buf_get_name(ev.buf)
				if name:sub(1, #s.root) ~= s.root then
					return
				end
			end
			vim.schedule(function()
				M.refresh({ keep = true })
			end)
		end,
	})

	api.nvim_create_autocmd("WinResized", {
		group = group,
		callback = function()
			if is_open() and s.file and api.nvim_win_is_valid(s.view.win) then
				local cur = api.nvim_win_get_cursor(s.view.win)
				render_view({ line = cur[1], col = cur[2] })
			end
		end,
	})
end

function M.open()
	if is_open() then
		api.nvim_set_current_tabpage(state.tab)
		return
	end
	local root = git.root(api.nvim_buf_get_name(0)) or git.root()
	if not root then
		notify("Not inside a git repository", vim.log.levels.ERROR)
		return
	end
	set_hl()

	local prev_tab = api.nvim_get_current_tabpage()
	vim.cmd("tabnew")
	local tab = api.nvim_get_current_tabpage()
	local view_win = api.nvim_get_current_win()
	local scratch = api.nvim_get_current_buf()

	local view_buf = api.nvim_create_buf(false, true)
	api.nvim_win_set_buf(view_win, view_buf)
	if api.nvim_buf_is_valid(scratch) and api.nvim_buf_get_name(scratch) == "" and not vim.bo[scratch].modified then
		pcall(api.nvim_buf_delete, scratch, { force = true })
	end

	local panel_buf = api.nvim_create_buf(false, true)
	local panel_win = api.nvim_open_win(panel_buf, false, {
		split = "left",
		width = M.config.panel_width,
		win = view_win,
	})

	for _, b in ipairs({ view_buf, panel_buf }) do
		vim.bo[b].buftype = "nofile"
		vim.bo[b].bufhidden = "wipe"
		vim.bo[b].swapfile = false
		vim.bo[b].buflisted = false
		vim.bo[b].modifiable = false
	end
	vim.bo[panel_buf].filetype = "changes"
	pcall(api.nvim_buf_set_name, panel_buf, "changes://files")

	local po = vim.wo[panel_win]
	po.number = false
	po.relativenumber = false
	po.signcolumn = "no"
	po.statuscolumn = ""
	po.cursorline = true
	po.winfixwidth = true
	po.wrap = false
	po.foldenable = false
	po.list = false
	po.spell = false

	local vo = vim.wo[view_win]
	vo.number = true
	vo.relativenumber = false
	vo.signcolumn = "yes:1"
	vo.statuscolumn = ""
	vo.cursorline = false
	vo.wrap = false
	vo.list = false
	vo.spell = false
	vo.foldmethod = "manual"
	vo.foldenable = true
	vo.foldlevel = 0
	vo.foldcolumn = "0"
	vo.foldtext = "v:lua.require'changes'.foldtext()"
	vo.fillchars = "fold: ,eob: "

	state = {
		tab = tab,
		prev_tab = prev_tab,
		root = root,
		user = git.user_name(root),
		mode = { kind = "status" },
		gen = 0,
		pending = 0,
		panel = { buf = panel_buf, win = panel_win },
		view = { buf = view_buf, win = view_win },
		blame_timer = assert(vim.uv.new_timer()),
		entries = {},
		staged = {},
		unstaged = {},
		line_entry = {},
		hunk_lines = {},
	}

	setup_keymaps()
	setup_autocmds()
	M.refresh()
	api.nvim_set_current_win(panel_win)
end

function M.close()
	local s = state
	if not s then
		return
	end
	state = nil
	pcall(api.nvim_del_augroup_by_id, s.augroup)
	s.blame_timer:stop()
	s.blame_timer:close()
	if api.nvim_tabpage_is_valid(s.tab) then
		if #api.nvim_list_tabpages() == 1 then
			api.nvim_set_current_tabpage(s.tab)
			vim.cmd("silent! only")
			vim.cmd("enew")
		else
			vim.cmd("silent! tabclose " .. api.nvim_tabpage_get_number(s.tab))
		end
	end
	for _, b in ipairs({ s.panel.buf, s.view.buf }) do
		if api.nvim_buf_is_valid(b) then
			pcall(api.nvim_buf_delete, b, { force = true })
		end
	end
end

function M.toggle()
	if is_open() then
		M.close()
	else
		M.open()
	end
end

function M.foldtext()
	local n = vim.v.foldend - vim.v.foldstart + 1
	return string.format("  ⋯ %d hidden line%s", n, n == 1 and "" or "s")
end

--- Read-only peek at internal state, for tests.
function M._state()
	return state
end

function M.setup(opts)
	M.config = vim.tbl_deep_extend("force", M.config, opts or {})
	set_hl()
	api.nvim_create_autocmd("ColorScheme", {
		group = api.nvim_create_augroup("changes.hl", { clear = true }),
		callback = set_hl,
	})
	api.nvim_create_user_command("Changes", function(cmd)
		local args = cmd.fargs
		local sub = args[1] or "toggle"
		if
			sub == "open"
			or sub == "close"
			or sub == "toggle"
			or sub == "refresh"
			or sub == "status"
			or sub == "commit"
			or sub == "push"
		then
			M[sub]()
		elseif sub == "worktree" then
			if not args[2] then
				notify("Usage: :Changes worktree <path>", vim.log.levels.WARN)
			else
				M.open()
				M.set_root(vim.fn.expand(args[2]))
			end
		elseif sub == "diff" then
			if not args[2] then
				notify("Usage: :Changes diff <ref> [<ref2>]", vim.log.levels.WARN)
			else
				M.diff(args[2], args[3])
			end
		else
			-- `:Changes main` is a shortcut for `:Changes diff main`
			M.diff(sub, args[2])
		end
	end, {
		nargs = "*",
		complete = function(_, line)
			local root = git.root(api.nvim_buf_get_name(0)) or git.root()
			if line:match("^%S+%s+worktree%s") then
				local paths = {}
				for _, wt in ipairs(root and git.worktrees(root) or {}) do
					paths[#paths + 1] = wt.path
				end
				return paths
			elseif line:match("^%S+%s+diff%s") then
				return root and git.refs(root) or {}
			end
			local subs = { "open", "close", "toggle", "refresh", "status", "commit", "push", "diff", "worktree" }
			return vim.list_extend(subs, root and git.refs(root) or {})
		end,
	})
end

return M
