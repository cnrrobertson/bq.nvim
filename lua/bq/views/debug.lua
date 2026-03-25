local state = require("bq.state")
local util = require("bq.util")
local views = require("bq.views")

local M = {}

---@param bufnr integer
M.show = function(bufnr)
    if not util.is_buf_valid(bufnr) or not util.is_win_valid(state.winnr) then
        return
    end

    if views.cleanup_view(bufnr, #state.debug_log == 0, "  No debug activity yet") then
        return
    end

    util.set_lines(bufnr, 0, -1, false, state.debug_log)
end

return M
