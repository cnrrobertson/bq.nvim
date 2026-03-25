local api = vim.api

local M = {}

---@param bufnr integer
---@param callback fun()
M.quit_buf_autocmd = function(bufnr, callback)
    api.nvim_create_autocmd("BufWipeout", {
        buffer = bufnr,
        once = true,
        callback = callback,
    })
end

return M
