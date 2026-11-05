-- A markdown buffer split below a window; `:w` or <C-s> sends it, q cancels.
local api = vim.api

local M = {}

M.height = 12

--- @param title string
--- @param opts { anchor?: integer, allow_empty?: boolean }
--- @param on_send fun(text: string)
--- @return integer buf
function M.open(title, opts, on_send)
	local anchor = opts.anchor or api.nvim_get_current_win()
	local buf = api.nvim_create_buf(false, true)
	vim.bo[buf].buftype = "acwrite"
	vim.bo[buf].bufhidden = "wipe"
	vim.bo[buf].swapfile = false
	pcall(api.nvim_buf_set_name, buf, "pulls://compose/" .. buf)
	vim.bo[buf].filetype = "markdown"
	local win = api.nvim_open_win(buf, true, { split = "below", win = anchor, height = M.height })
	vim.wo[win].wrap = true
	vim.wo[win].linebreak = true
	vim.wo[win].number = false
	vim.wo[win].relativenumber = false
	vim.wo[win].statuscolumn = ""
	vim.wo[win].winbar = ("  " .. title .. "   ·   :w or <C-s> to send, q to cancel"):gsub("%%", "%%%%")

	local sent = false
	local function close()
		if api.nvim_win_is_valid(win) then
			api.nvim_win_close(win, true)
		end
		if api.nvim_win_is_valid(anchor) then
			api.nvim_set_current_win(anchor)
		end
	end
	local function send()
		if sent then
			return
		end
		local text = vim.trim(table.concat(api.nvim_buf_get_lines(buf, 0, -1, false), "\n"))
		if text == "" and not opts.allow_empty then
			vim.notify("Nothing to send", vim.log.levels.WARN, { title = "pulls" })
			return
		end
		sent = true
		vim.bo[buf].modified = false
		vim.cmd("stopinsert")
		close()
		on_send(text)
	end
	api.nvim_create_autocmd("BufWriteCmd", { buffer = buf, callback = send })
	vim.keymap.set({ "n", "i" }, "<C-s>", send, { buffer = buf, desc = "Send" })
	vim.keymap.set("n", "q", close, { buffer = buf, desc = "Cancel" })
	vim.cmd("startinsert")
	return buf
end

return M
