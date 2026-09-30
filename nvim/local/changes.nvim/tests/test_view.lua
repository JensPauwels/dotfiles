local H = require("helpers")
local api = vim.api

return {
	{
		"panel lists staged and unstaged files",
		function()
			local root = H.repo()
			H.dirty(root)
			H.open(root)
			H.eq(H.panel_lines(), {
				" Staged (1)",
				"   M  s.txt",
				"",
				" Changes (4)",
				"   M  a.lua",
				"   M  b.tf",
				"   D  gone.txt",
				"   ?  new.txt",
			})
			H.match(vim.wo[H.state().panel.win].winbar, "main")
		end,
	},

	{
		"clean tree shows a message",
		function()
			local root = H.repo()
			H.open(root)
			H.eq(H.panel_lines(), { "", "   Working tree clean" })
			H.eq(H.view_lines(), { "", "  Nothing to show." })
		end,
	},

	{
		"renders added, removed and word-level changes with folds",
		function()
			local root = H.repo()
			H.dirty(root)
			H.open(root)
			H.view("a%.lua")
			local m = H.marks()
			H.eq(H.view_lines()[2], "line2 changed")
			H.truthy(m[2].add, "changed line is green")
			H.eq(m[2].del, { "line2" }, "old line drawn above")
			H.eq(m[2].del_above, true)
			H.eq(m[2].word, { 6, 13 }, "' changed' is the word diff")
			H.eq(m[9].del, { "line10" }, "pure deletion drawn below line 9")
			H.eq(m[9].del_above, false)
			H.truthy(m[19].add and m[20].add, "inserted lines are green")
			H.eq(H.folds(), { { 13, 15 } }, "unchanged lines beyond context are folded")
			H.match(vim.wo[H.state().view.win].winbar, "a%.lua  %(Working Tree%)  ·  3 changes")
		end,
	},

	{
		"tabs in removed lines are expanded and word diff survives",
		function()
			local root = H.repo()
			H.dirty(root)
			H.open(root)
			H.view("b%.tf")
			local m = H.marks()
			H.eq(m[1].del, { "hostnames = [var.oauth2_redirect_domain]" })
			H.eq(m[1].del_word, { "var.oauth2_redirect_domain" })
			H.eq(m[1].word, { 14, 42 })
		end,
	},

	{
		"deleted and untracked files render",
		function()
			local root = H.repo()
			H.dirty(root)
			H.open(root)
			H.view("gone%.txt")
			H.eq(H.marks()[1].del, { "gone" })
			H.view("new%.txt")
			H.eq(H.view_lines(), { "brand new" })
			H.truthy(H.marks()[1].add)
		end,
	},

	{
		"]c and [c cycle through changes",
		function()
			local root = H.repo()
			H.dirty(root)
			H.open(root)
			H.view("a%.lua")
			local function line()
				return api.nvim_win_get_cursor(0)[1]
			end
			H.eq(line(), 2)
			H.keys("]c")
			H.eq(line(), 9)
			H.keys("]c")
			H.eq(line(), 19)
			H.keys("]c")
			H.eq(line(), 2, "wraps around")
			H.keys("[c")
			H.eq(line(), 19)
		end,
	},

	{
		"Tab moves to the next file and - returns to the panel",
		function()
			local root = H.repo()
			H.dirty(root)
			H.open(root)
			H.view("a%.lua")
			H.keys("<Tab>")
			H.eq(H.state().current.path, "b.tf")
			H.eq(api.nvim_get_current_win(), H.state().view.win)
			H.keys("<S-Tab>")
			H.eq(H.state().current.path, "a.lua")
			H.keys("-")
			H.eq(api.nvim_get_current_win(), H.state().panel.win)
		end,
	},

	{
		"unsaved buffer edits are reflected",
		function()
			local root = H.repo()
			H.dirty(root)
			vim.cmd("edit " .. root .. "/a.lua")
			api.nvim_buf_set_lines(0, 0, 1, false, { "line1 edited in buffer" })
			H.open(root)
			H.view("a%.lua")
			H.eq(H.view_lines()[1], "line1 edited in buffer")
			H.truthy(H.marks()[1].add, "buffer edit is part of the first change")
			H.match(vim.wo[0].winbar, "3 changes")
		end,
	},

	{
		"gf opens the real file at the cursor line",
		function()
			local root = H.repo()
			H.dirty(root)
			H.open(root)
			H.view("a%.lua")
			H.cursor(19)
			H.keys("gf")
			H.eq(vim.fn.expand("%:t"), "a.lua")
			H.eq(api.nvim_win_get_cursor(0)[1], 19)
			H.truthy(H.C._state(), "view stays open in its own tab")
		end,
	},

	{
		"closing leaves a single tab",
		function()
			local root = H.repo()
			H.open(root)
			H.keys("q")
			H.eq(H.C._state(), nil)
			H.eq(#api.nvim_list_tabpages(), 1)
		end,
	},
}
