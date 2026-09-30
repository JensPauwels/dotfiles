local M = {}

local servers = {
	lua_ls = {
		settings = {
			Lua = {
				diagnostics = { globals = { "vim", "Snacks" } },
			},
		},
	},
	ts_ls = {
		root_dir = function(bufnr, cb)
			local root = vim.fs.root(bufnr, ".git")
			cb(root)
		end,
		single_file_support = false,
	},
	gopls = {},
	terraformls = {},
	tailwindcss = {},
	intelephense = {
		root_dir = function(bufnr, cb)
			local root = vim.fs.root(bufnr, { "composer.json", ".git" })
			cb(root)
		end,
		init_options = {
			licenceKey = vim.env.INTELEPENSE_LICENSE_KEY,
		},
		settings = {
			intelephense = {
				files = { maxSize = 5000000 },
				environment = { phpVersion = "8.3" },
			},
		},
	},
}

function M.setup()
	local capabilities = require("blink.cmp").get_lsp_capabilities()

	for name, opts in pairs(servers) do
		opts.capabilities = vim.tbl_deep_extend("force", {}, capabilities, opts.capabilities or {})
		vim.lsp.config(name, opts)
		vim.lsp.enable(name)
	end

	vim.diagnostic.config({
		virtual_text = { spacing = 2, prefix = "●" },
		severity_sort = true,
		float = { border = "rounded", source = true },
	})
end

vim.api.nvim_create_autocmd("LspAttach", {
	callback = function(args)
		local bufnr = args.buf

		local function map(mode, lhs, rhs, desc)
			vim.keymap.set(mode, lhs, rhs, { buffer = bufnr, desc = desc })
		end

		map("n", "gd", function() Snacks.picker.lsp_definitions() end, "Goto Definition")
		map("n", "gr", function() Snacks.picker.lsp_references() end, "References")
		map("n", "gD", function() Snacks.picker.lsp_declarations() end, "Goto Declaration")
		map("n", "gI", function() Snacks.picker.lsp_implementations() end, "Goto Implementation")
		map("n", "gb", function() Snacks.picker.lsp_type_definitions() end, "Goto Type Definition")
		map("n", "K", vim.lsp.buf.hover, "Hover")
		map("n", "gK", vim.lsp.buf.signature_help, "Signature Help")
		map({ "n", "v" }, "<leader>ca", vim.lsp.buf.code_action, "Code Action")
	end,
})

return M
