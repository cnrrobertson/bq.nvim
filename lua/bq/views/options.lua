local state = require("bq.state")
local setup = require("bq.setup")

local M = {}

---@param bufnr integer
M.set_buf_options = function(bufnr)
    local buf = vim.bo[bufnr]
    buf.buftype    = "nofile"
    buf.swapfile   = false
    buf.modifiable = false
    buf.filetype   = "bq"
    buf.bufhidden  = "hide"
end

M.set_win_options = function()
    local win = vim.wo[state.winnr][0]
    win.wrap           = false
    win.number         = false
    win.relativenumber = false
    win.cursorline     = true
    win.cursorlineopt  = "line"
    win.scrolloff      = 3
    win.statuscolumn   = ""
    win.foldcolumn     = "0"
    win.winfixbuf      = true
    win.signcolumn     = "no"

    local pos = setup.config.windows.position
    if pos == "above" or pos == "below" then
        win.winfixheight = true
    else
        win.winfixwidth = true
    end
end

return M
