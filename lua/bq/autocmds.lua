local api = vim.api
local state = require("bq.state")
local util = require("bq.util")

local group = api.nvim_create_augroup("bq", { clear = true })

-- Refresh winbar when window layout changes
api.nvim_create_autocmd({ "WinClosed", "WinNew" }, {
    group = group,
    callback = function()
        vim.schedule(function()
            if util.is_win_valid(state.winnr) then
                require("bq.options.winbar").set_winbar_opt()
            end
        end)
    end,
})

-- Save cursor position per view
api.nvim_create_autocmd("CursorMoved", {
    group = group,
    callback = function()
        if not util.is_win_valid(state.winnr) then return end
        if api.nvim_get_current_win() ~= state.winnr then return end
        if not state.current_section then return end
        local section_buf = state.bufs[state.current_section]
        if not section_buf then return end
        if api.nvim_win_get_buf(state.winnr) ~= section_buf then return end
        state.cur_pos[state.current_section] = api.nvim_win_get_cursor(state.winnr)
    end,
})
