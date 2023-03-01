vim.o.ruler = false
vim.o.splitright = true
vim.o.splitbelow = true
vim.o.ignorecase = true
vim.o.hlsearch = true
vim.o.background = 'dark'
vim.o.termguicolors = true
vim.o.lazyredraw = true

vim.o.hidden = true
vim.o.updatetime = 300
vim.o.scrolloff = 5
vim.o.sidescrolloff = 5
vim.o.completeopt = 'menuone,noinsert,noselect'
vim.o.shortmess = vim.o.shortmess .. 'c'
vim.o.showmode = false

vim.wo.number = true
vim.wo.relativenumber = true
vim.wo.signcolumn = 'number'
vim.wo.wrap = true

vim.o.tabstop = 2
vim.bo.tabstop = 2
vim.o.softtabstop = 2
vim.bo.softtabstop = 2
vim.o.shiftwidth = 2
vim.bo.shiftwidth = 2
vim.o.autoindent = true
vim.bo.autoindent = true
vim.o.expandtab = true
vim.bo.expandtab = true

vim.cmd('language en_US.utf-8')
vim.wo.list = true
vim.o.listchars = 'tab:┆·,trail:·,precedes:,extends:'

vim.g.markdown_fenced_languages = {'sh', 'vim'}

vim.g.termbufm_direction_cmd = 'new'

vim.g.mapleader = ' '
vim.b.mapleader = ' '

vim.g.user_emmet_leader_key = ','
vim.g.user_emmet_settings = [[{
	'javascript.js' : {
		'extends' : 'jsx',
	},
	'typescript' : {
		'extends' : 'jsx',
	},
}]]

vim.g.UltiSnipsSnippetsDir = '~/.config/nvim/ultisnips'

vim.api.nvim_command('set colorcolumn=100')

