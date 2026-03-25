local M = {}

local api = vim.api

---@param bufnr? integer
---@return boolean
M.is_buf_valid = function(bufnr)
    return bufnr ~= nil and api.nvim_buf_is_valid(bufnr)
end

---@param winnr? integer
---@return boolean
M.is_win_valid = function(winnr)
    return winnr ~= nil and api.nvim_win_is_valid(winnr)
end

---@param bufnr integer
---@param start integer
---@param end_ integer
---@param strict_indexing boolean
---@param replacement string[]
M.set_lines = function(bufnr, start, end_, strict_indexing, replacement)
    vim.bo[bufnr].modifiable = true
    api.nvim_buf_set_lines(bufnr, start, end_, strict_indexing, replacement)
    vim.bo[bufnr].modifiable = false
end

return M
