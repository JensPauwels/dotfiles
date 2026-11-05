-- Pull requests you opened recently, and the last results of the "waiting
-- for my review" / "mine" searches, kept on disk so the picker can show
-- something before GitHub answers.
local M = {}

M.file = vim.fn.stdpath("data") .. "/pulls/recent.json"
M.max = 30

local function read()
	local f = io.open(M.file, "rb")
	if not f then
		return {}
	end
	local ok, data = pcall(vim.json.decode, f:read("*a"), { luanil = { object = true, array = true } })
	f:close()
	return ok and type(data) == "table" and data or {}
end

local function write(data)
	vim.fn.mkdir(vim.fs.dirname(M.file), "p")
	local tmp = M.file .. ".tmp"
	local f = io.open(tmp, "wb")
	if not f then
		return
	end
	f:write(vim.json.encode(data))
	f:close()
	vim.uv.fs_rename(tmp, M.file)
end

--- @class pulls.RecentItem
--- @field repo string
--- @field number integer
--- @field title string
--- @field author string
--- @field state string     OPEN, MERGED, CLOSED or DRAFT
--- @field url string
--- @field body string
--- @field updated_at string
--- @field opened_at? integer  unix time you last opened it

--- @return { recent: pulls.RecentItem[], review: pulls.RecentItem[], mine: pulls.RecentItem[] }
function M.load()
	local d = read()
	d.recent, d.review, d.mine = d.recent or {}, d.review or {}, d.mine or {}
	return d
end

--- Remember that `pr` (a gh pr view object) of `repo` was opened.
function M.add(repo, pr)
	local d = M.load()
	local item = {
		repo = repo,
		number = pr.number,
		title = pr.title or "",
		author = pr.author and pr.author.login or "",
		state = (pr.isDraft and pr.state == "OPEN") and "DRAFT" or (pr.state or "OPEN"),
		url = pr.url or "",
		body = pr.body or "",
		updated_at = pr.updatedAt or "",
		opened_at = os.time(),
	}
	local list = { item }
	for _, r in ipairs(d.recent) do
		if not (r.repo:lower() == repo:lower() and r.number == pr.number) and #list < M.max then
			list[#list + 1] = r
		end
	end
	d.recent = list
	write(d)
end

--- Store the latest results under `key` ("review", "mine", "open@owner/name", …).
function M.set(key, items)
	local d = M.load()
	d[key] = items
	write(d)
end

--- Turn `gh search prs` results into items.
function M.from_search(results)
	local out = {}
	for _, r in ipairs(results or {}) do
		local st = r.state and r.state:upper() or "OPEN"
		out[#out + 1] = {
			repo = r.repository and r.repository.nameWithOwner or "",
			number = r.number,
			title = r.title or "",
			author = r.author and r.author.login or "",
			state = r.isDraft and st == "OPEN" and "DRAFT" or st,
			url = r.url or "",
			body = r.body or "",
			updated_at = r.updatedAt or "",
		}
	end
	return out
end

--- Turn `gh pr list` results of `repo` into items.
function M.from_list(repo, prs)
	local out = {}
	for _, r in ipairs(prs or {}) do
		local st = r.state and r.state:upper() or "OPEN"
		out[#out + 1] = {
			repo = repo,
			number = r.number,
			title = r.title or "",
			author = r.author and r.author.login or "",
			state = r.isDraft and st == "OPEN" and "DRAFT" or st,
			url = r.url or "",
			body = r.body or "",
			updated_at = r.updatedAt or "",
		}
	end
	return out
end

return M
