local H = require("helpers")
local api = vim.api

return {
	{
		"lists pull requests of the current repository with a preview",
		function()
			local s = H.open()
			H.eq(s.repo, "acme/widgets")
			local lines = H.panel_lines()
			H.match(lines[1], "^ #7  Add widgets$")
			H.match(lines[2], "alice · .* ago ✗ changes requested")
			H.match(lines[3], "^ #8  Draft thing")
			H.match(lines[4], "bob · .* · draft")
			H.match(vim.wo[s.panel.win].winbar, "acme/widgets  ·  open")
			H.eq(H.main_lines()[1], "# Add widgets")
			H.truthy(H.has(H.main_lines(), "Press <CR>"))
			H.eq(H.arg(H.call("pr", "list"), "--state"), "open")
		end,
	},

	{
		"preview follows the cursor; s cycles the state filter",
		function()
			H.open()
			H.select("#8")
			H.eq(H.main_lines()[1], "# Draft thing")
			H.truthy(H.has(H.main_lines(), "^DRAFT"))
			H.keys("s")
			H.eq(H.arg(H.call("pr", "list"), "--state"), "merged")
			H.keys("s")
			H.keys("s")
			H.keys("s")
			H.eq(H.arg(H.call("pr", "list"), "--state"), "open")
		end,
	},

	{
		"f searches",
		function()
			H.open()
			vim.ui.input = function(_, cb)
				cb("review-requested:@me")
			end
			H.keys("f")
			H.eq(H.arg(H.call("pr", "list"), "--search"), "review-requested:@me")
			H.match(vim.wo[H.state().panel.win].winbar, "review%-requested:@me")
		end,
	},

	{
		"opening a pull request shows the overview and files",
		function()
			H.open()
			H.select("#7")
			H.keys("<CR>")
			local s = H.state()
			H.eq(s.screen, "pr")
			local panel = H.panel_lines()
			H.eq(panel, {
				"  Overview",
				"",
				" Files (5)  · 1/5 viewed",
				"   M  src/app.lua  +3 −2  ● 3",
				" ✓ A  docs/new.md  +2 −0",
				"   D  old.txt  +0 −1",
				"   R  b.txt  +0 −0",
				"   M  img.png  +0 −0",
			})
			local main = H.main_lines()
			H.eq(main[1], "# Add widgets")
			H.match(main[3], "^OPEN  #7  alice wants to merge feature into main$")
			H.truthy(H.has(main, "^Labels: bug$"))
			H.truthy(H.has(main, "^Review: changes requested  · waiting on @erin$"))
			H.truthy(H.has(main, "^Merge: no conflicts$"))
			H.truthy(H.has(main, "^## Checks  ✓ 1  ✗ 1  ● 1$"))
			H.truthy(H.has(main, "^  ✗ ci / test$"))
			H.truthy(H.has(main, "^Hello$") and H.has(main, "^World$"), "body with CRLF")
			H.truthy(H.has(main, "^  abcdef1  Add widgets  alice"))
			H.truthy(H.has(main, "^## Conversation %(2%)$"), "empty COMMENTED review is skipped")
			H.truthy(H.has(main, "^### carol commented"))
			H.truthy(H.has(main, "^### bob requested changes"))
			H.truthy(H.has(main, "^3 review threads on the changed files%.$"))
		end,
	},

	{
		":PR owner/name number opens directly; <BS> goes back to the list",
		function()
			H.open({ repo = "acme/widgets", number = 7 })
			H.eq(H.state().screen, "pr")
			H.eq(H.call("pr", "list"), nil, "list not fetched yet")
			api.nvim_set_current_win(H.state().panel.win)
			H.keys("<BS>")
			H.eq(H.state().screen, "list")
			H.match(H.panel_lines()[1], "#7")
		end,
	},

	{
		"diff renders added, removed, hunk and word highlights",
		function()
			H.open_file()
			local lines = H.main_lines()
			H.eq(lines, {
				"@@ -1,4 +1,5 @@ local M = {}",
				"local a = 1",
				"local b = 2",
				"local b = 3",
				"local c = 4",
				"local d = 5",
				"local e = 6",
				"@@ -10,3 +11,3 @@ function M.run()",
				"x()",
				"y()",
				"y(true)",
				"z()",
			})
			local m = H.marks()
			H.eq(m[1].line_hl, "PullsHunk")
			H.eq(m[3].line_hl, "PullsDelete")
			H.eq(m[4].line_hl, "PullsAdd")
			H.eq(m[2], nil, "context line has no marks")
			H.eq(m[11].hl, { { 3, 6, "PullsAddWord" } })
			H.match(vim.wo[H.state().main.win].winbar, "src/app%.lua  ·  %+3 −2  ·  3 threads")
		end,
	},

	{
		"status column shows old and new line numbers",
		function()
			H.open_file()
			local P = H.P
			local function col(lnum)
				vim.v.lnum = lnum
				return P.statuscol()
			end
			-- vim.v.virtnum is 0 outside of drawing
			H.eq(col(1), "       ")
			H.eq(col(2), "%#PullsLineNr# 1  1  %*")
			H.eq(col(3), "%#PullsLineNr# 2     %*")
			H.eq(col(4), "%#PullsLineNr#    2  %*")
			H.eq(col(12), "%#PullsLineNr#12 13  %*")
		end,
	},

	{
		"review threads are drawn under their lines, outdated ones at the end",
		function()
			H.open_file()
			local m = H.marks()
			H.match(m[5].virt[1], "╭─ alice · ")
			H.eq(m[5].virt[2], "  │ Why 4?")
			H.match(m[5].virt[3], "├─ bob")
			H.eq(m[5].virt[4], "  │ Because.")
			H.eq(m[5].virt[5], "  │ Really.")
			H.match(m[5].virt[6], "r to reply")
			H.match(m[3].virt[1], "carol")
			H.truthy(H.has(m[12].virt, "Outdated comments"))
			H.truthy(H.has(m[12].virt, "dave · .* · line 40"))
		end,
	},

	{
		"other files: new, deleted, binary, rename",
		function()
			H.open_file("docs/new%.md")
			H.eq(H.main_lines(), { "@@ -0,0 +1,2 @@", "# New", "text" })
			H.select("img%.png")
			H.eq(H.main_lines(), { "", "  Binary file, not shown." })
			H.select("b%.txt")
			H.eq(H.main_lines(), { "", "  Renamed without changes." })
			H.match(vim.wo[H.state().main.win].winbar, "a%.txt → b%.txt")
		end,
	},

	{
		"navigation: ]c, ]t, <Tab>",
		function()
			H.open_file()
			local win = H.state().main.win
			H.keys("gg]c")
			H.eq(api.nvim_win_get_cursor(win)[1], 3)
			H.keys("]c")
			H.eq(api.nvim_win_get_cursor(win)[1], 10)
			H.keys("[c")
			H.eq(api.nvim_win_get_cursor(win)[1], 3)
			H.keys("gg]t")
			H.eq(api.nvim_win_get_cursor(win)[1], 3)
			H.keys("]t")
			H.eq(api.nvim_win_get_cursor(win)[1], 5)
			H.keys("<Tab>")
			H.eq(H.main_lines()[2], "# New")
			H.keys("<S-Tab><S-Tab>")
			H.match(H.main_lines()[2], "Binary", "wraps to the last file")
		end,
	},
}
