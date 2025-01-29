local M = {}

local servers = {
	"lua_ls",
	"ts_ls",
}

local tools = {
	"stylua",
}

local function lsp_capabilities()
	local capabilities = vim.lsp.protocol.make_client_capabilities()
	return require("blink.cmp").get_lsp_capabilities(capabilities)
end

function M.setup()
	local mason_registry = require("mason-registry")
	local mason_lspconfig = require("mason-lspconfig")

	-- Ensure required tools are installed
	for _, tool in ipairs(tools) do
		local package = mason_registry.get_package(tool)
		if not package:is_installed() then
			package:install()
		end
	end

	-- Ensure required LSP servers are installed
	mason_lspconfig.setup({ ensure_installed = servers })

	-- Setup LSP servers
	mason_lspconfig.setup_handlers({
		function(server)
			local opts = {
				capabilities = lsp_capabilities(),
			}
			require("lspconfig")[server].setup(opts)
		end,
	})
end

return M
