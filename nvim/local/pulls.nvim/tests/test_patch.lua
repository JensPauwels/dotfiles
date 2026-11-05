local H = require("helpers")
local P = H.patch

local function kinds(f)
	local t = {}
	for _, l in ipairs(f.lines) do
		t[#t + 1] = l.kind
	end
	return table.concat(t)
end

return {
	{
		"parses files, statuses and line numbers",
		function()
			local files = P.parse(H.read_file(H.dir .. "/fixtures/diff.patch"))
			local summary = {}
			for _, f in ipairs(files) do
				summary[#summary + 1] = { f.status, f.old_path, f.path, f.additions, f.deletions, f.binary }
			end
			H.eq(summary, {
				{ "M", "src/app.lua", "src/app.lua", 3, 2, false },
				{ "A", "docs/new.md", "docs/new.md", 2, 0, false },
				{ "D", "old.txt", "old.txt", 0, 1, false },
				{ "R", "a.txt", "b.txt", 0, 0, false },
				{ "M", "img.png", "img.png", 0, 0, true },
			})
			local app = files[1]
			H.eq(kinds(app), "@ -++  @ -+ ")
			H.eq({ app.lines[3].old, app.lines[3].new }, { 2, nil })
			H.eq({ app.lines[5].old, app.lines[5].new, app.lines[5].text }, { nil, 3, "local c = 4" })
			H.eq({ app.lines[7].old, app.lines[7].new }, { 4, 5 })
			H.eq({ app.lines[12].old, app.lines[12].new, app.lines[12].text }, { 12, 13, "z()" })
			H.eq(kinds(files[3]), "@-", "no-newline marker is dropped")
		end,
	},

	{
		"paths with spaces and quotes",
		function()
			local files = P.parse(table.concat({
				"diff --git a/my file.txt b/my file.txt",
				"index 1..2 100644",
				"Binary files a/my file.txt and b/my file.txt differ",
				'diff --git "a/caf\\303\\251.txt" "b/caf\\303\\251.txt"',
				"new file mode 100644",
				"--- /dev/null",
				'+++ "b/caf\\303\\251.txt"',
				"@@ -0,0 +1 @@",
				"+x",
			}, "\n"))
			H.eq(files[1].path, "my file.txt")
			H.eq(files[2].path, "café.txt")
			H.eq(files[2].status, "A")
		end,
	},

	{
		"word pairs only for runs of equal length",
		function()
			local f = P.parse(H.read_file(H.dir .. "/fixtures/diff.patch"))[1]
			H.eq(P.word_pairs(f.lines), { { 10, 11 } })
			local w = P.word_diff("y()", "y(true)")
			H.eq({ w.b_s, w.b_e }, { 3, 6 })
			H.eq(P.word_diff("abc", "xyz"), nil)
		end,
	},

	{
		"threads group replies across pages and find their row",
		function()
			local raw = vim.json.decode(H.read_file(H.dir .. "/fixtures/comments.json"))
			local all = {}
			for _, page in ipairs(raw) do
				vim.list_extend(all, page)
			end
			local t = P.threads(all)["src/app.lua"]
			H.eq(#t, 3)
			H.eq(t[1].comments[1].author, "dave")
			H.eq(t[1].outdated, true)
			H.eq(#t[2].comments, 2)
			H.eq(t[2].comments[2].body, "Because.\nReally.")
			local f = P.parse(H.read_file(H.dir .. "/fixtures/diff.patch"))[1]
			H.eq(P.thread_row(f.lines, t[2]), 5, "RIGHT line 3")
			H.eq(P.thread_row(f.lines, t[3]), 3, "LEFT line 2 is the removed line")
			H.eq(P.thread_row(f.lines, t[1]), nil)
		end,
	},

	{
		"wrap, time and checks",
		function()
			H.eq(P.wrap("alpha beta gamma delta epsilon", 11), { "alpha beta", "gamma delta", "epsilon" })
			H.eq(P.wrap("a\n\n  b\n", 20), { "a", "", "  b" })
			H.eq(P.parse_time("1970-01-02T00:00:00Z"), 86400)
			H.eq(P.parse_time("2026-11-04T09:39:35Z"), 1793785175)
			H.eq(P.ago("2026-11-04T09:00:00Z", P.parse_time("2026-11-04T12:00:00Z")), "3 hours ago")
			local c = P.checks(vim.json.decode(H.read_file(H.dir .. "/fixtures/view.json")).statusCheckRollup)
			H.eq({ c.pass, c.fail, c.pending }, { 1, 1, 1 })
			H.eq(c.checks[1].name, "ci / test", "failures first")
		end,
	},

	{
		"parse_args",
		function()
			H.eq(H.P.parse_args({}), {})
			H.eq(H.P.parse_args({ "12" }), { number = 12 })
			H.eq(H.P.parse_args({ "#12" }), { number = 12 })
			H.eq(H.P.parse_args({ "neovim/neovim", "3" }), { repo = "neovim/neovim", number = 3 })
			H.eq(
				H.P.parse_args({ "https://github.com/a-b/c.d/pull/9/files" }),
				{ repo = "a-b/c.d", number = 9 }
			)
		end,
	},
}
