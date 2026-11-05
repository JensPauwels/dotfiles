local api = vim.api
local H = {}

local here = debug.getinfo(1, "S").source:sub(2)
H.dir = vim.fn.fnamemodify(here, ":p:h")

H.P = require("pulls")
H.patch = require("pulls.patch")
require("pulls.gh").bin = H.dir .. "/bin/gh"
H.P.setup({})

H.notes = {}

function H.read_file(path)
	local f = assert(io.open(path, "rb"))
	local s = f:read("*a")
	f:close()
	return s
end

--- Calls made to the fake gh, each as a list of arguments.
function H.calls()
	local f = io.open(vim.env.PULLS_GH_LOG, "rb")
	if not f then
		return {}
	end
	local s = f:read("*a")
	f:close()
	local out = {}
	for rec in s:gmatch("([^\30]*)\30") do
		local args = {}
		for a in rec:gmatch("([^\31]*)\31") do
			args[#args + 1] = a
		end
		out[#out + 1] = args
	end
	return out
end

--- Last call whose first two arguments match, or nil.
function H.call(a, b)
	local calls = H.calls()
	for i = #calls, 1, -1 do
		if calls[i][1] == a and (b == nil or calls[i][2] == b) then
			return calls[i]
		end
	end
	return nil
end

--- Value following `flag` in an argument list, or of the form flag key=value.
function H.arg(args, key)
	for i, a in ipairs(args) do
		if a == key then
			return args[i + 1]
		end
		if (args[i - 1] == "-f" or args[i - 1] == "-F") and a:match("^" .. vim.pesc(key) .. "=") then
			return a:sub(#key + 2)
		end
	end
	return nil
end

function H.wait()
	assert(H.P.wait(10000), "timed out waiting for gh")
end

function H.state()
	return assert(H.P._state(), "view is not open")
end

function H.open(opts)
	H.P.open(opts)
	H.wait()
	return H.state()
end

function H.panel_lines()
	return api.nvim_buf_get_lines(H.state().panel.buf, 0, -1, false)
end

function H.main_lines()
	local s = H.state()
	return api.nvim_buf_get_lines(api.nvim_win_get_buf(s.main.win), 0, -1, false)
end

--- Put the panel cursor on the first line matching `pat`.
function H.select(pat)
	local s = H.state()
	api.nvim_set_current_win(s.panel.win)
	for lnum, l in ipairs(H.panel_lines()) do
		if l:find(pat) then
			api.nvim_win_set_cursor(s.panel.win, { lnum, 0 })
			vim.cmd("doautocmd CursorMoved")
			H.wait()
			return
		end
	end
	error("no panel line matching " .. pat, 2)
end

function H.keys(str)
	api.nvim_feedkeys(api.nvim_replace_termcodes(str, true, false, true), "x", false)
	H.wait()
end

--- Open PR 7 and show src/app.lua in the main window, focused.
function H.open_file(pat)
	H.open({ repo = "acme/widgets", number = 7 })
	H.select(pat or "src/app%.lua")
	api.nvim_set_current_win(H.state().main.win)
end

--- Extmarks of the main buffer by 1-based row: line_hl, hl (list), virt (text).
function H.marks()
	local s = H.state()
	local buf = api.nvim_win_get_buf(s.main.win)
	local out = {}
	for _, m in ipairs(api.nvim_buf_get_extmarks(buf, api.nvim_create_namespace("pulls"), 0, -1, { details = true })) do
		local row, d = m[2] + 1, m[4]
		out[row] = out[row] or { hl = {}, virt = {} }
		if d.line_hl_group then
			out[row].line_hl = d.line_hl_group
		end
		if d.hl_group then
			table.insert(out[row].hl, { m[3] + 1, d.end_col, d.hl_group })
		end
		for _, vl in ipairs(d.virt_lines or {}) do
			local text = ""
			for _, ch in ipairs(vl) do
				text = text .. ch[1]
			end
			table.insert(out[row].virt, text)
		end
	end
	return out
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

--- True when some line of `lines` matches `pat`.
function H.has(lines, pat)
	for _, l in ipairs(lines) do
		if l:find(pat) then
			return true
		end
	end
	return false
end

function H.note(pat)
	for i = #H.notes, 1, -1 do
		if H.notes[i]:find(pat) then
			return H.notes[i]
		end
	end
	return nil
end

--- Type `text` into the compose buffer that is now current and send it.
function H.send(text)
	local buf = api.nvim_get_current_buf()
	H.match(api.nvim_buf_get_name(buf), "pulls://compose")
	vim.cmd("stopinsert")
	api.nvim_buf_set_lines(buf, 0, -1, false, vim.split(text, "\n"))
	vim.cmd("write")
	H.wait()
end

local orig = {}

function H.before_each()
	if H.P._state() then
		H.P.close()
	end
	H.notes = {}
	vim.env.PULLS_GH_LOG = vim.fn.tempname()
	require("pulls.recent").file = vim.fn.tempname() .. "/recent.json"
	require("pulls.review").file = vim.fn.tempname() .. "/review.json"
	require("pulls.review")._reset()
	vim.env.PULLS_FAKE_BRANCH = nil
	orig.notify, orig.confirm, orig.input, orig.open, orig.select =
		vim.notify, vim.fn.confirm, vim.ui.input, vim.ui.open, vim.ui.select
	vim.notify = function(msg)
		H.notes[#H.notes + 1] = msg
	end
	vim.fn.confirm = function()
		return 1
	end
	vim.ui.open = function(url)
		H.opened = url
	end
end

function H.after_each()
	require("pulls.review")._reset()
	if H.P._state() then
		H.P.close()
	end
	vim.notify, vim.fn.confirm, vim.ui.input, vim.ui.open, vim.ui.select =
		orig.notify, orig.confirm, orig.input, orig.open, orig.select
	vim.fn.delete(vim.env.PULLS_GH_LOG)
end

return H
