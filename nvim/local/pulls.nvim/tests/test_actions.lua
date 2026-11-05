local H = require("helpers")
local api = vim.api

local function posts()
	local out = {}
	for _, c in ipairs(H.calls()) do
		if c[1] == "api" and c[2] == "-X" then
			out[#out + 1] = c
		end
	end
	return out
end

return {
	{
		"c comments on an added line",
		function()
			H.open_file()
			api.nvim_win_set_cursor(H.state().main.win, { 5, 0 })
			H.keys("c")
			H.send("Looks good\nsecond line")
			local p = posts()[1]
			H.eq(p[4], "repos/acme/widgets/pulls/7/comments")
			H.eq(H.arg(p, "body"), "Looks good\nsecond line")
			H.eq(H.arg(p, "commit_id"), "abc123")
			H.eq(H.arg(p, "path"), "src/app.lua")
			H.eq(H.arg(p, "line"), "3")
			H.eq(H.arg(p, "side"), "RIGHT")
			H.eq(H.arg(p, "start_line"), nil)
			H.truthy(H.note("Comment sent"))
			H.eq(api.nvim_get_current_win(), H.state().main.win, "back in the diff")
			-- comments were reloaded
			local n = 0
			for _, c in ipairs(H.calls()) do
				if c[1] == "api" and c[2] == "--paginate" then
					n = n + 1
				end
			end
			H.eq(n, 2)
		end,
	},

	{
		"c on a removed line uses the LEFT side; a selection sends a range",
		function()
			H.open_file()
			api.nvim_win_set_cursor(H.state().main.win, { 3, 0 })
			H.keys("c")
			H.send("x")
			H.eq(H.arg(posts()[1], "side"), "LEFT")
			H.eq(H.arg(posts()[1], "line"), "2")
			api.nvim_win_set_cursor(H.state().main.win, { 6, 0 })
			H.keys("Vjc")
			H.send("range")
			local p = posts()[2]
			H.eq({ H.arg(p, "start_line"), H.arg(p, "line"), H.arg(p, "side") }, { "4", "5", "RIGHT" })
		end,
	},

	{
		"c on a hunk header is refused; empty comments are not sent",
		function()
			H.open_file()
			api.nvim_win_set_cursor(H.state().main.win, { 1, 0 })
			H.keys("c")
			H.truthy(H.note("Put the cursor on a line"))
			api.nvim_win_set_cursor(H.state().main.win, { 2, 0 })
			H.keys("c")
			H.send("")
			H.truthy(H.note("Nothing to send"))
			H.eq(#posts(), 0)
			H.keys("<Esc>q")
			H.eq(api.nvim_get_current_win(), H.state().main.win)
		end,
	},

	{
		"r replies to the thread on the line",
		function()
			H.open_file()
			api.nvim_win_set_cursor(H.state().main.win, { 5, 0 })
			H.keys("r")
			H.send("thanks")
			local p = posts()[1]
			H.eq(p[4], "repos/acme/widgets/pulls/7/comments/1/replies")
			H.eq(H.arg(p, "body"), "thanks")
			api.nvim_win_set_cursor(H.state().main.win, { 2, 0 })
			H.keys("r")
			H.truthy(H.note("No review thread"))
		end,
	},

	{
		"r inside a change reaches the thread at its end",
		function()
			H.open_file()
			api.nvim_win_set_cursor(H.state().main.win, { 4, 0 })
			H.keys("r")
			H.send("ok")
			H.eq(posts()[1][4], "repos/acme/widgets/pulls/7/comments/1/replies")
		end,
	},

	{
		"A approves (body optional), X requests changes, c comments on the PR",
		function()
			H.open({ repo = "acme/widgets", number = 7 })
			H.keys("A")
			H.send("")
			local r = H.call("pr", "review")
			H.eq(r, { "pr", "review", "7", "-R", "acme/widgets", "--approve" })
			api.nvim_set_current_win(H.state().panel.win)
			H.keys("X")
			H.send("please change")
			H.eq(H.call("pr", "review"), {
				"pr",
				"review",
				"7",
				"-R",
				"acme/widgets",
				"--request-changes",
				"--body",
				"please change",
			})
			api.nvim_set_current_win(H.state().panel.win)
			H.keys("c")
			H.send("general")
			H.eq(H.call("pr", "comment"), { "pr", "comment", "7", "-R", "acme/widgets", "--body", "general" })
		end,
	},

	{
		"o opens the browser",
		function()
			H.open()
			H.keys("o")
			H.eq(H.opened, "https://github.com/acme/widgets/pull/7")
		end,
	},

	{
		"q closes the tab",
		function()
			local tabs = #api.nvim_list_tabpages()
			H.open()
			H.keys("q")
			H.eq(H.P._state(), nil)
			H.eq(#api.nvim_list_tabpages(), math.max(tabs, 1))
		end,
	},
}
