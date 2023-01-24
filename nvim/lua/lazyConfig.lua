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

    -- Import cost
    'barrett-ruth/import-cost.nvim',


    'phaazon/hop.nvim',

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
      requires = {
        {'nvim-lua/popup.nvim'},
        {'nvim-lua/plenary.nvim'}
      }
    }
})
