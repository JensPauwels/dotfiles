local M = {}

local servers = {
	"lua_ls",
	"vtsls",
}

local tools = {
	"stylua",
}

local function lsp_capabilities()
	local capabilities = vim.lsp.protocol.make_client_capabilities()
	return require("blink.cmp").get_lsp_capabilities(capabilities)
end

local function on_attach(client, bufnr)
	local Snacks = require("snacks")
	vim.keymap.set("n", "gd", Snacks.picker.lsp_definitions, { desc = "Goto Definition", buffer = bufnr })
	vim.keymap.set("n", "gr", Snacks.picker.lsp_references, { desc = "References", buffer = bufnr })
	vim.keymap.set("n", "gD", Snacks.picker.lsp_declarations, { desc = "Goto Declaration", buffer = bufnr })
	vim.keymap.set("n", "gI", Snacks.picker.lsp_implementations, { desc = "Goto Implementation", buffer = bufnr })
	vim.keymap.set("n", "gb", Snacks.picker.lsp_type_definitions, { desc = "Goto Type Definition", buffer = bufnr })
	vim.keymap.set("n", "K", vim.lsp.buf.hover, { desc = "Hover", buffer = bufnr })
	vim.keymap.set("n", "gK", vim.lsp.buf.signature_help, { desc = "Signature Help", buffer = bufnr })
	vim.keymap.set({ "n", "v" }, "<leader>ca", vim.lsp.buf.code_action, { desc = "Code Action", buffer = bufnr })
end

function M.setup()
	local mason_registry = require("mason-registry")
	local mason_lspconfig = require("mason-lspconfig")
	local lspconfig = require("lspconfig")

	-- Ensure tools installed
	for _, tool in ipairs(tools) do
		local ok, package = pcall(mason_registry.get_package, tool)
		if ok and not package:is_installed() then
			package:install()
		end
	end

	-- Ensure LSP servers installed
	mason_lspconfig.setup({
		ensure_installed = servers,
		automatic_installation = true,
	})

	-- Manually set up each server
	for _, server_name in ipairs(servers) do
		local opts = {
			capabilities = lsp_capabilities(),
			on_attach = on_attach,
		}

		-- Optional server-specific settings
		if server_name == "lua_ls" then
			opts.settings = {
				Lua = {
					diagnostics = { globals = { "vim" } },
				},
			}
		end

		if lspconfig[server_name] then
			lspconfig[server_name].setup(opts)
		else
			vim.notify("LSP server not found in lspconfig: " .. server_name, vim.log.levels.WARN)
		end
	end
end

return M
