return {
	"saghen/blink.cmp",
	version = "*",
	opts = {
		enabled = function()
			return not vim.tbl_contains({ "snacks_picker_input" }, vim.bo.filetype)
		end,
		keymap = {
			preset = "default",
			["<Up>"] = { "select_prev", "fallback" },
			["<Down>"] = { "select_next", "fallback" },
			["<Tab>"] = { "select_and_accept", "fallback" },
			["<s-Tab>"] = { "select_prev", "fallback" },
			-- Enter only takes an item you selected; otherwise it is a newline
			["<Cr>"] = { "accept", "fallback" },
		},
		completion = {
			-- nothing selected until you move (<Tab> still takes the first one)
			list = { selection = { preselect = false, auto_insert = true } },
		},
		signature = { enabled = true },
		appearance = {
			nerd_font_variant = "Nerd Font Mono",
		},
		snippets = { preset = "luasnip" },
		-- Fuzzy completion on the : command line (menu shows while typing)
		cmdline = {
			enabled = true,
			keymap = { preset = "cmdline" },
			completion = {
				menu = {
					auto_show = function()
						return vim.fn.getcmdtype() == ":"
					end,
				},
			},
		},
		sources = {
			default = {
				"lsp",
				"path",
				"snippets",
				"buffer",
			},
		},
	},
	opts_extend = { "sources.default" },
}
