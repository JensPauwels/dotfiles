-- The side window: real files opened next to the view, in the view's tab,
-- so language servers attach and you can navigate without leaving it. Also
-- LSP hover and go-to-definition for a position in a real file, answered by
-- the servers attached to that file (the view's own buffers have none).
--
-- Kept free of plugin state so the same file can live in several plugins.
local api = vim.api

local M = {}

local function notify(msg, level)
	vim.notify(msg, level or vim.log.levels.INFO)
end

-- Window options a view sets that a normal editing window must not inherit.
local reset = {
	"number",
	"relativenumber",
	"signcolumn",
	"statuscolumn",
	"cursorline",
	"wrap",
	"linebreak",
	"list",
	"spell",
	"foldmethod",
	"foldexpr",
	"foldenable",
	"foldlevel",
	"foldcolumn",
	"foldtext",
	"fillchars",
	"winbar",
	"winfixwidth",
	"numberwidth",
}

--- The side window of `holder` ({ side_win?, tab }), created to the right of
--- `anchor` when missing.
--- @param holder { side_win?: integer, tab: integer }
--- @param anchor integer
--- @return integer win
function M.window(holder, anchor)
	local win = holder.side_win
	if win and api.nvim_win_is_valid(win) and api.nvim_win_get_tabpage(win) == holder.tab then
		return win
	end
	win = api.nvim_open_win(api.nvim_win_get_buf(anchor), false, { split = "right", win = anchor })
	for _, name in ipairs(reset) do
		vim.wo[win][name] = api.nvim_get_option_value(name, { scope = "global" })
	end
	holder.side_win = win
	return win
end

--- Open `path` at `line` in the side window.
--- @param opts? { focus?: boolean }
function M.open(holder, anchor, path, line, opts)
	opts = opts or {}
	local win = M.window(holder, anchor)
	local buf = vim.fn.bufadd(path)
	vim.bo[buf].buflisted = true
	api.nvim_win_set_buf(win, buf)
	pcall(api.nvim_win_set_cursor, win, { line, 0 })
	api.nvim_win_call(win, function()
		vim.cmd("normal! zvzz")
	end)
	if opts.focus ~= false then
		api.nvim_set_current_win(win)
	end
	return win
end

--- Load `path` (hidden) so servers attach, and return its buffer.
function M.load(path)
	local buf = vim.fn.bufadd(path)
	if not api.nvim_buf_is_loaded(buf) then
		vim.fn.bufload(buf)
	end
	-- bufload does not fire FileType for a hidden buffer that never had one
	if vim.bo[buf].filetype == "" then
		api.nvim_buf_call(buf, function()
			vim.cmd("filetype detect")
		end)
	end
	return buf
end

--- Call cb(clients) once servers supporting `method` are attached to `buf`;
--- they may need a moment to start for a freshly loaded file.
--- @param valid fun(): boolean  false when the result is no longer wanted
local function with_clients(buf, method, label, valid, cb)
	local attempts = 0
	local function try()
		if not valid() then
			return
		end
		local clients = vim.lsp.get_clients({ bufnr = buf, method = method })
		if #clients > 0 then
			cb(clients)
			return
		end
		attempts = attempts + 1
		if attempts == 2 then
			notify("Waiting for a language server to attach to " .. label .. "...")
		elseif attempts > 20 then
			notify("No language server for " .. label .. " supports " .. method, vim.log.levels.WARN)
			return
		end
		vim.defer_fn(try, 500)
	end
	try()
end

local function params(buf, row, col, client)
	return {
		textDocument = { uri = vim.uri_from_bufnr(buf) },
		position = { line = row, character = vim.lsp.util.character_offset(buf, row, col, client.offset_encoding) },
	}
end

--- Hover float for (row, col) (0-based) of `buf`.
--- @param opts { label: string, valid: fun(): boolean, focus_id: string }
function M.hover(buf, row, col, opts)
	with_clients(buf, "textDocument/hover", opts.label, opts.valid, function(clients)
		local pending, contents = #clients, {}
		for _, client in ipairs(clients) do
			client:request("textDocument/hover", params(buf, row, col, client), function(err, result)
				pending = pending - 1
				if not err and result and result.contents then
					local lines = vim.lsp.util.convert_input_to_markdown_lines(result.contents)
					if #lines > 0 then
						if #contents > 0 then
							contents[#contents + 1] = "---"
						end
						vim.list_extend(contents, lines)
					end
				end
				if pending > 0 or not opts.valid() then
					return
				end
				if #contents == 0 then
					notify("No hover information available")
					return
				end
				vim.lsp.util.open_floating_preview(contents, "markdown", {
					border = "rounded",
					focus_id = opts.focus_id,
					max_width = math.min(100, vim.o.columns - 4),
				})
			end, buf)
		end
	end)
end

--- Show the definition of the symbol at (row, col) of `buf` in the side
--- window. The cursor stays where it is unless opts.focus.
--- @param opts { label: string, valid: fun(): boolean, holder: table, anchor: integer, focus?: boolean }
function M.definition(buf, row, col, opts)
	with_clients(buf, "textDocument/definition", opts.label, opts.valid, function(clients)
		local client = clients[1]
		client:request("textDocument/definition", params(buf, row, col, client), function(err, result)
			if not opts.valid() then
				return
			end
			if err then
				notify("Definition failed: " .. (err.message or tostring(err)), vim.log.levels.ERROR)
				return
			end
			if result and result.uri or result and result.targetUri then
				result = { result }
			end
			local loc = result and result[1]
			if not loc then
				notify("No definition found")
				return
			end
			local back = api.nvim_get_current_win()
			local win = M.window(opts.holder, opts.anchor)
			api.nvim_set_current_win(win)
			vim.lsp.util.show_document(loc, client.offset_encoding, { focus = true })
			vim.cmd("normal! zvzz")
			if not opts.focus and api.nvim_win_is_valid(back) then
				api.nvim_set_current_win(back)
			end
			if #result > 1 then
				notify(string.format("%d definitions, showing the first", #result))
			end
		end, buf)
	end)
end

return M
