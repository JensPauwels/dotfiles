local M = {}

local servers = {
	"lua_ls",
	"ts_ls",
	"gopls",
}

local function lsp_capabilities()
	local capabilities = vim.lsp.protocol.make_client_capabilities()
	return require("blink.cmp").get_lsp_capabilities(capabilities)
end

function M.setup()
	local mason_lspconfig = require("mason-lspconfig")
	local lspconfig = require("lspconfig")

	-- Setup LSP servers manually
	mason_lspconfig.setup({
		ensure_installed = servers,
		automatic_installation = true,
	})

	for _, server_name in ipairs(servers) do
		local opts = {
			capabilities = lsp_capabilities(),
		}

		if server_name == "lua_ls" then
			opts.settings = {
				Lua = {
					diagnostics = { globals = { "vim" } },
				},
			}
		end

		lspconfig[server_name].setup(opts)
	end
end

-- Setup LSP keymaps on LspAttach
vim.api.nvim_create_autocmd("LspAttach", {
	callback = function(args)
		local bufnr = args.buf
		local Snacks = require("snacks")

		local function map(mode, lhs, rhs, desc)
			vim.keymap.set(mode, lhs, rhs, { buffer = bufnr, desc = desc })
		end

		map("n", "gd", Snacks.picker.lsp_definitions, "Goto Definition")
		map("n", "gr", Snacks.picker.lsp_references, "References")
		map("n", "gD", Snacks.picker.lsp_declarations, "Goto Declaration")
		map("n", "gI", Snacks.picker.lsp_implementations, "Goto Implementation")
		map("n", "gb", Snacks.picker.lsp_type_definitions, "Goto Type Definition")
		map("n", "K", vim.lsp.buf.hover, "Hover")
		map("n", "gK", vim.lsp.buf.signature_help, "Signature Help")
		map({ "n", "v" }, "<leader>ca", vim.lsp.buf.code_action, "Code Action")
	end,
})

return M
