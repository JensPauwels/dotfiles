vim.g.coq_settings = { 
  keymap = { 
    recommended = false,
    pre_select = true,
    jump_to_mark = 'nop'
  },
  auto_start = 'shut-up',
}

-- these mappings are coq recommended mappings unrelated to nvim-autopairs
vim.api.nvim_set_keymap('n', '<esc>', [[pumvisible() ? "<c-e><esc>" : "<esc>"]], { expr = true, noremap = true })
vim.api.nvim_set_keymap('n', '<c-c>', [[pumvisible() ? "<c-e><c-c>" : "<c-c>"]], { expr = true, noremap = true })
vim.api.nvim_set_keymap('n', '<tab>', [[pumvisible() ? "<c-n>" : "<tab>"]], { expr = true, noremap = true })
vim.api.nvim_set_keymap('n', '<s-tab>', [[pumvisible() ? "<c-p>" : "<bs>"]], { expr = true, noremap = true })
