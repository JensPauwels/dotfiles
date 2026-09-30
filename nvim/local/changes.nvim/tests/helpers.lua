local api = vim.api
local H = {}

H.C = require("changes")
H.C.setup({ blame_delay = 10 })

H.notes = {}
local dirs = {}

--- @param root string
--- @param ... string
--- @return string stdout
function H.git(root, ...)
	local res = vim.system({ "git", ... }, { cwd = root, text = true }):wait()
	assert(res.code == 0, "git " .. table.concat({ ... }, " ") .. " failed: " .. (res.stderr or ""))
	return res.stdout or ""
end

function H.write(root, rel, content)
	local full = root .. "/" .. rel
	vim.fn.mkdir(vim.fs.dirname(full), "p")
	local f = assert(io.open(full, "wb"))
	f:write(content)
	f:close()
end

function H.read(root, rel)
	local f = io.open(root .. "/" .. rel, "rb")
	if not f then
		return nil
	end
	local s = f:read("*a")
	f:close()
	return s
end

local function lines(n, prefix)
	local t = {}
	for i = 1, n do
		t[i] = (prefix or "line") .. i
	end
	return table.concat(t, "\n") .. "\n"
end

--- A fresh repository with one commit.
--- @return string root
function H.repo()
	local dir = vim.fn.tempname()
	vim.fn.mkdir(dir, "p")
	dir = vim.uv.fs_realpath(dir) or dir
	dirs[#dirs + 1] = dir
	H.git(dir, "init", "-q", "-b", "main")
	H.git(dir, "config", "user.email", "test@example.com")
	H.git(dir, "config", "user.name", "Test User")
	H.write(dir, "a.lua", lines(20))
	H.write(dir, "b.tf", "hostnames = [var.oauth2_redirect_domain]\n\tindented\tline\n")
	H.write(dir, "gone.txt", "gone\n")
	H.write(dir, "s.txt", "staged before\n")
	H.git(dir, "add", "-A")
	H.git(dir, "commit", "-q", "-m", "init")
	return dir
end

--- The standard dirty state most tests start from:
---   a.lua   line2 changed, line10 deleted, "inserted A/B" after line19
---   b.tf    first line changed
---   gone.txt deleted, new.txt untracked, s.txt modified and staged
function H.dirty(root)
	local a = vim.split(lines(20), "\n", { trimempty = true })
	a[2] = "line2 changed"
	table.remove(a, 10)
	table.insert(a, 19, "inserted A")
	table.insert(a, 20, "inserted B")
	H.write(root, "a.lua", table.concat(a, "\n") .. "\n")
	H.write(root, "b.tf", "hostnames = [local.oauth2_redirect_domains]\n\tindented\tline\n")
	vim.fn.delete(root .. "/gone.txt")
	H.write(root, "new.txt", "brand new\n")
	H.write(root, "s.txt", "staged after\n")
	H.git(root, "add", "s.txt")
end

function H.wait()
	assert(H.C.wait(10000), "timed out waiting for git")
end

--- @return changes.State
function H.open(root)
	vim.cmd("cd " .. vim.fn.fnameescape(root))
	H.C.open()
	H.wait()
	return assert(H.C._state())
end

function H.state()
	return assert(H.C._state(), "view is not open")
end

function H.panel_lines()
	return api.nvim_buf_get_lines(H.state().panel.buf, 0, -1, false)
end

function H.view_lines()
	return api.nvim_buf_get_lines(H.state().view.buf, 0, -1, false)
end

--- Move the panel cursor to the entry matching `pat` (in the Staged group
--- when `staged`), let the diff load, and return it.
function H.select(pat, staged)
	local s = H.state()
	api.nvim_set_current_win(s.panel.win)
	local in_staged = false
	for lnum, l in ipairs(H.panel_lines()) do
		if l:match("^ Staged") then
			in_staged = true
		elseif l:match("^ %u") then
			in_staged = false
		end
		if l:match(pat) and in_staged == (staged or false) then
			api.nvim_win_set_cursor(s.panel.win, { lnum, 0 })
			vim.cmd("doautocmd CursorMoved")
			H.wait()
			return s.current
		end
	end
	error("no panel entry matching " .. pat .. (staged and " (staged)" or ""), 2)
end

--- Select an entry and focus the diff window.
function H.view(pat, staged)
	H.select(pat, staged)
	api.nvim_set_current_win(H.state().view.win)
end

function H.cursor(line, col)
	api.nvim_win_set_cursor(H.state().view.win, { line, col or 0 })
end

function H.keys(str)
	api.nvim_feedkeys(api.nvim_replace_termcodes(str, true, false, true), "x", false)
	H.wait()
end

--- Rendering summary of the diff buffer: for each 1-based row a table with
--- add = true, word = { s, e }, del = { "old line", ... } (virtual lines
--- attached above or below), del_word = { "highlighted part", ... }.
function H.marks()
	local s = H.state()
	local ns = api.nvim_create_namespace("changes")
	local out = {}
	for _, m in ipairs(api.nvim_buf_get_extmarks(s.view.buf, ns, 0, -1, { details = true })) do
		local row, d = m[2] + 1, m[4]
		out[row] = out[row] or {}
		if d.line_hl_group == "ChangesAdd" then
			out[row].add = true
		end
		if d.hl_group == "ChangesAddWord" then
			out[row].word = { m[3] + 1, d.end_col }
		end
		if d.virt_lines then
			out[row].del, out[row].del_word = {}, {}
			for _, vl in ipairs(d.virt_lines) do
				local text = ""
				for _, ch in ipairs(vl) do
					text = text .. ch[1]
					if ch[2] == "ChangesDeleteWord" then
						table.insert(out[row].del_word, ch[1])
					end
				end
				table.insert(out[row].del, (text:gsub("%s+$", "")))
			end
			out[row].del_above = d.virt_lines_above or false
		end
	end
	return out
end

function H.blame_text()
	local s = H.state()
	local ns = api.nvim_create_namespace("changes.blame")
	local marks = api.nvim_buf_get_extmarks(s.view.buf, ns, 0, -1, { details = true })
	if #marks == 0 then
		return nil
	end
	return vim.trim(marks[1][4].virt_text[1][1])
end

--- Closed folds in the diff window as { {first, last}, ... }.
function H.folds()
	local s = H.state()
	local out = {}
	api.nvim_win_call(s.view.win, function()
		local n = api.nvim_buf_line_count(s.view.buf)
		local i = 1
		while i <= n do
			local c = vim.fn.foldclosed(i)
			if c == i then
				out[#out + 1] = { c, vim.fn.foldclosedend(i) }
				i = vim.fn.foldclosedend(i) + 1
			else
				i = i + 1
			end
		end
	end)
	return out
end

function H.status(root)
	return (H.git(root, "status", "--short"):gsub("\n$", ""))
end

function H.eq(actual, expected, msg)
	if not vim.deep_equal(actual, expected) then
		error(
			(msg or "values differ")
				.. "\n  expected: "
				.. vim.inspect(expected)
				.. "\n  actual:   "
				.. vim.inspect(actual),
			2
		)
	end
end

function H.truthy(v, msg)
	if not v then
		error(msg or "expected a truthy value", 2)
	end
end

function H.match(str, pat, msg)
	if not tostring(str):find(pat) then
		error((msg or "no match") .. "\n  pattern: " .. pat .. "\n  string:  " .. tostring(str), 2)
	end
end

--- Last notification whose text matches pat, or nil.
function H.note(pat)
	for i = #H.notes, 1, -1 do
		if H.notes[i]:find(pat) then
			return H.notes[i]
		end
	end
	return nil
end

--- Stub vim.ui.select to pick the item whose label matches `pat`.
function H.ui_select(pat)
	vim.ui.select = function(items, opts, cb)
		for _, it in ipairs(items) do
			if opts.format_item(it):find(pat) then
				cb(it)
				return
			end
		end
		cb(nil)
	end
end

function H.ui_input(text)
	vim.ui.input = function(_, cb)
		cb(text)
	end
end

local orig = {}

function H.before_each()
	if H.C._state() then
		H.C.close()
	end
	H.notes = {}
	orig.notify, orig.confirm, orig.select, orig.input = vim.notify, vim.fn.confirm, vim.ui.select, vim.ui.input
	vim.notify = function(msg)
		H.notes[#H.notes + 1] = msg
	end
	vim.fn.confirm = function()
		return 1
	end
end

function H.after_each()
	if H.C._state() then
		H.C.close()
	end
	vim.notify, vim.fn.confirm, vim.ui.select, vim.ui.input = orig.notify, orig.confirm, orig.select, orig.input
	for _, d in ipairs(dirs) do
		vim.fn.delete(d, "rf")
	end
	dirs = {}
	-- wipe buffers the tests may have loaded
	for _, b in ipairs(api.nvim_list_bufs()) do
		if api.nvim_buf_get_name(b):match("^/") then
			pcall(api.nvim_buf_delete, b, { force = true })
		end
	end
end

return H
