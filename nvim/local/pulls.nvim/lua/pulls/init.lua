-- pulls.nvim: read and review GitHub pull requests inside Neovim.
--
-- One tab page. Left: the pull requests of a repository, or, once one is
-- opened, its overview and changed files. Right: the overview (checks,
-- description, commits, conversation) or a file's diff, drawn inline with
-- removed lines in red, added lines in green, and review threads under the
-- lines they comment on. Everything goes through the `gh` CLI.

local api = vim.api
local gh = require("pulls.gh")
local P = require("pulls.patch")

local M = {}

M.config = {
	panel_width = 50,
	limit = 50, -- pull requests fetched per list
	state = "open", -- initial list filter: open, closed, merged, all
	search = "", -- initial search, e.g. "review-requested:@me"
	compose_height = 12,
	-- When a reviewed pull request changes package.json or the lockfile:
	-- "ask" to run the install (bun/pnpm/yarn/npm), true always, false never.
	install = "ask",
	-- While reviewing in your checkout, tint changed lines and show removed
	-- ones inline through gitsigns (false: just its signs).
	review_colors = true,
}

local ns = api.nvim_create_namespace("pulls")
local STATES = { "open", "merged", "closed", "all" }

--- @class pulls.Item
--- @field kind "overview"|"file"
--- @field file? pulls.File

--- @class pulls.PR
--- @field number integer
--- @field view table|nil          gh pr view result
--- @field files pulls.File[]|nil
--- @field threads table<string, pulls.Thread[]>|nil
--- @field err string|nil

local state = nil

local function notify(msg, level)
	vim.notify(msg, level or vim.log.levels.INFO, { title = "pulls" })
end

local function confirm(msg)
	return vim.fn.confirm(msg, "&Yes\n&No", 2) == 1
end

local function is_open()
	return state ~= nil and api.nvim_tabpage_is_valid(state.tab)
end

--- Count an async call in `state.pending` and drop its result when the view
--- was closed or the request superseded (`gen` changed) in the meantime.
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
		PullsAdd = "DiffAdd",
		PullsDelete = "DiffDelete",
		PullsAddWord = "DiffText",
		PullsDeleteWord = "DiffText",
		PullsHunk = "Folded",
		PullsLineNr = "LineNr",
		PullsTitle = "Title",
		PullsDim = "Comment",
		PullsOpen = "Added",
		PullsDraft = "Comment",
		PullsMerged = "Special",
		PullsClosed = "Removed",
		PullsPass = "DiagnosticOk",
		PullsFail = "DiagnosticError",
		PullsPending = "DiagnosticWarn",
		PullsThread = "NormalFloat",
		PullsThreadBorder = "FloatBorder",
		PullsThreadAuthor = "Title",
		PullsStatusA = "Added",
		PullsStatusM = "Changed",
		PullsStatusD = "Removed",
		PullsStatusR = "Changed",
		PullsViewed = "DiagnosticOk",
	}
	for name, target in pairs(links) do
		api.nvim_set_hl(0, name, { link = target, default = true })
	end
end

-- ---------------------------------------------------------------------------
-- Small builders
-- ---------------------------------------------------------------------------

--- Lines plus highlight ranges, built line by line.
local function builder()
	local b = { lines = {}, marks = {} }
	function b.add(text, hl)
		b.lines[#b.lines + 1] = text
		if hl then
			b.marks[#b.marks + 1] = { #b.lines, 0, #text, hl }
		end
		return #b.lines
	end
	--- Highlight a byte range (0-based start, exclusive end) of the last line.
	function b.mark(s, e, hl)
		b.marks[#b.marks + 1] = { #b.lines, s, e, hl }
	end
	--- Append `text` to the last line, highlighted with `hl`.
	function b.append(text, hl)
		local l = b.lines[#b.lines]
		b.lines[#b.lines] = l .. text
		if hl then
			b.marks[#b.marks + 1] = { #b.lines, #l, #l + #text, hl }
		end
	end
	return b
end

local function set_lines(buf, b)
	vim.bo[buf].modifiable = true
	api.nvim_buf_set_lines(buf, 0, -1, false, b.lines)
	vim.bo[buf].modifiable = false
	api.nvim_buf_clear_namespace(buf, ns, 0, -1)
	for _, m in ipairs(b.marks) do
		pcall(api.nvim_buf_set_extmark, buf, ns, m[1] - 1, m[2], { end_col = m[3], hl_group = m[4], priority = 300 })
	end
end

local function set_winbar(win, text)
	if win and api.nvim_win_is_valid(win) then
		vim.wo[win].winbar = (text:gsub("%%", "%%%%"))
	end
end

local function login(user)
	if type(user) ~= "table" then
		return "ghost"
	end
	return user.login or user.name or user.slug or "ghost"
end

local function clean(body)
	return ((body or ""):gsub("\r\n", "\n"):gsub("%s+$", ""))
end

local state_hl = { OPEN = "PullsOpen", MERGED = "PullsMerged", CLOSED = "PullsClosed" }

local function pr_state(pr)
	if pr.isDraft and pr.state == "OPEN" then
		return "DRAFT", "PullsDraft"
	end
	return pr.state or "OPEN", state_hl[pr.state] or "PullsOpen"
end

local function checks_icon(c)
	if c.fail > 0 then
		return "✗", "PullsFail"
	elseif c.pending > 0 then
		return "●", "PullsPending"
	elseif c.pass > 0 then
		return "✓", "PullsPass"
	end
	return nil, nil
end

local review_text = {
	APPROVED = { "approved", "PullsPass" },
	CHANGES_REQUESTED = { "changes requested", "PullsFail" },
	REVIEW_REQUIRED = { "review required", "PullsPending" },
}

local function set_syntax(buf, path)
	local ft = vim.filetype.match({ filename = path }) or ""
	if vim.b[buf].pulls_ft == ft then
		return
	end
	vim.b[buf].pulls_ft = ft
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

-- ---------------------------------------------------------------------------
-- Overview (also used as the preview in the list)
-- ---------------------------------------------------------------------------

--- @param pr table   gh pr view (or gh pr list) object
--- @param opts { preview?: boolean, threads?: integer }
local function overview(pr, opts)
	local b = builder()
	b.add("# " .. (pr.title or ""))
	b.add("")
	local st, st_hl = pr_state(pr)
	b.add(st, st_hl)
	b.append(string.format("  #%d  %s wants to merge ", pr.number, login(pr.author)))
	b.append(pr.headRefName or "?", "PullsTitle")
	b.append(" into ")
	b.append(pr.baseRefName or "?", "PullsTitle")
	local meta = string.format("+%d −%d", pr.additions or 0, pr.deletions or 0)
	if pr.changedFiles then
		meta = meta .. string.format(" in %d file%s", pr.changedFiles, pr.changedFiles == 1 and "" or "s")
	end
	if pr.createdAt then
		meta = meta .. " · opened " .. P.ago(pr.createdAt)
	end
	if pr.updatedAt then
		meta = meta .. " · updated " .. P.ago(pr.updatedAt)
	end
	b.add(meta, "PullsDim")
	if pr.labels and #pr.labels > 0 then
		local names = {}
		for _, l in ipairs(pr.labels) do
			names[#names + 1] = l.name
		end
		b.add("Labels: " .. table.concat(names, ", "))
	end
	if pr.assignees and #pr.assignees > 0 then
		local names = {}
		for _, a in ipairs(pr.assignees) do
			names[#names + 1] = "@" .. login(a)
		end
		b.add("Assignees: " .. table.concat(names, ", "))
	end
	local rv = review_text[pr.reviewDecision or ""]
	if rv then
		b.add("Review: ")
		b.append(rv[1], rv[2])
		if pr.reviewRequests and #pr.reviewRequests > 0 then
			local names = {}
			for _, r in ipairs(pr.reviewRequests) do
				names[#names + 1] = "@" .. login(r)
			end
			b.append("  · waiting on " .. table.concat(names, ", "), "PullsDim")
		end
	end
	if pr.mergeable and pr.state == "OPEN" then
		local m = { MERGEABLE = { "no conflicts", "PullsPass" }, CONFLICTING = { "has conflicts", "PullsFail" } }
		local v = m[pr.mergeable]
		if v then
			b.add("Merge: ")
			b.append(v[1], v[2])
		end
	end

	local c = P.checks(pr.statusCheckRollup)
	if #c.checks > 0 then
		b.add("")
		b.add("## Checks")
		for _, k in ipairs({ { "pass", "✓", "PullsPass" }, { "fail", "✗", "PullsFail" }, { "pending", "●", "PullsPending" } }) do
			if c[k[1]] > 0 then
				b.append(string.format("  %s %d", k[2], c[k[1]]), k[3])
			end
		end
		if c.skipped > 0 then
			b.append(string.format("  %d skipped", c.skipped), "PullsDim")
		end
		local icons = { pass = { "✓", "PullsPass" }, fail = { "✗", "PullsFail" }, pending = { "●", "PullsPending" } }
		local list_pass = c.pass <= 8
		for _, ck in ipairs(c.checks) do
			local ic = icons[ck.state]
			if ic and (ck.state ~= "pass" or list_pass) then
				b.add("  " .. ic[1], ic[2])
				b.append(" " .. ck.name)
			end
		end
		if not list_pass then
			b.add(string.format("  ✓ %d passed", c.pass), "PullsPass")
		end
	end

	b.add("")
	b.add("## Description")
	b.add("")
	local body = clean(pr.body)
	if body == "" then
		b.add("No description.", "PullsDim")
	else
		for _, l in ipairs(vim.split(body, "\n", { plain = true })) do
			b.add(l)
		end
	end

	if opts.preview then
		b.add("")
		b.add("Press <CR> to open this pull request.", "PullsDim")
		return b
	end

	if pr.commits and #pr.commits > 0 then
		b.add("")
		b.add(string.format("## Commits (%d)", #pr.commits))
		b.add("")
		for _, cm in ipairs(pr.commits) do
			local who = cm.authors and cm.authors[1] and login(cm.authors[1]) or ""
			b.add("  ")
			b.append((cm.oid or ""):sub(1, 7), "PullsDim")
			b.append("  " .. (cm.messageHeadline or ""))
			b.append(string.format("  %s, %s", who, P.ago(cm.committedDate or "")), "PullsDim")
		end
	end

	local timeline = {}
	for _, cm in ipairs(pr.comments or {}) do
		timeline[#timeline + 1] =
			{ who = login(cm.author), what = "commented", hl = "PullsTitle", at = cm.createdAt or "", body = clean(cm.body) }
	end
	local verbs = {
		APPROVED = { "approved", "PullsPass" },
		CHANGES_REQUESTED = { "requested changes", "PullsFail" },
		COMMENTED = { "reviewed", "PullsTitle" },
		DISMISSED = { "review dismissed", "PullsDim" },
	}
	for _, r in ipairs(pr.reviews or {}) do
		local v = verbs[r.state or ""]
		local body_r = clean(r.body)
		-- plain "COMMENTED" reviews without a body are just inline comments
		if v and (r.state ~= "COMMENTED" or body_r ~= "") then
			timeline[#timeline + 1] = { who = login(r.author), what = v[1], hl = v[2], at = r.submittedAt or "", body = body_r }
		end
	end
	table.sort(timeline, function(x, y)
		return x.at < y.at
	end)
	b.add("")
	b.add(string.format("## Conversation (%d)", #timeline))
	if (opts.threads or 0) > 0 then
		b.add("")
		b.add(
			string.format("%d review thread%s on the changed files.", opts.threads, opts.threads == 1 and "" or "s"),
			"PullsDim"
		)
	end
	for _, ev in ipairs(timeline) do
		b.add("")
		b.add("### " .. ev.who .. " ")
		b.append(ev.what, ev.hl)
		b.append(" · " .. P.ago(ev.at), "PullsDim")
		if ev.body ~= "" then
			b.add("")
			for _, l in ipairs(vim.split(ev.body, "\n", { plain = true })) do
				b.add(l)
			end
		end
	end
	if #timeline == 0 then
		b.add("")
		b.add("No comments yet.", "PullsDim")
	end
	return b
end

local function show_main(buf)
	local s = state
	if api.nvim_win_get_buf(s.main.win) ~= buf then
		api.nvim_win_set_buf(s.main.win, buf)
	end
	local wo = vim.wo[s.main.win]
	local is_diff = buf == s.diff_buf
	wo.wrap = not is_diff
	wo.linebreak = not is_diff
	wo.number = is_diff
	wo.statuscolumn = is_diff and "%!v:lua.require'pulls'.statuscol()" or ""
	wo.cursorline = is_diff
end

local function render_overview(pr, opts)
	local s = state
	set_lines(s.overview_buf, overview(pr, opts))
	show_main(s.overview_buf)
	api.nvim_win_set_cursor(s.main.win, { 1, 0 })
	set_winbar(s.main.win, string.format("  #%d  %s", pr.number, pr.title or ""))
end

local function render_message(msg)
	local s = state
	set_lines(s.overview_buf, { lines = { "", "  " .. msg }, marks = { { 2, 0, #msg + 2, "PullsDim" } } })
	show_main(s.overview_buf)
	set_winbar(s.main.win, "")
end

-- ---------------------------------------------------------------------------
-- Diff of one file
-- ---------------------------------------------------------------------------

--- virt_lines for a thread, `width` cells wide.
local function thread_virt(t, width, label)
	local virt = {}
	local bw = math.max(width - 4, 20)
	for i, cm in ipairs(t.comments) do
		local corner = i == 1 and "╭─ " or "├─ "
		virt[#virt + 1] = {
			{ "  " .. corner, "PullsThreadBorder" },
			{ cm.author, "PullsThreadAuthor" },
			{ " · " .. P.ago(cm.created_at) .. (i == 1 and label or ""), "PullsDim" },
		}
		for _, l in ipairs(P.wrap(cm.body, bw)) do
			virt[#virt + 1] = { { "  │ ", "PullsThreadBorder" }, { l, "PullsThread" } }
		end
	end
	virt[#virt + 1] = { { "  ╰─ ", "PullsThreadBorder" }, { "r to reply", "PullsDim" } }
	return virt
end

local function render_diff(f, opts)
	opts = opts or {}
	local s = state
	local buf, win = s.diff_buf, s.main.win
	local threads = (s.pr.threads or {})[f.path] or {}
	local lines, maxn = {}, 0
	for i, l in ipairs(f.lines) do
		lines[i] = l.text
		maxn = math.max(maxn, l.old or 0, l.new or 0)
	end
	local placeholder = nil
	if #lines == 0 then
		placeholder = f.binary and "Binary file, not shown." or (f.status == "R" and "Renamed without changes.")
			or "No changes to show."
		lines = { "", "  " .. placeholder }
	end
	vim.bo[buf].modifiable = true
	api.nvim_buf_set_lines(buf, 0, -1, false, lines)
	vim.bo[buf].modifiable = false
	api.nvim_buf_clear_namespace(buf, ns, 0, -1)

	s.diff = {
		file = f,
		lines = placeholder and {} or f.lines,
		numw = math.max(#tostring(maxn), 2),
		thread_rows = {},
		hunk_rows = {},
	}
	if placeholder then
		set_syntax(buf, "")
		api.nvim_buf_set_extmark(buf, ns, 1, 0, { end_col = #lines[2], hl_group = "PullsDim" })
	else
		set_syntax(buf, f.path)
	end

	for i, l in ipairs(s.diff.lines) do
		local row = i - 1
		if l.kind == "+" then
			api.nvim_buf_set_extmark(buf, ns, row, 0, { line_hl_group = "PullsAdd", priority = 100 })
		elseif l.kind == "-" then
			api.nvim_buf_set_extmark(buf, ns, row, 0, { line_hl_group = "PullsDelete", priority = 100 })
		elseif l.kind == "@" then
			api.nvim_buf_set_extmark(
				buf,
				ns,
				row,
				0,
				{ end_col = #l.text, hl_group = "PullsHunk", line_hl_group = "PullsHunk", priority = 300 }
			)
		end
		local prev = s.diff.lines[i - 1]
		if (l.kind == "+" or l.kind == "-") and not (prev and (prev.kind == "+" or prev.kind == "-")) then
			s.diff.hunk_rows[#s.diff.hunk_rows + 1] = i
		end
	end
	for _, pair in ipairs(P.word_pairs(s.diff.lines)) do
		local a, b = s.diff.lines[pair[1]], s.diff.lines[pair[2]]
		local w = P.word_diff(a.text, b.text)
		if w then
			if w.a_e >= w.a_s then
				api.nvim_buf_set_extmark(
					buf,
					ns,
					pair[1] - 1,
					w.a_s - 1,
					{ end_col = w.a_e, hl_group = "PullsDeleteWord", priority = 200 }
				)
			end
			if w.b_e >= w.b_s then
				api.nvim_buf_set_extmark(
					buf,
					ns,
					pair[2] - 1,
					w.b_s - 1,
					{ end_col = w.b_e, hl_group = "PullsAddWord", priority = 200 }
				)
			end
		end
	end

	local width = api.nvim_win_get_width(win) - (s.diff.numw * 2 + 4)
	local outdated = {}
	for _, t in ipairs(threads) do
		local row = not placeholder and P.thread_row(s.diff.lines, t)
		if row then
			api.nvim_buf_set_extmark(buf, ns, row - 1, 0, { virt_lines = thread_virt(t, width, "") })
			s.diff.thread_rows[row] = s.diff.thread_rows[row] or {}
			table.insert(s.diff.thread_rows[row], t)
		else
			outdated[#outdated + 1] = t
		end
	end
	if #outdated > 0 then
		local last = #lines
		local virt = { { { "", "" } }, { { "  Outdated comments", "PullsTitle" } } }
		for _, t in ipairs(outdated) do
			local where = string.format(" · %s line %s", t.side == "LEFT" and "old" or "", t.original_line or "?")
			vim.list_extend(virt, thread_virt(t, width, (where:gsub("  ", " "))))
		end
		api.nvim_buf_set_extmark(buf, ns, last - 1, 0, { virt_lines = virt })
		s.diff.thread_rows[last] = s.diff.thread_rows[last] or {}
		vim.list_extend(s.diff.thread_rows[last], outdated)
	end

	show_main(buf)
	local n = 0
	for _ in pairs(s.diff.thread_rows) do
		n = n + 1
	end
	local bar = string.format(
		"  %s  ·  +%d −%d%s",
		f.status == "R" and (f.old_path .. " → " .. f.path) or f.path,
		f.additions,
		f.deletions,
		#threads > 0 and string.format("  ·  %d thread%s", #threads, #threads == 1 and "" or "s") or ""
	) .. ((s.pr.viewed or {})[f.path] and "  ·  ✓ viewed" or "")
	set_winbar(win, bar)
	local line = math.min(opts.line or 1, api.nvim_buf_line_count(buf))
	api.nvim_win_set_cursor(win, { line, 0 })
end

--- Status column of the diff: old and new line numbers.
function M.statuscol()
	local s = state
	if not s or not s.diff then
		return ""
	end
	local w = s.diff.numw
	local blank = string.rep(" ", w * 2 + 3)
	if vim.v.virtnum ~= 0 then
		return blank
	end
	local l = s.diff.lines[vim.v.lnum]
	if not l or l.kind == "@" then
		return blank
	end
	local function pad(n)
		local t = n and tostring(n) or ""
		return string.rep(" ", w - #t) .. t
	end
	return "%#PullsLineNr#" .. pad(l.old) .. " " .. pad(l.new) .. "  %*"
end

-- ---------------------------------------------------------------------------
-- Panel
-- ---------------------------------------------------------------------------

local function render_list_panel()
	local s = state
	local b = builder()
	local line_pr = {}
	if s.list_err then
		b.add("")
		b.add("  " .. s.list_err:gsub("\n", " "), "PullsFail")
	elseif not s.prs then
		b.add("")
		b.add("  Loading…", "PullsDim")
	elseif #s.prs == 0 then
		b.add("")
		b.add("  No pull requests", "PullsDim")
	end
	for _, pr in ipairs(s.prs or {}) do
		local _, st_hl = pr_state(pr)
		local num = "#" .. pr.number
		b.add(" ")
		b.append(num, st_hl)
		b.append("  " .. (pr.title or ""))
		line_pr[#b.lines] = pr
		b.add("   " .. string.rep(" ", #num))
		b.append(login(pr.author), "PullsDim")
		b.append(" · " .. P.ago(pr.updatedAt or ""), "PullsDim")
		if pr.isDraft then
			b.append(" · draft", "PullsDraft")
		end
		local icon, icon_hl = checks_icon(P.checks(pr.statusCheckRollup))
		if icon then
			b.append(" " .. icon, icon_hl)
		end
		local rv = review_text[pr.reviewDecision or ""]
		if rv and rv[1] ~= "review required" then
			b.append(" " .. rv[1], rv[2])
		end
		line_pr[#b.lines] = pr
	end
	set_lines(s.panel.buf, b)
	s.line_pr = line_pr
	local filter = s.state_filter .. (s.search ~= "" and ("  " .. s.search) or "")
	set_winbar(s.panel.win, string.format("  %s  ·  %s", s.repo or "…", filter))
end

local function render_pr_panel()
	local s = state
	local pr = s.pr
	local b = builder()
	local items = {}
	b.add("  Overview", nil)
	items[1] = { kind = "overview" }
	if pr.err then
		b.add("")
		b.add("  " .. pr.err:gsub("\n", " "), "PullsFail")
	elseif not pr.files then
		b.add("")
		b.add(" Files", "PullsTitle")
		b.add("   Loading…", "PullsDim")
	else
		b.add("")
		b.add(string.format(" Files (%d)", #pr.files), "PullsTitle")
		local viewed = pr.viewed or {}
		local nviewed = 0
		for _, f in ipairs(pr.files) do
			if viewed[f.path] then
				nviewed = nviewed + 1
			end
		end
		if nviewed > 0 then
			b.append(string.format("  · %d/%d viewed", nviewed, #pr.files), "PullsDim")
		end
		for _, f in ipairs(pr.files) do
			local seen = viewed[f.path]
			local prefix = seen and " ✓ " or "   "
			b.add(prefix)
			if seen then
				b.mark(1, #prefix - 1, "PullsViewed")
			end
			b.append(f.status, "PullsStatus" .. f.status)
			b.append("  ")
			local dir = f.path:match("^(.*/)")
			if seen then
				b.append(f.path, "PullsDim")
			elseif dir then
				b.append(dir, "PullsDim")
				b.append(f.path:sub(#dir + 1))
			else
				b.append(f.path)
			end
			b.append(string.format("  +%d", f.additions), "PullsStatusA")
			b.append(string.format(" −%d", f.deletions), "PullsStatusD")
			local nt = #((pr.threads or {})[f.path] or {})
			if nt > 0 then
				b.append(string.format("  ● %d", nt), "PullsPending")
			end
			items[#b.lines] = { kind = "file", file = f }
		end
	end
	set_lines(s.panel.buf, b)
	s.line_item = items
	local title = pr.view and pr.view.title or ""
	set_winbar(s.panel.win, string.format("  %s #%d  %s", s.repo, pr.number, title))
end

--- Show what the panel cursor points at in the main window.
local function sync_main(force)
	local s = state
	if not api.nvim_win_is_valid(s.panel.win) then
		return
	end
	local lnum = api.nvim_win_get_cursor(s.panel.win)[1]
	if s.screen == "list" then
		local pr = s.line_pr[lnum]
		if pr and (force or s.shown ~= pr) then
			s.shown = pr
			render_overview(pr, { preview = true })
		elseif not pr and (force or s.shown ~= nil) then
			s.shown = nil
			render_message(s.prs and #s.prs == 0 and "Nothing to show." or "")
		end
		return
	end
	local item = s.line_item[lnum]
	if not item then
		return
	end
	local key = item.kind == "file" and item.file or "overview"
	if not force and s.shown == key then
		return
	end
	s.shown = key
	if item.kind == "overview" then
		if s.pr.view then
			local nt = 0
			for _, ts in pairs(s.pr.threads or {}) do
				nt = nt + #ts
			end
			render_overview(s.pr.view, { threads = nt })
		else
			render_message(s.pr.err or "Loading…")
		end
	else
		render_diff(item.file)
	end
end

-- ---------------------------------------------------------------------------
-- Loading
-- ---------------------------------------------------------------------------

function M.refresh_list()
	local s = state
	s.gen = s.gen + 1
	s.screen = "list"
	s.prs, s.list_err, s.shown = nil, nil, false
	render_list_panel()
	sync_main(true)
	if not s.repo then
		return
	end
	local gen = s.gen
	gh.list(
		s.repo,
		{ state = s.state_filter, search = s.search, limit = M.config.limit },
		track(s, gen, function(err, prs)
			s.prs, s.list_err = prs or {}, err
			render_list_panel()
			local lnum = 1
			if s.restore_list then
				for l, pr in pairs(s.line_pr) do
					if pr.number == s.restore_list and (lnum == 1 or l < lnum) then
						lnum = l
					end
				end
				s.restore_list = nil
			end
			pcall(api.nvim_win_set_cursor, s.panel.win, { lnum, 0 })
			sync_main(true)
		end)
	)
end

--- (Re)load everything about a pull request. `keep` keeps the panel cursor.
local function load_pr(number, keep)
	local s = state
	s.gen = s.gen + 1
	local gen = s.gen
	local cursor = keep and api.nvim_win_get_cursor(s.panel.win) or { 1, 0 }
	local main_cursor = keep and api.nvim_win_get_cursor(s.main.win)
	s.screen = "pr"
	s.pr = { number = number }
	s.shown = nil
	render_pr_panel()
	pcall(api.nvim_win_set_cursor, s.panel.win, cursor)
	sync_main(true)

	local waiting = 4
	local function done()
		waiting = waiting - 1
		render_pr_panel()
		pcall(api.nvim_win_set_cursor, s.panel.win, cursor)
		if waiting == 0 then
			sync_main(true)
			if main_cursor then
				pcall(api.nvim_win_set_cursor, s.main.win, main_cursor)
			end
		elseif s.shown == "overview" then
			sync_main(true)
		end
	end
	gh.view(
		s.repo,
		number,
		track(s, gen, function(err, view)
			s.pr.view = view
			if err then
				s.pr.err = err
			else
				pcall(require("pulls.recent").add, s.repo, view)
			end
			done()
		end)
	)
	gh.diff(
		s.repo,
		number,
		track(s, gen, function(err, text)
			if err then
				s.pr.err = s.pr.err or err
				s.pr.files = {}
			else
				s.pr.files = P.parse(text)
			end
			done()
		end)
	)
	gh.review_comments(
		s.repo,
		number,
		track(s, gen, function(err, raw)
			s.pr.threads = err and {} or P.threads(raw or {})
			if err then
				notify("Could not load review comments: " .. err, vim.log.levels.WARN)
			end
			done()
		end)
	)
	gh.viewed_files(
		s.repo,
		number,
		track(s, gen, function(err, res)
			-- not fatal: the files just show without their "Viewed" state
			if res then
				s.pr.id, s.pr.viewed = res.id, res.viewed
			end
			done()
		end)
	)
end

--- Reload only review comments and redraw the current file in place.
local function reload_comments()
	local s = state
	local gen = s.gen
	local number = s.pr.number
	gh.review_comments(
		s.repo,
		number,
		track(s, gen, function(err, raw)
			if err then
				return
			end
			s.pr.threads = P.threads(raw or {})
			local cursor = api.nvim_win_get_cursor(s.main.win)
			render_pr_panel()
			if s.diff and api.nvim_win_get_buf(s.main.win) == s.diff_buf then
				render_diff(s.diff.file, { line = cursor[1] })
			end
		end)
	)
end

local function reload_view()
	local s = state
	local gen = s.gen
	gh.view(
		s.repo,
		s.pr.number,
		track(s, gen, function(err, view)
			if not err then
				s.pr.view = view
				if s.shown == "overview" then
					sync_main(true)
				end
			end
		end)
	)
end

function M.open_pr(number)
	local s = state
	s.restore_list = number
	load_pr(number, false)
end

-- ---------------------------------------------------------------------------
-- Writing comments and reviews
-- ---------------------------------------------------------------------------

--- Open a markdown buffer below the main window; `:w` or <C-s> sends it.
local function compose(title, opts, on_send)
	require("pulls.compose").height = M.config.compose_height
	return require("pulls.compose").open(title, vim.tbl_extend("force", opts, { anchor = state.main.win }), on_send)
end

local function reported(what, after)
	return function(err)
		if err then
			notify(what .. " failed: " .. err, vim.log.levels.ERROR)
			return
		end
		notify(what .. " sent")
		if after then
			after()
		end
	end
end

local function need_pr()
	local s = state
	if s.screen ~= "pr" or not s.pr.view then
		notify("Open a pull request first", vim.log.levels.WARN)
		return nil
	end
	return s.pr
end

--- Number of the PR under the cursor in the list, or the open one.
local function target_pr()
	local s = state
	if s.screen == "pr" then
		return s.pr.number, s.pr.view
	end
	local pr = s.line_pr[api.nvim_win_get_cursor(s.panel.win)[1]]
	if pr then
		return pr.number, pr
	end
	return nil
end

function M.comment()
	local s = state
	local number = target_pr()
	if not number then
		return
	end
	compose(string.format("Comment on #%d", number), {}, function(text)
		gh.comment(
			s.repo,
			number,
			text,
			track(s, nil, reported("Comment", function()
				if s.screen == "pr" then
					reload_view()
				end
			end))
		)
	end)
end

--- @param event "approve"|"request-changes"|"comment"
function M.review(event)
	local s = state
	local number = target_pr()
	if not number then
		return
	end
	local labels = { approve = "Approve", ["request-changes"] = "Request changes on", comment = "Review" }
	compose(
		string.format("%s #%d  (body%s)", labels[event], number, event == "approve" and " optional" or ""),
		{ allow_empty = event == "approve" },
		function(text)
			gh.review(
				s.repo,
				number,
				event,
				text,
				track(s, nil, reported("Review", function()
					if s.screen == "pr" then
						reload_view()
					end
				end))
			)
		end
	)
end

--- Line under the cursor (or the selected range) in the diff, as review
--- comment coordinates.
local function comment_target(l1, l2)
	local s = state
	local d = s.diff
	local first, last = d.lines[l1], d.lines[l2]
	if not first or not last or first.kind == "@" or last.kind == "@" then
		return nil
	end
	local function coord(l)
		if l.kind == "-" then
			return l.old, "LEFT"
		end
		return l.new, "RIGHT"
	end
	local line, side = coord(last)
	local start_line, start_side = coord(first)
	return { path = d.file.path, line = line, side = side, start_line = start_line, start_side = start_side }
end

function M.comment_line(l1, l2)
	local s = state
	local pr = need_pr()
	if not pr or not s.diff or api.nvim_get_current_buf() ~= s.diff_buf then
		return
	end
	local cur = api.nvim_win_get_cursor(s.main.win)[1]
	l1, l2 = l1 or cur, l2 or cur
	local c = comment_target(l1, l2)
	if not c then
		notify("Put the cursor on a line of the diff", vim.log.levels.WARN)
		return
	end
	c.commit_id = pr.view.headRefOid
	local where = c.path .. ":" .. (c.start_line ~= c.line and (c.start_line .. "-") or "") .. c.line
	compose("Comment on " .. where, {}, function(text)
		c.body = text
		gh.add_review_comment(s.repo, pr.number, c, track(s, nil, reported("Comment", reload_comments)))
	end)
end

--- Tick or untick GitHub's "Viewed" box for the file under the cursor
--- (panel) or shown in the diff.
function M.toggle_viewed()
	local s = state
	if s.screen ~= "pr" then
		return
	end
	local f
	if api.nvim_get_current_win() == s.panel.win then
		local item = s.line_item[api.nvim_win_get_cursor(s.panel.win)[1]]
		f = item and item.file
	elseif s.diff and api.nvim_win_get_buf(s.main.win) == s.diff_buf then
		f = s.diff.file
	end
	if not f then
		notify("Put the cursor on a file", vim.log.levels.WARN)
		return
	end
	if not s.pr.id then
		notify("Viewed state is not available for this pull request", vim.log.levels.WARN)
		return
	end
	s.pr.viewed = s.pr.viewed or {}
	local viewed = not s.pr.viewed[f.path]
	local function redraw()
		local cursor = api.nvim_win_get_cursor(s.panel.win)
		render_pr_panel()
		pcall(api.nvim_win_set_cursor, s.panel.win, cursor)
		if s.diff and s.diff.file == f and api.nvim_win_get_buf(s.main.win) == s.diff_buf then
			render_diff(f, { line = api.nvim_win_get_cursor(s.main.win)[1] })
		end
	end
	-- update right away, undo if GitHub refuses
	s.pr.viewed[f.path] = viewed
	redraw()
	gh.set_viewed(
		s.pr.id,
		f.path,
		viewed,
		track(s, s.gen, function(err)
			if err then
				s.pr.viewed[f.path] = not viewed
				redraw()
				notify("Could not mark as viewed: " .. err, vim.log.levels.ERROR)
			end
		end)
	)
end

function M.reply()
	local s = state
	local pr = need_pr()
	if not pr or not s.diff then
		return
	end
	local row = api.nvim_win_get_cursor(s.main.win)[1]
	local ts = s.diff.thread_rows[row]
	local cur = s.diff.lines[row]
	if not ts and cur and (cur.kind == "+" or cur.kind == "-") then
		-- also accept the cursor anywhere in the change the thread hangs under
		for r = row + 1, #s.diff.lines do
			local l = s.diff.lines[r]
			if l.kind ~= "+" and l.kind ~= "-" then
				break
			end
			if s.diff.thread_rows[r] then
				ts = s.diff.thread_rows[r]
				break
			end
		end
	end
	if not ts then
		notify("No review thread on this line", vim.log.levels.WARN)
		return
	end
	local function go(t)
		compose("Reply to " .. t.comments[1].author, {}, function(text)
			gh.reply(s.repo, pr.number, t.id, text, track(s, nil, reported("Reply", reload_comments)))
		end)
	end
	if #ts == 1 then
		go(ts[1])
	else
		vim.ui.select(ts, {
			prompt = "Reply to which thread?",
			format_item = function(t)
				local first = t.comments[1]
				return first.author .. ": " .. (first.body:match("[^\n]*") or "")
			end,
		}, function(t)
			if t then
				go(t)
			end
		end)
	end
end

--- Check the pull request out in your own clone and review it there.
function M.checkout()
	local s = state
	local number = target_pr()
	if not number then
		return
	end
	if not s.local_root then
		notify("No local clone of " .. s.repo .. " in the current directory", vim.log.levels.WARN)
		return
	end
	local root = s.local_root
	M.close()
	require("pulls.review").start(number, { root = root })
end

function M.browse()
	local _, pr = target_pr()
	if pr and pr.url then
		vim.ui.open(pr.url)
	end
end

-- ---------------------------------------------------------------------------
-- Navigation
-- ---------------------------------------------------------------------------

local function jump(rows, dir)
	local s = state
	local cur = api.nvim_win_get_cursor(s.main.win)[1]
	local list = {}
	for _, r in ipairs(rows) do
		list[#list + 1] = r
	end
	table.sort(list)
	if dir > 0 then
		for _, r in ipairs(list) do
			if r > cur then
				api.nvim_win_set_cursor(s.main.win, { r, 0 })
				return
			end
		end
	else
		for i = #list, 1, -1 do
			if list[i] < cur then
				api.nvim_win_set_cursor(s.main.win, { list[i], 0 })
				return
			end
		end
	end
end

function M.next_hunk(dir)
	if state.diff then
		jump(state.diff.hunk_rows, dir)
		vim.cmd("normal! zz")
	end
end

function M.next_thread(dir)
	if state.diff then
		jump(vim.tbl_keys(state.diff.thread_rows), dir)
	end
end

--- Move to the next/previous file in the panel and show it.
function M.next_file(dir)
	local s = state
	if s.screen ~= "pr" or not s.pr.files or #s.pr.files == 0 then
		return
	end
	local rows = {}
	for lnum, item in pairs(s.line_item) do
		if item.kind == "file" then
			rows[#rows + 1] = lnum
		end
	end
	table.sort(rows)
	local cur = api.nvim_win_get_cursor(s.panel.win)[1]
	local target
	if dir > 0 then
		target = rows[1]
		for _, r in ipairs(rows) do
			if r > cur then
				target = r
				break
			end
		end
	else
		target = rows[#rows]
		for i = #rows, 1, -1 do
			if rows[i] < cur then
				target = rows[i]
				break
			end
		end
	end
	api.nvim_win_set_cursor(s.panel.win, { target, 0 })
	sync_main()
end

--- Open the real file at the line under the cursor, in the previous tab.
function M.goto_file()
	local s = state
	if not s.diff or not s.local_root then
		if not s.local_root then
			notify("No local clone of " .. s.repo .. " in the current directory", vim.log.levels.WARN)
		end
		return
	end
	local f = s.diff.file
	if f.status == "D" then
		notify("The file is deleted in this pull request", vim.log.levels.WARN)
		return
	end
	local row = api.nvim_win_get_cursor(s.main.win)[1]
	local line = 1
	for r = row, #s.diff.lines do
		if s.diff.lines[r].new then
			line = s.diff.lines[r].new
			break
		end
	end
	local path = s.local_root .. "/" .. f.path
	if api.nvim_tabpage_is_valid(s.prev_tab) then
		api.nvim_set_current_tabpage(s.prev_tab)
	else
		vim.cmd("tabnew")
	end
	vim.cmd("edit " .. vim.fn.fnameescape(path))
	pcall(api.nvim_win_set_cursor, 0, { line, 0 })
	vim.cmd("normal! zz")
end

function M.back()
	local s = state
	if s.screen == "pr" then
		s.restore_list = s.pr.number
		if s.prs then
			s.gen = s.gen + 1
			s.screen = "list"
			s.shown = false
			s.diff = nil
			render_list_panel()
			local lnum = 1
			for l, pr in pairs(s.line_pr) do
				if pr.number == s.restore_list and (lnum == 1 or l < lnum) then
					lnum = l
				end
			end
			s.restore_list = nil
			pcall(api.nvim_win_set_cursor, s.panel.win, { lnum, 0 })
			sync_main(true)
		else
			M.refresh_list()
		end
	end
	api.nvim_set_current_win(s.panel.win)
end

function M.cycle_state()
	local s = state
	local i = 1
	for k, v in ipairs(STATES) do
		if v == s.state_filter then
			i = k
		end
	end
	s.state_filter = STATES[i % #STATES + 1]
	M.refresh_list()
end

function M.search()
	local s = state
	vim.ui.input({ prompt = "Search (e.g. author:@me, review-requested:@me): ", default = s.search }, function(q)
		if q == nil then
			return
		end
		s.search = vim.trim(q)
		M.refresh_list()
	end)
end

function M.switch_repo()
	local s = state
	vim.ui.input({ prompt = "Repository (owner/name): ", default = s.repo or "" }, function(r)
		if not r or vim.trim(r) == "" then
			return
		end
		s.repo = vim.trim(r)
		s.local_root = (s.cwd_repo and s.cwd_repo:lower() == s.repo:lower()) and s.cwd_root or nil
		M.refresh_list()
	end)
end

function M.refresh()
	local s = state
	if not is_open() then
		return
	end
	if s.screen == "pr" then
		load_pr(s.pr.number, true)
	else
		s.restore_list = (s.line_pr[api.nvim_win_get_cursor(s.panel.win)[1]] or {}).number
		M.refresh_list()
	end
end

local help = {
	"Pull request list",
	"  <CR> l   open the pull request",
	"  s        cycle open / merged / closed / all",
	"  f        search (gh search syntax)",
	"  r        switch repository",
	"",
	"Pull request",
	"  <CR> l   focus the overview or diff",
	"  <BS> h   back to the list (panel)",
	"  -        back to the panel (diff/overview)",
	"  ]c [c    next / previous change",
	"  ]t [t    next / previous review thread",
	"  <Tab>    next / previous file (<S-Tab>)",
	"  c        comment on the line (or selection) / on the PR",
	"  r        reply to the thread on this line",
	"  v        mark the file as viewed (again to undo)",
	"  gf       open the file in your checkout",
	"  A X      approve / request changes",
	"  C        review in your checkout (check out, LSP, gd …)",
	"",
	"Everywhere",
	"  o  open in browser    R  refresh    q  close    ?  help",
	"",
	"Comments open a markdown buffer: :w or <C-s> sends it, q cancels.",
}

function M.help()
	-- menu.nvim, when there: the keys of this window, fuzzy-searchable
	local ok, menu = pcall(require, "menu")
	if ok then
		menu.open({ here = true, title = "Pulls keys" })
		return
	end
	notify(table.concat(help, "\n"))
end

-- ---------------------------------------------------------------------------
-- Setup of the tab
-- ---------------------------------------------------------------------------

local function map(buf, lhs, fn, desc, mode)
	vim.keymap.set(mode or "n", lhs, fn, { buffer = buf, nowait = true, silent = true, desc = desc })
end

local function setup_keymaps()
	local s = state
	local p = s.panel.buf
	map(p, "<CR>", function()
		if s.screen == "list" then
			local pr = s.line_pr[api.nvim_win_get_cursor(s.panel.win)[1]]
			if pr then
				M.open_pr(pr.number)
			end
		else
			sync_main()
			api.nvim_set_current_win(s.main.win)
		end
	end, "Open")
	vim.keymap.set("n", "l", "<CR>", { buffer = p, remap = true, nowait = true })
	vim.keymap.set("n", "o", function()
		M.browse()
	end, { buffer = p, nowait = true, desc = "Open in browser" })
	map(p, "<BS>", M.back, "Back to the list")
	map(p, "h", M.back, "Back to the list")
	map(p, "s", function()
		if s.screen == "list" then
			M.cycle_state()
		end
	end, "Cycle state filter")
	map(p, "f", function()
		if s.screen == "list" then
			M.search()
		end
	end, "Search")
	map(p, "r", function()
		if s.screen == "list" then
			M.switch_repo()
		end
	end, "Switch repository")
	map(p, "c", M.comment, "Comment on the pull request")

	for _, b in ipairs({ s.overview_buf, s.diff_buf }) do
		map(b, "-", function()
			api.nvim_set_current_win(s.panel.win)
		end, "Back to the panel")
		map(b, "<Tab>", function()
			M.next_file(1)
		end, "Next file")
		map(b, "<S-Tab>", function()
			M.next_file(-1)
		end, "Previous file")
		map(b, "o", M.browse, "Open in browser")
	end
	map(s.overview_buf, "c", M.comment, "Comment on the pull request")

	local d = s.diff_buf
	map(d, "c", function()
		M.comment_line()
	end, "Comment on this line")
	map(d, "c", function()
		local a, b = vim.fn.line("v"), vim.fn.line(".")
		if a > b then
			a, b = b, a
		end
		api.nvim_feedkeys(api.nvim_replace_termcodes("<Esc>", true, false, true), "nx", false)
		M.comment_line(a, b)
	end, "Comment on the selected lines", "x")
	map(d, "r", M.reply, "Reply to the thread")
	map(d, "v", M.toggle_viewed, "Toggle viewed")
	map(p, "v", M.toggle_viewed, "Toggle viewed")
	map(d, "]c", function()
		M.next_hunk(1)
	end, "Next change")
	map(d, "[c", function()
		M.next_hunk(-1)
	end, "Previous change")
	map(d, "]t", function()
		M.next_thread(1)
	end, "Next thread")
	map(d, "[t", function()
		M.next_thread(-1)
	end, "Previous thread")
	map(d, "gf", M.goto_file, "Open the file in your checkout")
	map(d, "<CR>", M.goto_file, "Open the file in your checkout")

	for _, b in ipairs({ p, s.overview_buf, s.diff_buf }) do
		map(b, "A", function()
			M.review("approve")
		end, "Approve")
		map(b, "X", function()
			M.review("request-changes")
		end, "Request changes")
		map(b, "C", M.checkout, "Review in your checkout (checks the branch out)")
		map(b, "R", M.refresh, "Refresh")
		map(b, "q", M.close, "Close")
		map(b, "?", M.help, "Help")
	end
end

local function scratch(name)
	local buf = api.nvim_create_buf(false, true)
	vim.bo[buf].buftype = "nofile"
	vim.bo[buf].bufhidden = "hide"
	vim.bo[buf].swapfile = false
	vim.bo[buf].modifiable = false
	pcall(api.nvim_buf_set_name, buf, name)
	return buf
end

local function git_root(dir)
	local res = vim.system({ "git", "rev-parse", "--show-toplevel" }, { cwd = dir, text = true }):wait()
	if res.code ~= 0 then
		return nil
	end
	return vim.trim(res.stdout)
end

--- Open the view.
--- @param opts? { repo?: string, number?: integer }
function M.open(opts)
	opts = opts or {}
	if is_open() then
		api.nvim_set_current_tabpage(state.tab)
		if opts.repo and opts.repo ~= state.repo then
			state.repo = opts.repo
			state.local_root = (state.cwd_repo and state.cwd_repo:lower() == opts.repo:lower()) and state.cwd_root
				or nil
			if opts.number then
				M.open_pr(opts.number)
			else
				M.refresh_list()
			end
		elseif opts.number then
			M.open_pr(opts.number)
		end
		return
	end
	set_hl()

	local file = api.nvim_buf_get_name(0)
	local cwd = (file ~= "" and vim.fn.isdirectory(vim.fs.dirname(file)) == 1) and vim.fs.dirname(file)
		or vim.fn.getcwd()
	local root = git_root(cwd)

	local prev_tab = api.nvim_get_current_tabpage()
	vim.cmd("tabnew")
	local tab = api.nvim_get_current_tabpage()
	local main_win = api.nvim_get_current_win()
	local first = api.nvim_get_current_buf()

	local overview_buf = scratch("pulls://overview")
	local diff_buf = scratch("pulls://diff")
	local panel_buf = scratch("pulls://panel")
	vim.bo[panel_buf].filetype = "pulls"
	pcall(vim.treesitter.start, overview_buf, "markdown")
	api.nvim_win_set_buf(main_win, overview_buf)
	if api.nvim_buf_is_valid(first) and api.nvim_buf_get_name(first) == "" and not vim.bo[first].modified then
		pcall(api.nvim_buf_delete, first, { force = true })
	end
	local panel_win = api.nvim_open_win(panel_buf, false, {
		split = "left",
		width = M.config.panel_width,
		win = main_win,
	})

	local po = vim.wo[panel_win]
	po.number = false
	po.relativenumber = false
	po.signcolumn = "no"
	po.statuscolumn = ""
	po.cursorline = true
	po.winfixwidth = true
	po.wrap = false
	po.list = false
	po.spell = false
	po.foldenable = false

	local mo = vim.wo[main_win]
	mo.relativenumber = false
	mo.signcolumn = "no"
	mo.foldenable = false
	mo.foldcolumn = "0"
	mo.list = false
	mo.spell = false
	mo.numberwidth = 1
	mo.fillchars = "eob: "

	state = {
		tab = tab,
		prev_tab = prev_tab,
		gen = 0,
		pending = 0,
		screen = "list",
		repo = opts.repo,
		cwd_root = root,
		local_root = nil,
		state_filter = M.config.state,
		search = M.config.search,
		panel = { buf = panel_buf, win = panel_win },
		main = { win = main_win },
		overview_buf = overview_buf,
		diff_buf = diff_buf,
		line_pr = {},
		line_item = {},
	}
	local s = state

	setup_keymaps()
	s.augroup = api.nvim_create_augroup("pulls.view", { clear = true })
	api.nvim_create_autocmd("CursorMoved", {
		group = s.augroup,
		buffer = panel_buf,
		callback = function()
			sync_main()
		end,
	})
	api.nvim_create_autocmd("TabClosed", {
		group = s.augroup,
		callback = function()
			if state == s and not api.nvim_tabpage_is_valid(s.tab) then
				M.close()
			end
		end,
	})
	api.nvim_create_autocmd("VimResized", {
		group = s.augroup,
		callback = function()
			if state == s and s.diff and api.nvim_win_get_buf(s.main.win) == s.diff_buf then
				render_diff(s.diff.file, { line = api.nvim_win_get_cursor(s.main.win)[1] })
			end
		end,
	})

	local function start()
		if opts.number then
			M.open_pr(opts.number)
		else
			M.refresh_list()
		end
	end

	-- Which repository the current directory is a clone of: the default
	-- repository, and needed to open files and check out branches.
	gh.current_repo(root or cwd, track(s, nil, function(err, repo)
		s.cwd_repo = repo
		if not s.repo then
			if err or not repo then
				s.list_err = "Not a GitHub repository here; use :PR owner/name"
				render_list_panel()
				render_message("")
				return
			end
			s.repo = repo
			s.local_root = root
			start()
		elseif repo and repo:lower() == s.repo:lower() then
			s.local_root = root
		end
	end))
	if s.repo then
		start()
	else
		render_list_panel()
		render_message("")
	end
	api.nvim_set_current_win(panel_win)
end

function M.close()
	local s = state
	if not s then
		return
	end
	state = nil
	pcall(api.nvim_del_augroup_by_id, s.augroup)
	if api.nvim_tabpage_is_valid(s.tab) then
		if #api.nvim_list_tabpages() == 1 then
			api.nvim_set_current_tabpage(s.tab)
			vim.cmd("silent! only")
			vim.cmd("enew")
		else
			vim.cmd("silent! tabclose " .. api.nvim_tabpage_get_number(s.tab))
		end
	end
	for _, b in ipairs({ s.panel.buf, s.overview_buf, s.diff_buf }) do
		if api.nvim_buf_is_valid(b) then
			pcall(api.nvim_buf_delete, b, { force = true })
		end
	end
end

--- Quick picker over pull requests waiting for your review, recently
--- opened ones and your own, across repositories.
--- <CR> reviews it in your checkout when it belongs to the repository in
--- the current directory, otherwise (and with <C-t>) opens the pulls tab.
--- @param opts? { all?: boolean } all repositories, not just this one
function M.pick(opts)
	opts = opts or {}
	local here_root = vim.fs.root(vim.fn.getcwd(), ".git")
	local here_repo = here_root and require("pulls.review").repo_of(here_root) or nil
	require("pulls.pick").open(function(repo, number, how)
		if how ~= "tab" then
			-- A remote of the current clone points at the repository.
			local here = vim.fs.root(vim.fn.getcwd(), ".git")
			if here and not require("pulls.review").remote_for(here, repo):match("^https://") then
				require("pulls.review").start(number)
				return
			end
		end
		M.open({ repo = repo, number = number })
	end, { repo = not opts.all and here_repo or nil, home = here_repo })
end

function M.toggle()
	if is_open() then
		M.close()
	else
		M.open()
	end
end

--- Block until all async gh work has finished. Meant for tests.
function M.wait(ms)
	return vim.wait(ms or 5000, function()
		return state == nil or state.pending == 0
	end, 10)
end

function M._state()
	return state
end

--- Parse :PR arguments: [owner/name] [number], or a pull request URL.
--- @param args string[]
--- @return { repo?: string, number?: integer }
function M.parse_args(args)
	local opts = {}
	for _, a in ipairs(args) do
		local r, n = a:match("github%.com/([^/]+/[^/]+)/pull/(%d+)")
		if r then
			opts.repo, opts.number = r, tonumber(n)
		elseif a:match("^#?%d+$") then
			opts.number = tonumber((a:gsub("#", "")))
		elseif a:match("^[%w%-%._]+/[%w%-%._]+$") then
			opts.repo = a
		end
	end
	return opts
end

function M.setup(opts)
	M.config = vim.tbl_deep_extend("force", M.config, opts or {})
	require("pulls.review").auto_install = M.config.install
	require("pulls.review").colors = M.config.review_colors
	set_hl()
	api.nvim_create_autocmd("ColorScheme", {
		group = api.nvim_create_augroup("pulls.hl", { clear = true }),
		callback = set_hl,
	})
	api.nvim_create_user_command("PR", function(cmd)
		local sub = cmd.fargs[1]
		local review = require("pulls.review")
		if sub == "close" or sub == "toggle" or sub == "pick" then
			M[sub]()
		elseif sub == "refresh" then
			if is_open() then
				M.refresh()
			else
				review.refresh()
			end
		elseif sub == "review" then
			local n = M.parse_args({ cmd.fargs[2] or "" }).number
			if n then
				review.start(n)
			else
				M.pick()
			end
		elseif sub == "done" then
			review.done()
		elseif sub == "files" then
			review.toggle_tree()
		elseif sub == "install" then
			review.install()
		else
			M.open(M.parse_args(cmd.fargs))
		end
	end, {
		nargs = "*",
		desc = "GitHub pull requests: :PR [owner/name] [number]",
		complete = function()
			return { "review", "done", "files", "install", "pick", "close", "toggle", "refresh" }
		end,
	})
end

return M
