-- Pure helpers: parse the unified diff GitHub returns for a pull request,
-- word-level diff of changed lines, review threads, text wrapping, times.
local M = {}

--- @class pulls.Line
--- @field kind " "|"+"|"-"|"@"   "@" is the hunk header
--- @field old integer|nil        line number on the base side
--- @field new integer|nil        line number on the head side
--- @field text string

--- @class pulls.File
--- @field path string       path on the head side (base side for deletions)
--- @field old_path string
--- @field status "A"|"M"|"D"|"R"
--- @field binary boolean
--- @field additions integer
--- @field deletions integer
--- @field lines pulls.Line[] every hunk header and line of the file, in order

--- Undo git's C-style quoting of unusual paths: "a/caf\303\251.txt".
local function unquote(p)
	if p:sub(1, 1) ~= '"' then
		return p
	end
	p = p:sub(2, -2)
	local escapes = { n = "\n", t = "\t", ['"'] = '"', ["\\"] = "\\" }
	return (
		p:gsub("\\(%d%d%d)", function(o)
			return string.char(tonumber(o, 8))
		end):gsub("\\(.)", function(c)
			return escapes[c] or c
		end)
	)
end

local function strip_prefix(p)
	p = unquote(p)
	if p == "/dev/null" then
		return nil
	end
	return (p:gsub("^[ab]/", ""))
end

--- Best guess at the two paths of `diff --git a/x b/x` when no ---/+++ lines
--- follow (binary files, pure renames). Both sides are equal unless renamed.
local function header_paths(rest)
	local a, b = rest:match('^(".-")%s+(".-")$')
	if a then
		return strip_prefix(a), strip_prefix(b)
	end
	-- "a/foo bar b/foo bar": split in the middle when both halves match
	local n = #rest
	if n % 2 == 1 then
		local half = (n - 1) / 2
		local left, right = rest:sub(1, half), rest:sub(half + 2)
		if left:sub(3) == right:sub(3) then
			return strip_prefix(left), strip_prefix(right)
		end
	end
	a, b = rest:match("^(%S+)%s+(%S+)$")
	if a then
		return strip_prefix(a), strip_prefix(b)
	end
	return rest, rest
end

--- @param text string  output of `gh pr diff`
--- @return pulls.File[]
function M.parse(text)
	local files = {}
	local f -- current file
	local old_ln, new_ln = 0, 0
	local in_hunk = false
	text = text:gsub("\r\n", "\n"):gsub("\n$", "")
	for line in (text .. "\n"):gmatch("(.-)\n") do
		local rest = line:match("^diff %-%-git (.*)$")
		if rest then
			local a, b = header_paths(rest)
			f = {
				path = b or a,
				old_path = a or b,
				status = "M",
				binary = false,
				additions = 0,
				deletions = 0,
				lines = {},
			}
			files[#files + 1] = f
			in_hunk = false
		elseif f and not in_hunk and line:match("^new file mode") then
			f.status = "A"
		elseif f and not in_hunk and line:match("^deleted file mode") then
			f.status = "D"
		elseif f and not in_hunk and line:match("^rename from ") then
			f.old_path = unquote(line:sub(13))
			f.status = "R"
		elseif f and not in_hunk and line:match("^rename to ") then
			f.path = unquote(line:sub(11))
			f.status = "R"
		elseif f and not in_hunk and line:match("^Binary files ") then
			f.binary = true
		elseif f and not in_hunk and line:match("^%-%-%- ") then
			local p = strip_prefix(line:sub(5))
			if p then
				f.old_path = p
			else
				f.status = "A"
			end
		elseif f and not in_hunk and line:match("^%+%+%+ ") then
			local p = strip_prefix(line:sub(5))
			if p then
				f.path = p
			else
				f.status = "D"
				f.path = f.old_path
			end
		elseif f and line:match("^@@ ") then
			local a, b = line:match("^@@ %-(%d+)[,%d]* %+(%d+)[,%d]* @@")
			old_ln, new_ln = tonumber(a) or 1, tonumber(b) or 1
			in_hunk = true
			f.lines[#f.lines + 1] = { kind = "@", text = line }
		elseif f and in_hunk then
			local c, body = line:sub(1, 1), line:sub(2)
			if c == "+" then
				f.lines[#f.lines + 1] = { kind = "+", new = new_ln, text = body }
				new_ln = new_ln + 1
				f.additions = f.additions + 1
			elseif c == "-" then
				f.lines[#f.lines + 1] = { kind = "-", old = old_ln, text = body }
				old_ln = old_ln + 1
				f.deletions = f.deletions + 1
			elseif c == " " or line == "" then
				f.lines[#f.lines + 1] = { kind = " ", old = old_ln, new = new_ln, text = body }
				old_ln, new_ln = old_ln + 1, new_ln + 1
			elseif c == "\\" then
				-- "\ No newline at end of file": nothing to show
			else
				in_hunk = false
			end
		end
	end
	return files
end

--- Byte range (1-based, inclusive) that differs between two lines, common
--- prefix and suffix stripped, aligned to UTF-8 boundaries. nil when the
--- lines share too little for highlighting to help.
--- @return { a_s: integer, a_e: integer, b_s: integer, b_e: integer }|nil
function M.word_diff(a, b)
	local la, lb = #a, #b
	if la == 0 or lb == 0 then
		return nil
	end
	local p = 0
	while p < la and p < lb and a:byte(p + 1) == b:byte(p + 1) do
		p = p + 1
	end
	local s = 0
	while s < la - p and s < lb - p and a:byte(la - s) == b:byte(lb - s) do
		s = s + 1
	end
	if (p + s) * 4 < math.min(la, lb) then
		return nil
	end
	if p < la and p < lb then
		p = p + vim.str_utf_start(a, p + 1)
	end
	if s > 0 then
		s = s - vim.str_utf_end(a, la - s)
	end
	p, s = math.max(p, 0), math.max(s, 0)
	return { a_s = p + 1, a_e = la - s, b_s = p + 1, b_e = lb - s }
end

--- Pairs of (removed, added) line indexes in `lines` that should get word
--- highlighting: a run of removed lines directly followed by a run of added
--- lines of the same length.
--- @param lines pulls.Line[]
--- @return integer[][]
function M.word_pairs(lines)
	local pairs_, i, n = {}, 1, #lines
	while i <= n do
		if lines[i].kind == "-" then
			local d1 = i
			while i <= n and lines[i].kind == "-" do
				i = i + 1
			end
			local a1 = i
			while i <= n and lines[i].kind == "+" do
				i = i + 1
			end
			local nd, na = a1 - d1, i - a1
			if nd == na then
				for k = 0, nd - 1 do
					pairs_[#pairs_ + 1] = { d1 + k, a1 + k }
				end
			end
		else
			i = i + 1
		end
	end
	return pairs_
end

--- @class pulls.Comment
--- @field id integer
--- @field author string
--- @field body string
--- @field created_at string
--- @field path string
--- @field line integer|nil        nil when the comment is outdated
--- @field original_line integer|nil
--- @field side "LEFT"|"RIGHT"
--- @field in_reply_to_id integer|nil

--- @class pulls.Thread
--- @field id integer   id of the first comment, used to reply
--- @field path string
--- @field line integer|nil
--- @field original_line integer|nil
--- @field side "LEFT"|"RIGHT"
--- @field outdated boolean
--- @field comments pulls.Comment[]

--- Group review comments (REST API objects) into threads per file.
--- @param raw table[]
--- @return table<string, pulls.Thread[]>
function M.threads(raw)
	local by_id, roots = {}, {}
	table.sort(raw, function(a, b)
		return (a.created_at or "") < (b.created_at or "")
	end)
	for _, c in ipairs(raw) do
		local comment = {
			id = c.id,
			author = c.user and c.user.login or "ghost",
			body = (c.body or ""):gsub("\r\n", "\n"),
			created_at = c.created_at or "",
			path = c.path,
			line = c.line ~= vim.NIL and c.line or nil,
			original_line = c.original_line ~= vim.NIL and c.original_line or nil,
			side = c.side ~= vim.NIL and c.side or "RIGHT",
			in_reply_to_id = c.in_reply_to_id ~= vim.NIL and c.in_reply_to_id or nil,
		}
		local parent = comment.in_reply_to_id and by_id[comment.in_reply_to_id]
		if parent then
			table.insert(parent.comments, comment)
			by_id[comment.id] = parent
		else
			local t = {
				id = comment.id,
				path = comment.path,
				line = comment.line,
				original_line = comment.original_line,
				side = comment.side,
				outdated = comment.line == nil,
				comments = { comment },
			}
			by_id[comment.id] = t
			roots[#roots + 1] = t
		end
	end
	local out = {}
	for _, t in ipairs(roots) do
		out[t.path] = out[t.path] or {}
		table.insert(out[t.path], t)
	end
	return out
end

--- Index into `lines` where a thread belongs, nil when the line is not part
--- of the diff.
--- @param lines pulls.Line[]
--- @param t pulls.Thread
--- @return integer|nil
function M.thread_row(lines, t)
	if not t.line then
		return nil
	end
	for i, l in ipairs(lines) do
		if t.side == "LEFT" then
			if l.old == t.line and l.kind ~= "+" then
				return i
			end
		elseif l.new == t.line and l.kind ~= "-" then
			return i
		end
	end
	return nil
end

--- Word-wrap text to `width` display cells, keeping blank lines and
--- indentation of each source line.
--- @param text string
--- @param width integer
--- @return string[]
function M.wrap(text, width)
	local out = {}
	width = math.max(width, 10)
	for _, src in ipairs(vim.split(text, "\n", { plain = true })) do
		src = src:gsub("%s+$", ""):gsub("\t", "    ")
		if vim.fn.strdisplaywidth(src) <= width then
			out[#out + 1] = src
		else
			local indent = src:match("^%s*")
			local cur = ""
			for word in src:gmatch("%S+") do
				local candidate = cur == "" and (indent .. word) or (cur .. " " .. word)
				if cur ~= "" and vim.fn.strdisplaywidth(candidate) > width then
					out[#out + 1] = cur
					cur = indent .. word
				else
					cur = candidate
				end
			end
			out[#out + 1] = cur
		end
	end
	while #out > 0 and out[#out] == "" do
		table.remove(out)
	end
	return out
end

--- Unix time of an ISO 8601 UTC timestamp like 2026-11-04T09:39:35Z.
--- @param iso string
--- @return integer|nil
function M.parse_time(iso)
	local y, mo, d, h, mi, s = (iso or ""):match("^(%d+)-(%d+)-(%d+)T(%d+):(%d+):(%d+)")
	if not y then
		return nil
	end
	-- days from civil (Howard Hinnant), avoids os.time's local timezone
	y, mo, d = tonumber(y), tonumber(mo), tonumber(d)
	y = mo <= 2 and y - 1 or y
	local era = math.floor(y / 400)
	local yoe = y - era * 400
	local doy = math.floor((153 * (mo + (mo > 2 and -3 or 9)) + 2) / 5) + d - 1
	local doe = yoe * 365 + math.floor(yoe / 4) - math.floor(yoe / 100) + doy
	local days = era * 146097 + doe - 719468
	return days * 86400 + tonumber(h) * 3600 + tonumber(mi) * 60 + tonumber(s)
end

--- "3 hours ago" for an ISO timestamp.
--- @param iso string
--- @param now? integer
--- @return string
function M.ago(iso, now)
	local t = M.parse_time(iso)
	if not t then
		return ""
	end
	local d = (now or os.time()) - t
	if d < 45 then
		return "just now"
	end
	local units = {
		{ 60, "minute" },
		{ 3600, "hour" },
		{ 86400, "day" },
		{ 604800, "week" },
		{ 2592000, "month" },
		{ 31536000, "year" },
	}
	for i = #units, 1, -1 do
		local secs, name = units[i][1], units[i][2]
		if d >= secs or i == 1 then
			local n = math.max(1, math.floor(d / secs + 0.5))
			return string.format("%d %s%s ago", n, name, n == 1 and "" or "s")
		end
	end
	return "just now"
end

--- Summary of statusCheckRollup: counts and the individual checks.
--- @param rollup table[]|nil
--- @return { pass: integer, fail: integer, pending: integer, skipped: integer, checks: { name: string, state: string, url: string|nil }[] }
function M.checks(rollup)
	local res = { pass = 0, fail = 0, pending = 0, skipped = 0, checks = {} }
	for _, c in ipairs(type(rollup) == "table" and rollup or {}) do
		local name, state
		if c.__typename == "StatusContext" then
			name = c.context or "?"
			local st = c.state or ""
			state = (st == "SUCCESS" and "pass") or ((st == "PENDING" or st == "EXPECTED") and "pending") or "fail"
		else
			name = c.workflowName and c.workflowName ~= "" and (c.workflowName .. " / " .. (c.name or "?"))
				or (c.name or "?")
			local concl = c.conclusion ~= vim.NIL and c.conclusion or ""
			if c.status ~= "COMPLETED" then
				state = "pending"
			elseif concl == "SUCCESS" or concl == "NEUTRAL" then
				state = "pass"
			elseif concl == "SKIPPED" then
				state = "skipped"
			else
				state = "fail"
			end
		end
		res[state] = res[state] + 1
		res.checks[#res.checks + 1] =
			{ name = name, state = state, url = c.detailsUrl ~= vim.NIL and c.detailsUrl or c.targetUrl }
	end
	local order = { fail = 1, pending = 2, pass = 3, skipped = 4 }
	table.sort(res.checks, function(a, b)
		if order[a.state] ~= order[b.state] then
			return order[a.state] < order[b.state]
		end
		return a.name < b.name
	end)
	return res
end

return M
