local H = require("helpers")
local api = vim.api

local function mutations()
	local out = {}
	for _, c in ipairs(H.calls()) do
		if c[1] == "api" and c[2] == "graphql" and c[4] and c[4]:find("mutation") then
			out[#out + 1] = c
		end
	end
	return out
end

return {
	{
		"viewed state is loaded across pages; DISMISSED counts as not viewed",
		function()
			H.open({ repo = "acme/widgets", number = 7 })
			local s = H.state()
			H.eq(s.pr.id, "PR_node7")
			H.eq(s.pr.viewed, { ["src/app.lua"] = false, ["docs/new.md"] = true, ["old.txt"] = false })
			local q = H.call("api", "graphql")
			H.eq({ H.arg(q, "owner"), H.arg(q, "name"), H.arg(q, "number") }, { "acme", "widgets", "7" })
		end,
	},

	{
		"v in the panel marks the file viewed, again unmarks it",
		function()
			H.open({ repo = "acme/widgets", number = 7 })
			H.select("src/app%.lua")
			H.keys("v")
			H.match(H.panel_lines()[4], "^ ✓ M  src/app%.lua")
			H.match(H.panel_lines()[3], "2/5 viewed")
			local m = mutations()[1]
			H.match(H.arg(m, "query"), "{ markFileAsViewed%(")
			H.eq({ H.arg(m, "id"), H.arg(m, "path") }, { "PR_node7", "src/app.lua" })
			H.eq(api.nvim_win_get_cursor(H.state().panel.win)[1], 4, "cursor stays")
			H.keys("v")
			H.match(H.panel_lines()[4], "^   M  src/app%.lua")
			H.match(H.arg(mutations()[2], "query"), "unmarkFileAsViewed")
		end,
	},

	{
		"v in the diff marks the shown file and keeps the cursor",
		function()
			H.open_file()
			local win = H.state().main.win
			api.nvim_win_set_cursor(win, { 6, 0 })
			H.keys("v")
			H.match(vim.wo[win].winbar, "✓ viewed")
			H.eq(api.nvim_win_get_cursor(win)[1], 6)
			H.eq(H.arg(mutations()[1], "path"), "src/app.lua")
		end,
	},

	{
		"a failed mutation is undone",
		function()
			H.open_file()
			require("pulls.gh").bin = "false"
			local ok, err = pcall(H.keys, "v")
			require("pulls.gh").bin = H.dir .. "/bin/gh"
			assert(ok, err)
			H.eq(H.state().pr.viewed["src/app.lua"], false)
			H.truthy(H.note("Could not mark as viewed"))
		end,
	},
}
