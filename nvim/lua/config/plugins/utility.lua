return {
  -- Spell checking
  'kamykn/spelunker.vim',

  -- Themes
  'rebelot/kanagawa.nvim',
  'Shatur/neovim-ayu',
  'catppuccin/nvim',
  "loctvl842/monokai-pro.nvim",

  -- Highlighting
  'folke/lsp-colors.nvim',
  'ap/vim-css-color',
  'maxmellon/vim-jsx-pretty',

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

  -- FZF is required for my custom plugins
  'vijaymarupudi/nvim-fzf',

  -- easy motion
  'easymotion/vim-easymotion',

  -- Commentary
  'tpope/vim-commentary',

  -- git
  'folke/trouble.nvim',

  -- snippets
  'SirVer/ultisnips' ,

  -- tabline
  'mkitt/tabline.vim',

  { 
    'nvim-telescope/telescope.nvim',
    dependencies = {
      {'nvim-lua/popup.nvim'},
      {'nvim-lua/plenary.nvim'}
    }
  }
}