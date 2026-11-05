return {
	"nvim-treesitter/nvim-treesitter",
	branch = "main",
	lazy = false,
	build = ":TSUpdate",
	config = function()
		require("nvim-treesitter").setup()

		vim.api.nvim_create_autocmd("FileType", {
			callback = function(args)
				local bufnr = args.buf
				local ft = vim.bo[bufnr].filetype
				if ft == "" then
					return
				end
				local lang = vim.treesitter.language.get_lang(ft) or ft
				local function start()
					if not vim.api.nvim_buf_is_valid(bufnr) then
						return
					end
					pcall(vim.treesitter.start, bufnr, lang)
					vim.bo[bufnr].indentexpr = "v:lua.require'nvim-treesitter'.indentexpr()"
				end
				if pcall(vim.treesitter.language.add, lang) then
					start()
					return
				end
				-- No parser yet: install it the first time the language is opened
				if vim.tbl_contains(require("nvim-treesitter").get_available(), lang) then
					require("nvim-treesitter").install({ lang }):await(function(err)
						vim.schedule(function()
							if not err and pcall(vim.treesitter.language.add, lang) then
								start()
							end
						end)
					end)
				end
			end,
		})
	end,
}
