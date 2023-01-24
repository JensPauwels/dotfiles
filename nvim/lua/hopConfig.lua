-- place this in one of your configuration file(s)
local hop = require('hop')
local directions = require('hop.hint').HintDirection
vim.keymap.set('', '<Leader>wh', function()
  hop.hint_char1({})
end, {remap=true})

hop.setup()

