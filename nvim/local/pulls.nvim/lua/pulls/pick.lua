-- Quick picker over pull requests. In a clone it shows that repository:
-- waiting for your review, recently opened, yours, then every other open
-- one. <C-a> switches to all repositories (review requests, recent and
-- yours everywhere), which is also what you get outside a clone.
-- Shows what is cached right away and refreshes from GitHub while open.
-- Uses snacks.nvim's picker when available, vim.ui.select otherwise.
local gh = require("pulls.gh")
local recent = require("pulls.recent")
local P = require("pulls.patch")

local M = {}

local sections = {
	{ key = "review", label = "review", hl = "PullsPending" },
	{ key = "recent", label = "recent", hl = "PullsTitle" },
	{ key = "mine", label = "mine", hl = "PullsOpen" },
	{ key = "open", label = "open", hl = "PullsDim" },
}

local state_hl = { OPEN = "PullsOpen", DRAFT = "PullsDraft", MERGED = "PullsMerged", CLOSED = "PullsClosed" }

--- Cache key of a section for a scope (nil: all repositories).
local function cache_key(key, repo)
	return repo and (key .. "@" .. repo:lower()) or key
end

--- One list, sections in order, each pull request once (first section wins).
--- @param data table section key -> items
--- @return table[]
function M.items(data)
	local out, seen = {}, {}
	for _, sec in ipairs(sections) do
		for _, it in ipairs(data[sec.key] or {}) do
			local key = it.repo:lower() .. "#" .. it.number
			if not seen[key] then
				seen[key] = true
				local body = (it.body or ""):gsub("\r\n", "\n")
				out[#out + 1] = {
					text = table.concat({ sec.label, it.repo, "#" .. it.number, it.title, it.author }, " "),
					section = sec,
					pr = it,
					preview = {
						text = table.concat({
							"# " .. it.title,
							"",
							string.format("%s  %s #%d by %s", it.state, it.repo, it.number, it.author),
							"",
							body ~= "" and body or "_No description._",
						}, "\n"),
						ft = "markdown",
						loc = false,
					},
				}
			end
		end
	end
	return out
end

--- Section data for a scope, from the cache.
--- @param repo string|nil
function M.data(repo)
	local all = recent.load()
	local data = {}
	for _, sec in ipairs(sections) do
		data[sec.key] = all[cache_key(sec.key, repo)] or {}
	end
	data.recent = all.recent or {}
	if repo then
		data.recent = vim.tbl_filter(function(r)
			return r.repo:lower() == repo:lower()
		end, data.recent)
	end
	return data
end

local function label(item, repo)
	local it = item.pr
	local where = repo and "" or (it.repo .. " ")
	return string.format("%-6s  %s#%d  %s  (%s)", item.section.label, where, it.number, it.title, it.author)
end

local function make_format(repo)
	return function(item)
		local it = item.pr
		local meta = (repo and "" or (it.repo .. " · ")) .. it.author
		if it.updated_at ~= "" then
			meta = meta .. " · " .. P.ago(it.updated_at)
		end
		return {
			{ string.format("%-7s", item.section.label), item.section.hl },
			{ string.format("#%-6d", it.number), state_hl[it.state] or "PullsOpen" },
			{ it.title .. "  " },
			{ meta, "PullsDim" },
		}
	end
end

--- Searches to run for a scope: section key -> function(cb).
local function fetchers(repo)
	local f = {}
	local scope = repo and { "--repo=" .. repo } or {}
	f.review = function(cb)
		gh.search(vim.list_extend({ "--review-requested=@me" }, scope), cb)
	end
	f.mine = function(cb)
		gh.search(vim.list_extend({ "--author=@me" }, scope), cb)
	end
	if repo then
		f.open = function(cb)
			gh.list(repo, {
				state = "open",
				limit = 50,
				-- only what the picker shows: checks make this slow
				fields = "number,title,author,isDraft,state,url,body,updatedAt",
			}, function(err, prs)
				if err then
					cb(err)
					return
				end
				cb(nil, recent.from_list(repo, prs))
			end)
		end
	end
	return f
end

--- @param on_open fun(repo: string, number: integer, how: "review"|"tab")
--- @param opts? { repo?: string } the repository to show; nil for all
function M.open(on_open, opts)
	opts = opts or {}
	local repo = opts.repo
	local data = M.data(repo)
	local picker
	local has_snacks, Snacks = pcall(require, "snacks")
	has_snacks = has_snacks and Snacks.picker ~= nil

	local f = fetchers(repo)
	local pending = vim.tbl_count(f)
	for key, fetch in pairs(f) do
		fetch(function(err, results)
			pending = pending - 1
			if err then
				vim.notify("gh failed: " .. err, vim.log.levels.WARN, { title = "pulls" })
			else
				data[key] = key == "open" and results or recent.from_search(results)
				if repo then
					data[key] = vim.tbl_filter(function(r)
						return r.repo:lower() == repo:lower()
					end, data[key])
				end
				recent.set(cache_key(key, repo), data[key])
			end
			if picker and not picker.closed then
				picker.opts.items = M.items(data)
				picker.list:set_target()
				picker:find()
			elseif not has_snacks and pending == 0 then
				M.select(data, on_open, repo)
			end
		end)
	end

	if not has_snacks then
		return
	end
	local function choose(how)
		return function(p, item)
			p:close()
			if item then
				on_open(item.pr.repo, item.pr.number, how)
			end
		end
	end
	picker = Snacks.picker.pick({
		source = "pulls_pick",
		title = repo and ("Pull requests · " .. repo .. "  (<C-a> all repos)") or "Pull requests · all repos",
		items = M.items(data),
		format = make_format(repo),
		preview = "preview",
		show_empty = true, -- the searches may still be running
		confirm = choose("review"),
		actions = {
			tab = choose("tab"),
			browse = function(_, item)
				if item and item.pr.url ~= "" then
					vim.ui.open(item.pr.url)
				end
			end,
			scope = function(p)
				p:close()
				vim.schedule(function()
					M.open(on_open, { repo = not repo and opts.home or nil, home = opts.home or repo })
				end)
			end,
		},
		win = {
			input = {
				keys = {
					["<C-o>"] = { "browse", mode = { "n", "i" }, desc = "Open in browser" },
					["<C-t>"] = { "tab", mode = { "n", "i" }, desc = "Read in the pulls tab, no checkout" },
					["<C-a>"] = { "scope", mode = { "n", "i" }, desc = "This repository / all repositories" },
				},
			},
		},
	})
end

--- Fallback without snacks.nvim.
function M.select(data, on_open, repo)
	vim.ui.select(M.items(data), {
		prompt = repo and ("Pull requests · " .. repo) or "Pull requests",
		format_item = function(item)
			return label(item, repo)
		end,
	}, function(item)
		if item then
			on_open(item.pr.repo, item.pr.number, "review")
		end
	end)
end

return M
