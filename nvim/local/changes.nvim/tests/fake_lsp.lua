-- An in-process language server for the tests: answers hover with
-- "hover text" and definition with line 1, column 0 of the same file.
-- Attaches to every lua buffer.
local F = { requests = {} }

local function server(dispatchers)
	local closing = false
	local srv = {}
	function srv.request(method, params, callback)
		F.requests[#F.requests + 1] = { method = method, params = params }
		vim.schedule(function()
			if method == "initialize" then
				callback(nil, { capabilities = { definitionProvider = true, hoverProvider = true } })
			elseif method == "textDocument/definition" then
				callback(nil, {
					uri = params.textDocument.uri,
					range = { start = { line = 0, character = 0 }, ["end"] = { line = 0, character = 1 } },
				})
			elseif method == "textDocument/hover" then
				callback(nil, { contents = { kind = "markdown", value = "hover text" } })
			else
				callback(nil, nil)
			end
		end)
		return true, #F.requests
	end
	function srv.notify(method)
		if method == "exit" then
			dispatchers.on_exit(0, 15)
		end
		return true
	end
	function srv.is_closing()
		return closing
	end
	function srv.terminate()
		closing = true
	end
	return srv
end

vim.cmd("filetype on")
vim.api.nvim_create_autocmd("FileType", {
	pattern = "lua",
	callback = function(ev)
		vim.lsp.start({ name = "fake", cmd = server, root_dir = vim.fs.dirname(vim.api.nvim_buf_get_name(ev.buf)) }, {
			bufnr = ev.buf,
		})
	end,
})

--- Last request of `method` sent to the fake server.
function F.last(method)
	for i = #F.requests, 1, -1 do
		if F.requests[i].method == method then
			return F.requests[i]
		end
	end
	return nil
end

return F
