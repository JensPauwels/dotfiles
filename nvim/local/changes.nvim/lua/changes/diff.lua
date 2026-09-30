-- Pure diff helpers: line splitting, hunk computation, per-line word diff.
local M = {}

--- Split file contents into lines, remembering whether the last line lacked
--- a trailing newline (needed to build patches git accepts).
--- @param text string|nil
--- @return string[] lines, boolean noeol
function M.split(text)
	if text == nil or text == "" then
		return {}, false
	end
	local noeol = text:sub(-1) ~= "\n"
	local lines = vim.split(text, "\n", { plain = true })
	if not noeol then
		table.remove(lines) -- drop the empty string after the final newline
	end
	return lines, noeol
end

--- @param old string
--- @param new string
--- @param algorithm? string
--- @return integer[][] hunks  each { start_a, count_a, start_b, count_b }
function M.hunks(old, new, algorithm)
	return vim.diff(old, new, {
		result_type = "indices",
		algorithm = algorithm or "histogram",
		indent_heuristic = true,
	}) --[[@as integer[][] ]]
end

--- Byte range (1-based, inclusive) that differs between two lines, with the
--- common prefix and suffix stripped. Ranges are aligned to UTF-8 boundaries.
--- Returns nil when the lines share too little to make highlighting useful.
--- @param a string
--- @param b string
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
	-- Lines that have almost nothing in common are better shown as plain
	-- removed/added lines.
	if (p + s) * 4 < math.min(la, lb) then
		return nil
	end
	-- Never start a range in the middle of a multibyte character.
	if p < la and p < lb then
		p = p + vim.str_utf_start(a, p + 1)
	end
	if s > 0 and la - s + 1 <= la then
		s = s - vim.str_utf_end(a, la - s)
	end
	if p < 0 then
		p = 0
	end
	if s < 0 then
		s = 0
	end
	return { a_s = p + 1, a_e = la - s, b_s = p + 1, b_e = lb - s }
end

--- Expand tabs to spaces so a line can be drawn as virtual text.
--- @param s string
--- @param ts integer
--- @return string
function M.expand_tabs(s, ts)
	if not s:find("\t") then
		return s
	end
	local out, col = {}, 0
	for ch in s:gmatch("[%z\1-\127\194-\244][\128-\191]*") do
		if ch == "\t" then
			local n = ts - (col % ts)
			out[#out + 1] = string.rep(" ", n)
			col = col + n
		else
			out[#out + 1] = ch
			col = col + vim.fn.strdisplaywidth(ch)
		end
	end
	return table.concat(out)
end

--- Line ranges (1-based, inclusive, in "new" coordinates) that stay visible
--- around hunks; everything else gets folded as "hidden lines".
--- @param hunks integer[][]
--- @param n integer  number of lines in the new file
--- @param ctx integer
--- @return integer[][] hidden  list of { first, last }
function M.hidden_ranges(hunks, n, ctx)
	local visible = {}
	for _, h in ipairs(hunks) do
		local sb, cb = h[3], h[4]
		local first, last
		if cb > 0 then
			first, last = sb - ctx, sb + cb - 1 + ctx
		else
			first, last = sb + 1 - ctx, sb + ctx
		end
		first = math.max(first, 1)
		last = math.min(last, n)
		if first <= last then
			if #visible > 0 and first <= visible[#visible][2] + 1 then
				visible[#visible][2] = math.max(visible[#visible][2], last)
			else
				visible[#visible + 1] = { first, last }
			end
		end
	end
	local hidden, cursor = {}, 1
	for _, v in ipairs(visible) do
		if v[1] > cursor then
			hidden[#hidden + 1] = { cursor, v[1] - 1 }
		end
		cursor = v[2] + 1
	end
	if cursor <= n then
		hidden[#hidden + 1] = { cursor, n }
	end
	return hidden
end

--- Trim a hunk to the selected lines l1..l2 (new-file coordinates), the way
--- "stage selected lines" works in VSCode. Added lines inside the selection
--- are kept. The hunk's removed lines are kept only when the selection
--- reaches the top of the hunk (that is where they are drawn), or always
--- for a pure deletion.
--- @param hunk integer[]
--- @param old string[]
--- @param old_noeol boolean
--- @param new string[]
--- @param new_noeol boolean
--- @param l1 integer
--- @param l2 integer
--- @return changes.PatchSide|nil removed, changes.PatchSide|nil added, integer a1, integer a2, boolean include_removed
function M.partial_hunk(hunk, old, old_noeol, new, new_noeol, l1, l2)
	local sa, ca, sb, cb = hunk[1], hunk[2], hunk[3], hunk[4]
	local first, last = sb, sb + cb - 1
	if cb == 0 then
		first, last = math.max(sb, 1), sb + 1
	end
	if l2 < first or l1 > last then
		return nil
	end
	local include_removed = ca > 0 and (cb == 0 or l1 <= sb)
	local a1, a2 = math.max(l1, sb), math.min(l2, sb + cb - 1)
	local added_lines = {}
	for i = a1, a2 do
		added_lines[#added_lines + 1] = new[i]
	end
	local removed_lines = {}
	if include_removed then
		for i = sa, sa + ca - 1 do
			removed_lines[#removed_lines + 1] = old[i]
		end
	end
	if #added_lines == 0 and #removed_lines == 0 then
		return nil
	end
	local removed_start
	if include_removed or ca == 0 then
		removed_start = sa
	else
		removed_start = sa + ca - 1 -- keep the old lines, insert after them
	end
	local removed = {
		start = removed_start,
		lines = removed_lines,
		noeol = old_noeol and include_removed and sa + ca - 1 == #old,
	}
	local added = {
		start = cb > 0 and a1 or sb,
		lines = added_lines,
		noeol = new_noeol and #added_lines > 0 and a2 == #new,
	}
	return removed, added, a1, a2, include_removed
end

--- Human readable "3 hours ago" for a unix timestamp.
--- @param time integer
--- @param now? integer
--- @return string
function M.relative_time(time, now)
	local d = (now or os.time()) - time
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

return M
