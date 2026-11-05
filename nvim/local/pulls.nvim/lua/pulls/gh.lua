-- Thin async wrappers around the GitHub CLI. Every call takes a callback
-- that runs on the main loop as cb(err, result); err is nil on success.
local M = {}

--- Executable to run; tests point this at a fake.
M.bin = "gh"

local function decode(out)
	local ok, val = pcall(vim.json.decode, out, { luanil = { object = true, array = true } })
	if not ok then
		return nil
	end
	return val
end

--- @param args string[]
--- @param opts? { cwd?: string, json?: boolean }
--- @param cb fun(err: string|nil, out: any)
function M.run(args, opts, cb)
	opts = opts or {}
	local cmd = { M.bin }
	vim.list_extend(cmd, args)
	local ok, err = pcall(vim.system, cmd, {
		cwd = opts.cwd,
		text = true,
		env = { GH_PROMPT_DISABLED = "1", NO_COLOR = "1", GH_PAGER = "" },
	}, function(res)
		vim.schedule(function()
			if res.code ~= 0 then
				local msg = vim.trim(res.stderr or "")
				cb(msg ~= "" and msg or ("gh exited with " .. res.code), nil)
				return
			end
			if opts.json then
				local val = decode(res.stdout or "")
				if val == nil then
					cb("could not parse gh output", nil)
				else
					cb(nil, val)
				end
			else
				cb(nil, res.stdout or "")
			end
		end)
	end)
	if not ok then
		vim.schedule(function()
			cb("could not run " .. M.bin .. ": " .. tostring(err), nil)
		end)
	end
end

--- owner/name of the repository the directory belongs to.
--- @param cwd string
--- @param cb fun(err: string|nil, repo: string|nil)
function M.current_repo(cwd, cb)
	M.run({ "repo", "view", "--json", "nameWithOwner" }, { cwd = cwd, json = true }, function(err, val)
		cb(err, val and val.nameWithOwner)
	end)
end

M.list_fields = table.concat({
	"number",
	"title",
	"author",
	"headRefName",
	"baseRefName",
	"isDraft",
	"state",
	"reviewDecision",
	"updatedAt",
	"createdAt",
	"additions",
	"deletions",
	"labels",
	"statusCheckRollup",
	"body",
	"url",
}, ",")

--- @param repo string
--- @param opts { state: string, search?: string, limit: integer, fields?: string }
--- @param cb fun(err: string|nil, prs: table[]|nil)
function M.list(repo, opts, cb)
	local fields = opts.fields or M.list_fields
	local args = { "pr", "list", "-R", repo, "--state", opts.state, "-L", tostring(opts.limit), "--json", fields }
	if opts.search and opts.search ~= "" then
		vim.list_extend(args, { "--search", opts.search })
	end
	M.run(args, { json = true }, cb)
end

M.view_fields = table.concat({
	"number",
	"title",
	"body",
	"author",
	"state",
	"isDraft",
	"url",
	"headRefName",
	"headRefOid",
	"baseRefName",
	"createdAt",
	"updatedAt",
	"additions",
	"deletions",
	"changedFiles",
	"reviewDecision",
	"mergeable",
	"labels",
	"assignees",
	"reviewRequests",
	"reviews",
	"comments",
	"commits",
	"statusCheckRollup",
}, ",")

function M.view(repo, number, cb)
	M.run({ "pr", "view", tostring(number), "-R", repo, "--json", M.view_fields }, { json = true }, cb)
end

--- Unified diff of the pull request.
function M.diff(repo, number, cb)
	M.run({ "pr", "diff", tostring(number), "-R", repo, "--color", "never" }, {}, cb)
end

--- Review comments on lines (REST objects), all pages.
function M.review_comments(repo, number, cb)
	M.run(
		{ "api", "--paginate", "--slurp", string.format("repos/%s/pulls/%d/comments?per_page=100", repo, number) },
		{ json = true },
		function(err, pages)
			if err then
				cb(err, nil)
				return
			end
			local all = {}
			for _, page in ipairs(pages or {}) do
				vim.list_extend(all, page)
			end
			cb(nil, all)
		end
	)
end

--- @param c { body: string, commit_id: string, path: string, line: integer, side: string, start_line?: integer, start_side?: string }
function M.add_review_comment(repo, number, c, cb)
	local args = {
		"api",
		"-X",
		"POST",
		string.format("repos/%s/pulls/%d/comments", repo, number),
		"-f",
		"body=" .. c.body,
		"-f",
		"commit_id=" .. c.commit_id,
		"-f",
		"path=" .. c.path,
		"-F",
		"line=" .. c.line,
		"-f",
		"side=" .. c.side,
	}
	if c.start_line and c.start_line ~= c.line then
		vim.list_extend(args, { "-F", "start_line=" .. c.start_line, "-f", "start_side=" .. c.start_side })
	end
	M.run(args, { json = true }, cb)
end

function M.reply(repo, number, comment_id, body, cb)
	M.run({
		"api",
		"-X",
		"POST",
		string.format("repos/%s/pulls/%d/comments/%d/replies", repo, number, comment_id),
		"-f",
		"body=" .. body,
	}, { json = true }, cb)
end

function M.comment(repo, number, body, cb)
	M.run({ "pr", "comment", tostring(number), "-R", repo, "--body", body }, {}, cb)
end

--- @param event "approve"|"request-changes"|"comment"
function M.review(repo, number, event, body, cb)
	local args = { "pr", "review", tostring(number), "-R", repo, "--" .. event }
	if body ~= "" then
		vim.list_extend(args, { "--body", body })
	end
	M.run(args, {}, cb)
end

local viewed_query = [[
query($owner: String!, $name: String!, $number: Int!, $endCursor: String) {
  repository(owner: $owner, name: $name) {
    pullRequest(number: $number) {
      id
      files(first: 100, after: $endCursor) {
        pageInfo { hasNextPage endCursor }
        nodes { path viewerViewedState }
      }
    }
  }
}]]

--- Node id of the pull request and which files you marked as viewed.
--- @param cb fun(err: string|nil, res: { id: string, viewed: table<string, boolean> }|nil)
function M.viewed_files(repo, number, cb)
	local owner, name = repo:match("^([^/]+)/(.+)$")
	M.run({
		"api",
		"graphql",
		"--paginate",
		"--slurp",
		"-f",
		"query=" .. viewed_query,
		"-f",
		"owner=" .. (owner or ""),
		"-f",
		"name=" .. (name or ""),
		"-F",
		"number=" .. number,
	}, { json = true }, function(err, pages)
		if err then
			cb(err, nil)
			return
		end
		local res = { viewed = {} }
		for _, page in ipairs(pages or {}) do
			local pr = vim.tbl_get(page, "data", "repository", "pullRequest")
			if pr then
				res.id = pr.id
				for _, f in ipairs(vim.tbl_get(pr, "files", "nodes") or {}) do
					res.viewed[f.path] = f.viewerViewedState == "VIEWED"
				end
			end
		end
		if not res.id then
			cb("pull request not found", nil)
			return
		end
		cb(nil, res)
	end)
end

--- Tick or untick GitHub's "Viewed" box of a file.
function M.set_viewed(pr_id, path, viewed, cb)
	local mutation = viewed and "markFileAsViewed" or "unmarkFileAsViewed"
	M.run({
		"api",
		"graphql",
		"-f",
		string.format(
			"query=mutation($id: ID!, $path: String!) { %s(input: {pullRequestId: $id, path: $path}) { clientMutationId } }",
			mutation
		),
		"-f",
		"id=" .. pr_id,
		"-f",
		"path=" .. path,
	}, { json = true }, cb)
end

--- Open pull requests across GitHub matching qualifiers, e.g.
--- { "--review-requested=@me" } or { "--author=@me", "--repo=owner/name" }.
--- @param qualifiers string|string[]
function M.search(qualifiers, cb)
	local args = { "search", "prs" }
	vim.list_extend(args, type(qualifiers) == "table" and qualifiers or { qualifiers })
	vim.list_extend(args, {
		"--state=open",
		"--sort=updated",
		"-L",
		"30",
		"--json",
		"number,title,repository,author,updatedAt,isDraft,state,url,body",
	})
	M.run(args, { json = true }, cb)
end

function M.checkout(repo, number, cwd, cb)
	M.run({ "pr", "checkout", tostring(number), "-R", repo }, { cwd = cwd }, cb)
end

return M
