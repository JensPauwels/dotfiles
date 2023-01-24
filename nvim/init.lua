local lazypath = vim.fn.stdpath("data") .. "/lazy/lazy.nvim"
 if not vim.loop.fs_stat(lazypath) then
   vim.fn.system({
     "git",
     "clone",
     "--filter=blob:none",
     "--single-branch",
     "https://github.com/folke/lazy.nvim.git",
     lazypath,
   })
 end
 vim.opt.runtimepath:prepend(lazypath)

require('options')
require('maps')
require('coqConfig')
require('lazyConfig')
require('tokyonightConfig')
require('styleconfig')
require('lspConfig')
require('treesitterConfig')
require('autopairsConfig')
require('supertabconfig')
require('hopConfig')
