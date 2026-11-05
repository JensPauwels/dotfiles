local H = require("helpers")
local recent = require("pulls.recent")
local pick = require("pulls.pick")

local function labels(items)
	local out = {}
	for _, it in ipairs(items) do
		out[#out + 1] = it.section.key .. " " .. it.pr.repo .. "#" .. it.pr.number
	end
	return out
end

return {
	{
		"opening a pull request remembers it, newest first, once",
		function()
			H.open({ repo = "acme/widgets", number = 7 })
			local r = recent.load().recent
			H.eq(#r, 1)
			H.eq({ r[1].repo, r[1].number, r[1].title, r[1].author, r[1].state }, { "acme/widgets", 7, "Add widgets", "alice", "OPEN" })
			recent.add("acme/gears", { number = 3, title = "Gears", state = "OPEN" })
			recent.add("ACME/widgets", { number = 7, title = "Add widgets", state = "MERGED" })
			r = recent.load().recent
			H.eq({ r[1].number, r[1].state, r[2].number, #r }, { 7, "MERGED", 3, 2 })
		end,
	},

	{
		"items: review first, then recent, then mine; each pull request once",
		function()
			local items = pick.items({
				review = { { repo = "a/b", number = 1, title = "x", author = "u", state = "OPEN" } },
				recent = {
					{ repo = "a/b", number = 1, title = "x", author = "u", state = "OPEN" },
					{ repo = "a/c", number = 2, title = "y", author = "u", state = "MERGED" },
				},
				mine = { { repo = "a/c", number = 2, title = "y", author = "u", state = "OPEN" }, { repo = "a/d", number = 4, title = "z", author = "me", state = "DRAFT" } },
			})
			H.eq(labels(items), { "review a/b#1", "recent a/c#2", "mine a/d#4" })
			H.match(items[1].text, "a/b #1 x u")
			H.match(items[1].preview.text, "^# x\n")
		end,
	},

	{
		"pick searches GitHub and opens the chosen pull request (vim.ui.select fallback)",
		function()
			local shown
			vim.ui.select = function(items, opts, cb)
				shown = vim.tbl_map(opts.format_item, items)
				for _, it in ipairs(items) do
					if it.pr.number == 7 then
						cb(it)
					end
				end
			end
			H.P.pick({ all = true })
			assert(vim.wait(5000, function()
				return H.P._state() ~= nil
			end, 10), "nothing opened")
			H.wait()
			H.eq(H.state().repo, "acme/widgets")
			H.eq(H.state().pr.number, 7)
			H.match(shown[1], "^review  acme/widgets #7  Add widgets  %(alice%)$")
			H.match(shown[2], "^review  acme/gears #3")
			H.eq(#shown, 2, "mine has the same two, shown once")
			local r = H.call("search", "prs")
			H.truthy(vim.tbl_contains(r, "--author=@me") or vim.tbl_contains(r, "--review-requested=@me"))
			H.eq(recent.load().review[2].state, "DRAFT", "search results are cached")
		end,
	},

	{
		"in a clone it shows that repository: review, recent, mine, then all open",
		function()
			recent.add("acme/widgets", { number = 9, title = "Old one", state = "MERGED" })
			recent.add("acme/gears", { number = 3, title = "Elsewhere", state = "OPEN" })
			local shown, done
			vim.ui.select = function(items, opts, cb)
				shown = vim.tbl_map(opts.format_item, items)
				done = true
				cb(nil)
			end
			pick.open(function() end, { repo = "acme/widgets" })
			assert(vim.wait(5000, function()
				return done
			end, 10), "nothing shown")
			-- gh searches are limited to the repository; open PRs come from pr list
			for _, c in ipairs(H.calls()) do
				if c[1] == "search" then
					H.truthy(vim.tbl_contains(c, "--repo=acme/widgets"), "search is scoped")
				end
			end
			local list = H.call("pr", "list")
			H.eq(H.arg(list, "-R"), "acme/widgets")
			local text = table.concat(shown, "\n")
			H.truthy(not text:find("Elsewhere"), "the other repository's recent PR is not listed")
			H.truthy(not text:find("Other repo"), "nor its review requests")
			H.match(shown[1], "^review  #7")
			H.truthy(text:find("recent  #9"), "recent of this repository")
			H.truthy(text:find("open    #8"), "other open pull requests")
			H.truthy(not text:find("acme/widgets #"), "no repository name on every line")
			H.truthy(recent.load()["open@acme/widgets"], "cached per repository")
		end,
	},

	{
		"repo_of reads owner/name from the remotes, origin first",
		function()
			local root = vim.fn.tempname()
			vim.fn.mkdir(root, "p")
			vim.system({ "git", "init", "-q", root }):wait()
			vim.system({ "git", "-C", root, "remote", "add", "upstream", "https://github.com/up/stream.git" }):wait()
			vim.system({ "git", "-C", root, "remote", "add", "origin", "git@github.com:acme/widgets.git" }):wait()
			H.eq(require("pulls.review").repo_of(root), "acme/widgets")
		end,
	},
}
