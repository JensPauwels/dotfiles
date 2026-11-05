-- Set tab width to 2 spaces
vim.opt.tabstop = 2
vim.opt.shiftwidth = 2

vim.opt.expandtab = true

-- Enable relative line numbers
vim.opt.number = true
vim.opt.relativenumber = true

-- Set the leader to space
vim.g.mapleader = " "

-- No wrapping for code; prose wraps at word boundaries
vim.opt.wrap = false
vim.api.nvim_create_autocmd("FileType", {
	pattern = { "markdown", "text", "gitcommit" },
	callback = function()
		vim.opt_local.wrap = true
		vim.opt_local.linebreak = true
	end,
})

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

-- Undo survives closing the file, restarts and reloads after outside edits
vim.opt.undofile = true

-- Always room for signs, so text doesn't shift when signs/diagnostics appear
vim.opt.signcolumn = "yes"

-- Keep some lines around the cursor; highlight its line
vim.opt.scrolloff = 8
vim.opt.cursorline = true

-- Preview :s/…/…/ in a split while typing
vim.opt.inccommand = "split"

-- Ask instead of failing on :q with unsaved changes
vim.opt.confirm = true

-- y / p use the system clipboard (set after startup: the provider is slow to load)
vim.schedule(function()
	vim.opt.clipboard = "unnamedplus"
end)

vim.opt.autoread = true
-- Faster CursorHold trigger (default 4000ms is too slow for external change detection)
vim.opt.updatetime = 250

vim.api.nvim_create_autocmd({ "BufEnter", "CursorHold", "CursorHoldI", "FocusGained" }, {
	pattern = "*",
	command = "if mode() !~ 'r' && getcmdwintype() == '' | checktime | endif",
})

-- A quiet hint when a file is reloaded because something else (Claude)
-- changed it; undo (u) takes you back to before the change.
vim.api.nvim_create_autocmd("FileChangedShellPost", {
	pattern = "*",
	callback = function(ev)
		local name = vim.fn.fnamemodify(ev.file, ":~:.")
		vim.api.nvim_echo({ { "↻ " .. name .. " changed on disk, reloaded", "Comment" } }, false, {})
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
