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
				if not pcall(vim.treesitter.language.add, lang) then
					return
				end
				pcall(vim.treesitter.start, bufnr, lang)
				vim.bo[bufnr].indentexpr = "v:lua.require'nvim-treesitter'.indentexpr()"
			end,
		})
	end,
}
