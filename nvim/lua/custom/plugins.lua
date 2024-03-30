local overrides = require("custom.configs.overrides")


local plugins = {
  {
    "tpope/vim-abolish",
    lazy = false
  },
  {
    "tpope/vim-surround",
    lazy = false
  },
  {
    "rcarriga/nvim-dap-ui",
    event = "VeryLazy",
    dependencies = "mfussenegger/nvim-dap",
    config = function()
      local dap = require("dap")
      local dapui = require("dapui")
      require("dapui").setup()
      dap.listeners.after.event_initialized["dapui_config"] = function()
        dapui.open()
      end
      dap.listeners.before.event_terminated["dapui_config"] = function()
        dapui.close()
      end
      dap.listeners.before.event_exited["dapui_config"] = function()
        dapui.close()
      end
    end
  },
  {
    "mfussenegger/nvim-dap",
    config = function()
      require "custom.configs.dap"
      require("core.utils").load_mappings("dap")
    end
  },
  {
    "zbirenbaum/copilot.lua",
    event = "InsertEnter",
    opts = overrides.copilot,
  },
  {
    "mhartington/formatter.nvim",
    event = "VeryLazy",
    opts = function()
      return require "custom.configs.formatter"
    end
  },
  {
    "mfussenegger/nvim-lint",
    event = "VeryLazy",
    config = function()
      require "custom.configs.lint"
    end
  },
  {
    "williamboman/mason.nvim",
    opts = {
      ensure_installed = {
        "eslint-lsp",
        "js-debug-adapter",
        "prettier",
        "typescript-language-server",
        "cssls",
        "gopls"
      }
    }
  },
  {
    "neovim/nvim-lspconfig",
    config = function()
      require "plugins.configs.lspconfig"
      require "custom.configs.lspconfig"
    end,
  },
  {
    "MaxMEllon/vim-jsx-pretty",
  },
  {
    "kdheepak/lazygit.nvim",
    lazy = false
  },
  {
    "fatih/vim-go",
    lazy = false
  },
  {
    "andythigpen/nvim-coverage",
    dependencies = {
      {
        "nvim-lua/plenary.nvim",
        config = function()
          require("coverage").setup()
        end,
      },
    },
  },
  {
    "nvim-neotest/neotest",
    dependencies = {
      "nvim-lua/plenary.nvim",
      "antoinemadec/FixCursorHold.nvim",
      "nvim-treesitter/nvim-treesitter"
    }
  },
  {
    "hrsh7th/nvim-cmp",
    dependencies = {
      {
        "zbirenbaum/copilot-cmp",
        config = function()
          require("copilot_cmp").setup()
        end,
      },
    },
    opts = {
      sources = {
        { name = "copilot",  group_index = 2 },
        { name = "nvim_lsp", group_index = 2 },
        { name = "luasnip",  group_index = 2 },
        { name = "buffer",   group_index = 2 },
        { name = "nvim_lua", group_index = 2 },
        { name = "path",     group_index = 2 },
      },
    },
  },
  {
    lazy = false,
    "NeogitOrg/neogit",
    dependencies = {
      "nvim-lua/plenary.nvim",         -- required
      "sindrets/diffview.nvim",        -- optional - Diff integration

      -- Only one of these is needed, not both.
      "nvim-telescope/telescope.nvim", -- optional
      "ibhagwan/fzf-lua",              -- optional
    },
    config = true
  },
  {
    lazy = false,
    "vim-test/vim-test",
  },
  {
    lazy = false,
    "andythigpen/nvim-coverage",
    dependencies = {
      "nvim-lua/plenary.nvim"
    },
    config = function()
      require("coverage").setup({
        auto_reload = true,
        commands = true, -- create commands
        highlights = {
          -- customize highlight groups created by the plugin
          covered = { fg = "#C3E88D", bg = "#C3E88D" },   -- supports style, fg, bg, sp (see :h highlight-gui)
          uncovered = { fg = "#F07178", bg = "#F07178" },
        },
        signs = {
          -- use your own highlight groups or text markers
          covered = { hl = "CoverageCovered", text = "▎" },
          uncovered = { hl = "CoverageUncovered", text = "▎" },
        }
      })
    end,
  },
  {
    lazy = false,
    'pwntester/octo.nvim',
    dependencies = {
      'nvim-lua/plenary.nvim',
      'nvim-telescope/telescope.nvim',
      -- OR 'ibhagwan/fzf-lua',
      'nvim-tree/nvim-web-devicons',
    },
    config = function ()
      require"octo".setup({
        suppress_missing_scope = {
          project_v2 = true,
        }
      })
    end
  },
  {
    lazy = false,
    'akinsho/git-conflict.nvim',
    config = function()
      require("git-conflict").setup()
    end
  }
}
return plugins
