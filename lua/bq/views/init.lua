local state = require("bq.state")
local util = require("bq.util")

local M = {}

local api = vim.api

---@param bufnr integer
---@param condition boolean
---@param message string
---@return boolean
M.cleanup_view = function(bufnr, condition, message)
    if not util.is_win_valid(state.winnr) or not util.is_buf_valid(bufnr) then
        return condition
    end

    if condition then
        vim.wo[state.winnr][0].cursorlineopt = "number"
        util.set_lines(bufnr, 0, -1, false, { message })
        local ns = require("bq.globals").NAMESPACE
        api.nvim_buf_clear_namespace(bufnr, ns, 0, -1)
        vim.hl.range(bufnr, ns, "BQMissingData", { 0, 0 }, { 0, #message })
    else
        vim.wo[state.winnr][0].cursorlineopt = "both"
    end

    return condition
end

---@param view string
---@param skip_restore_cursor? boolean
M.switch_to_view = function(view, skip_restore_cursor)
    if not util.is_win_valid(state.winnr) then return end
    local bufnr = state.bufs[view]
    if not util.is_buf_valid(bufnr) then return end

    local cursor = state.cur_pos[view] or { 1, 0 }
    local cursor_line, cursor_col = cursor[1], cursor[2]

    -- Swap the view-specific buffer into the window
    local cur_buf = api.nvim_win_get_buf(state.winnr)
    if cur_buf ~= bufnr then
        vim.wo[state.winnr][0].winfixbuf = false
        api.nvim_win_set_buf(state.winnr, bufnr)
        vim.wo[state.winnr][0].winfixbuf = true
    end

    require("bq.options.winbar").refresh_winbar(view)

    -- Clear namespace highlights before re-rendering
    api.nvim_buf_clear_namespace(bufnr, require("bq.globals").NAMESPACE, 0, -1)

    require("bq.views." .. view).show(bufnr)

    if not skip_restore_cursor then
        local buf_len = api.nvim_buf_line_count(bufnr)
        local line = math.min(cursor_line, math.max(buf_len, 1))
        local line_content = api.nvim_buf_get_lines(bufnr, line - 1, line, true)
        local line_len = line_content[1] and #line_content[1] or 0
        local col = math.min(cursor_col, line_len)

        state.cur_pos[view] = { line, col }
        pcall(api.nvim_win_set_cursor, state.winnr, { line, col })
    end
end

return M
