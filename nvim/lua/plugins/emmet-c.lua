return {
	"mattn/emmet-vim",
	init = function()
		vim.g.user_emmet_leader_key = ","
		vim.g.user_emmet_settings = [[{
      'javascript.js' : {
        'extends' : 'jsx',
      },
      'typescript' : {
        'extends' : 'jsx',
      },
    }]]
	end,
}
