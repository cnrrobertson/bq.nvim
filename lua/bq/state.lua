---@class bq.QueryError
---@field raw string        raw output from the bq CLI
---@field info table        parsed result from parse_bq_error
---@field elapsed_ms integer

---@class bq.State
---@field bufs table<string, integer>
---@field winnr? integer          virtual field — resolves to tab_wins[current_tabpage]
---@field tab_wins table<integer, integer>   tabpage_id → window_id (backing store for winnr)
---@field current_section? string
---@field cur_pos table<string, integer[]>
---@field project? string
---@field current_job? integer
---@field last_query? string
---@field results_data table
---@field results_schema string[]
---@field stats_data table
---@field history table
---@field schema_dataset? string
---@field schema_table? string
---@field query_error? bq.QueryError  set when the last query failed, nil otherwise

local _tab_wins = {}

local M = {
    bufs = {},
    tab_wins = _tab_wins,   -- exposed for vim.tbl_isempty checks in actions.lua
    cur_pos = {},
    results_data = {},
    results_schema = {},
    stats_data = {},
    history = {},
    debug_log = {},
    query_error = nil,
}

-- Make state.winnr a virtual field: reads/writes transparently use the current
-- tabpage's window ID.  All existing `state.winnr` references across the plugin
-- work correctly for multi-tab without any further changes.
setmetatable(M, {
    __index = function(_, k)
        if k == "winnr" then
            return _tab_wins[vim.api.nvim_get_current_tabpage()]
        end
    end,
    __newindex = function(t, k, v)
        if k == "winnr" then
            _tab_wins[vim.api.nvim_get_current_tabpage()] = v
        else
            rawset(t, k, v)
        end
    end,
})

return M
