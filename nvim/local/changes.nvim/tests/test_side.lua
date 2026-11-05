local H = require("helpers")
local F = require("fake_lsp")
local api = vim.api

local function wait_for(fn, msg)
	assert(vim.wait(5000, fn, 10), msg or "timed out")
end

return {
	{
		"gs opens the real file in a split inside the view and reuses it",
		function()
			local root = H.repo()
			H.dirty(root)
			local s = H.open(root)
			H.view("a%.lua")
			H.cursor(19)
			H.keys("gs")
			local win = api.nvim_get_current_win()
			H.truthy(win ~= s.view.win and win ~= s.panel.win, "focus is in a new window")
			H.eq(api.nvim_win_get_tabpage(win), s.tab, "inside the view's tab")
			H.eq(api.nvim_buf_get_name(0), root .. "/a.lua")
			H.eq(api.nvim_win_get_cursor(win)[1], 19)
			H.eq(vim.wo[win].winbar, "", "view options are not inherited")
			H.eq(vim.wo[win].statuscolumn, "")
			H.eq(vim.bo.buftype, "", "a real file buffer")
			api.nvim_set_current_win(s.view.win)
			H.keys("<Tab>")
			H.keys("gs")
			H.eq(api.nvim_get_current_win(), win, "same split reused")
			H.eq(vim.fn.expand("%:t"), "b.tf")
			H.eq(#api.nvim_tabpage_list_wins(s.tab), 3)
		end,
	},

	{
		"gd shows the definition in the split and stays in the diff",
		function()
			local root = H.repo()
			H.dirty(root)
			local s = H.open(root)
			H.view("a%.lua")
			H.cursor(19, 3)
			H.keys("gd")
			wait_for(function()
				return s.side_win and api.nvim_win_is_valid(s.side_win)
			end, "no side window")
			H.eq(api.nvim_get_current_win(), s.view.win, "cursor stays in the diff")
			H.eq(api.nvim_buf_get_name(api.nvim_win_get_buf(s.side_win)), root .. "/a.lua")
			H.eq(api.nvim_win_get_cursor(s.side_win), { 1, 0 })
			local req = F.last("textDocument/definition")
			H.eq(req.params.position, { line = 18, character = 3 })
		end,
	},

	{
		"K asks the server of the real file",
		function()
			local root = H.repo()
			H.dirty(root)
			H.open(root)
			H.view("a%.lua")
			H.cursor(2, 2)
			H.keys("K")
			wait_for(function()
				return F.last("textDocument/hover") ~= nil
			end)
			H.eq(F.last("textDocument/hover").params.position, { line = 1, character = 2 })
		end,
	},
}
