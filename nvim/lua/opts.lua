-- Set tab width to 2 spaces
vim.opt.tabstop = 2
vim.opt.shiftwidth = 2

vim.opt.expandtab = true
vim.opt.laststatus = 0

-- Enable relative line numbers
vim.opt.number = true
vim.opt.relativenumber = true

-- Set the leader to space
vim.g.mapleader = " "

-- Enable word wrapping
vim.opt.wrap = true

-- Enable auto indentation
vim.opt.autoindent = true

-- Ignore the casing
vim.o.ignorecase = true
vim.o.smartcase = true

-- Make the buffer on the right active when splitting
vim.o.splitright = true

-- Make the buffer on the bottom active when splitting
vim.o.splitbelow = true

vim.o.completeopt = "menuone,noinsert,noselect"

vim.o.smartindent = true

vim.g.loaded_netrw = 1
vim.g.loaded_netrwPlugin = 1

vim.g.go_doc_keywordprg_enabled = 0

vim.opt.autoread = true
-- Faster CursorHold trigger (default 4000ms is too slow for external change detection)
vim.opt.updatetime = 250

vim.api.nvim_create_autocmd({ "BufEnter", "CursorHold", "CursorHoldI", "FocusGained" }, {
	pattern = "*",
	command = "if mode() !~ 'r' && getcmdwintype() == '' | checktime | endif",
})

-- Notify when a file is reloaded from disk (e.g. changed in VSCode)
vim.api.nvim_create_autocmd("FileChangedShellPost", {
	pattern = "*",
	callback = function()
		vim.notify("File changed on disk. Buffer reloaded.", vim.log.levels.WARN)
	end,
})

-- Set tmux window name to the project folder name
if vim.env.TMUX then
	local project_name = vim.fn.fnamemodify(vim.fn.getcwd(), ":t")
	vim.api.nvim_create_autocmd("VimEnter", {
		callback = function()
			vim.fn.system("tmux rename-window " .. vim.fn.shellescape(project_name))
		end,
	})
	vim.api.nvim_create_autocmd("DirChanged", {
		callback = function()
			local name = vim.fn.fnamemodify(vim.fn.getcwd(), ":t")
			vim.fn.system("tmux rename-window " .. vim.fn.shellescape(name))
		end,
	})
	vim.api.nvim_create_autocmd("VimLeave", {
		callback = function()
			vim.fn.system("tmux set-window-option automatic-rename on")
		end,
	})
end
