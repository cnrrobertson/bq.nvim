-- Add current directory to 'runtimepath' so local lua/ files are found
vim.cmd([[let &rtp.=','.getcwd()]])

-- Use the system-installed mini.nvim
vim.cmd('set rtp+=~/.local/share/nvim/site/pack/deps/start/mini.nvim')
require('mini.doc').setup()
require('mini.test').setup()
