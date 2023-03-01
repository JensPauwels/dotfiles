local lazypath = vim.fn.stdpath("data") .. "/lazy/lazy.nvim"
 if not vim.loop.fs_stat(lazypath) then
   vim.fn.system({
     "git",
     "clone",
     "--filter=blob:none",
     "--single-branch",
     "https://github.com/folke/lazy.nvim.git",
     lazypath,
   })
 end

vim.opt.runtimepath:prepend(lazypath)

require("lazy").setup({
  -- Spell checking
  'kamykn/spelunker.vim',
  -- Themes
  'challenger-deep-theme/vim',
  'rebelot/kanagawa.nvim',
  'yunlingz/equinusocio-material.vim',
  'Shatur/neovim-ayu',
  'catppuccin/nvim',
  'folke/tokyonight.nvim',
  {
    "loctvl842/monokai-pro.nvim",
    config = function()
      require("monokai-pro").setup()
    end
  },

  -- Highlighting
  'folke/lsp-colors.nvim',
  'ap/vim-css-color',
  'maxmellon/vim-jsx-pretty',
  'nvim-treesitter/nvim-treesitter',
  -- Statusline
  'nvim-lualine/lualine.nvim',

  -- Completion
  { 
    'ms-jpq/coq_nvim',
    branch = 'coq',
    cmd = "COQnow",
  } ,

  -- Svelte
  'evanleck/vim-svelte',
  'HerringtonDarkholme/yats.vim',

  -- Golang
  'fatih/vim-go',
  'sebdah/vim-delve',

  -- Lsp
  'onsails/lspkind-nvim',
  'neovim/nvim-lspconfig',

  -- Completion
  'nvim-lua/plenary.nvim',
  'tpope/vim-abolish',
  'mattn/emmet-vim',
  'ervandew/supertab',
  'tpope/vim-surround',
  'windwp/nvim-autopairs',

  -- FZF is required for my custom plugins
  'vijaymarupudi/nvim-fzf',

  -- easy motion
  'easymotion/vim-easymotion',

  -- Commentary
  'tpope/vim-commentary',

  -- Navigation
  { 'kyazdani42/nvim-tree.lua', config = function() require'nvim-tree'.setup { } end },

  -- git
  'folke/trouble.nvim',

  -- snippets
  'SirVer/ultisnips' ,

  -- tabline
  'mkitt/tabline.vim',

  { 'nvim-telescope/telescope.nvim',
  dependencies = {
    {'nvim-lua/popup.nvim'},
    {'nvim-lua/plenary.nvim'}
  }
}
}, {})
