return {
	"saghen/blink.cmp",
	dependencies = {
		"fang2hou/blink-copilot",
	},
	version = "*",
	opts = {
		enabled = function()
			return not vim.tbl_contains({ "snacks_picker_input" }, vim.bo.filetype)
		end,
		keymap = {
			preset = "default",
			["<Up>"] = { "select_prev", "fallback" },
			["<Down>"] = { "select_next", "fallback" },
			["<Tab>"] = { "select_next", "fallback" },
			["<s-Tab>"] = { "select_prev", "fallback" },
			["<Cr>"] = { "select_and_accept", "fallback" },
		},
		signature = { enabled = true },
		appearance = {
			nerd_font_variant = "Nerd Font Mono",
		},
		snippets = { preset = "luasnip" },
		sources = {
			cmdline = {},
			default = {
				"lsp",
				"path",
				"snippets",
				"buffer",
				"copilot",
			},
			providers = {
				copilot = {
					name = "copilot",
					module = "blink-copilot",
					score_offset = 100,
					async = true,
					opts = {
						max_completions = 3,
					},
				},
			},
		},
	},
	opts_extend = { "sources.default" },
}
