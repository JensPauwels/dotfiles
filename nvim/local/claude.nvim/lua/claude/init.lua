-- claude.nvim: hand code to the Claude Code session running in tmux.
--
-- <leader>aa sends "@file lines 10-20 " for the cursor line or selection,
-- <leader>af the whole file, <leader>ad the line plus its diagnostics; then
-- focuses Claude so you can type the question. The Claude pane is found in
-- this tmux window, else this session (same directory first); when several
-- match you choose once and it is remembered.
local api = vim.api

local M = {}

M.config = {
	focus = true, -- jump to the Claude pane after sending
}

--- @type string|nil remembered pane id
local target

local function notify(msg, level)
	vim.notify(msg, level or vim.log.levels.INFO, { title = "claude" })
end

local function tmux(args)
	local cmd = { "tmux" }
	vim.list_extend(cmd, args)
	local r = vim.system(cmd, { text = true }):wait()
	return r.code == 0, vim.trim(r.stdout or ""), vim.trim(r.stderr or "")
end

--- Claude panes: { id, title, path, window, here }.
function M.panes()
	local ok, out = tmux({
		"list-panes",
		"-s",
		"-F",
		"#{pane_id}\t#{pane_current_command}\t#{pane_title}\t#{pane_current_path}\t#{window_index}\t#{window_active}",
	})
	if not ok then
		return {}
	end
	local cwd = vim.fn.getcwd()
	local list = {}
	for line in out:gmatch("[^\n]+") do
		local id, cmd, title, path, window, active = line:match("^(%S+)\t([^\t]*)\t([^\t]*)\t([^\t]*)\t(%d+)\t(%d)$")
		if id and (cmd:match("^claude") or title:match("^✳")) then
			list[#list + 1] = {
				id = id,
				title = title:gsub("^✳%s*", ""),
				path = path,
				window = window,
				here = active == "1",
				same_dir = path == cwd or vim.startswith(cwd, path .. "/") or vim.startswith(path, cwd .. "/"),
			}
		end
	end
	return list
end

local function alive(id)
	for _, p in ipairs(M.panes()) do
		if p.id == id then
			return true
		end
	end
	return false
end

--- Find (or ask for) the Claude pane, then cb(pane_id).
local function with_pane(cb)
	if not vim.env.TMUX then
		notify("Not inside tmux", vim.log.levels.WARN)
		return
	end
	if target and alive(target) then
		cb(target)
		return
	end
	local panes = M.panes()
	if #panes == 0 then
		notify("No Claude Code pane in this tmux session", vim.log.levels.WARN)
		return
	end
	local function pick(list)
		if #list == 1 then
			target = list[1].id
			cb(target)
			return true
		end
		return false
	end
	if pick(vim.tbl_filter(function(p) return p.here end, panes)) then
		return
	end
	if pick(vim.tbl_filter(function(p) return p.same_dir end, panes)) then
		return
	end
	if pick(panes) then
		return
	end
	vim.ui.select(panes, {
		prompt = "Which Claude session?",
		format_item = function(p)
			return string.format("window %s  %s  (%s)", p.window, p.title, vim.fn.fnamemodify(p.path, ":~"))
		end,
	}, function(p)
		if p then
			target = p.id
			cb(target)
		end
	end)
end

--- Type `text` into the Claude pane (not submitted) and focus it.
function M.send(text)
	with_pane(function(id)
		local ok, _, err = tmux({ "send-keys", "-t", id, "-l", "--", text })
		if not ok then
			notify("tmux send-keys failed: " .. err, vim.log.levels.ERROR)
			target = nil
			return
		end
		if M.config.focus then
			tmux({ "select-window", "-t", id })
			tmux({ "select-pane", "-t", id })
		end
	end)
end

local function path()
	local name = api.nvim_buf_get_name(0)
	if name == "" or vim.bo.buftype ~= "" then
		return nil
	end
	return vim.fn.fnamemodify(name, ":.")
end

--- Lines of the visual selection, or the cursor line.
local function range()
	local mode = vim.fn.mode()
	if mode == "v" or mode == "V" or mode == "\22" then
		local a, b = vim.fn.line("v"), vim.fn.line(".")
		api.nvim_feedkeys(api.nvim_replace_termcodes("<Esc>", true, false, true), "nx", false)
		return math.min(a, b), math.max(a, b)
	end
	local l = vim.fn.line(".")
	return l, l
end

--- "@path line 12 " / "@path lines 10-20 ".
function M.reference(l1, l2)
	local p = path()
	if not p then
		return nil
	end
	if l1 == l2 then
		return string.format("@%s line %d ", p, l1)
	end
	return string.format("@%s lines %d-%d ", p, l1, l2)
end

function M.send_here()
	local ref = M.reference(range())
	if not ref then
		notify("Not a file", vim.log.levels.WARN)
		return
	end
	M.send(ref)
end

function M.send_file()
	local p = path()
	if not p then
		notify("Not a file", vim.log.levels.WARN)
		return
	end
	M.send("@" .. p .. " ")
end

--- The line (or selection) with the diagnostics on it, ready to ask about.
function M.send_diagnostics()
	local l1, l2 = range()
	local ref = M.reference(l1, l2)
	if not ref then
		notify("Not a file", vim.log.levels.WARN)
		return
	end
	local msgs = {}
	for _, d in ipairs(vim.diagnostic.get(0)) do
		if d.lnum + 1 >= l1 and d.lnum + 1 <= l2 then
			msgs[#msgs + 1] = string.format("%s (line %d)", d.message:gsub("%s*\n%s*", " "), d.lnum + 1)
		end
	end
	if #msgs == 0 then
		notify("No diagnostics here", vim.log.levels.WARN)
		return
	end
	M.send(ref .. "has: " .. table.concat(msgs, "; ") .. " ")
end

--- Forget the remembered pane (choose again next time).
function M.reset()
	target = nil
end

function M.setup(opts)
	M.config = vim.tbl_deep_extend("force", M.config, opts or {})
	api.nvim_create_user_command("ClaudePane", function()
		M.reset()
		with_pane(function(id)
			notify("Sending to pane " .. id)
		end)
	end, { desc = "Choose the Claude Code pane to send to" })
end

return M
