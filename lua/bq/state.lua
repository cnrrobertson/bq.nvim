---@class bq.QueryError
---@field raw string        raw output from the bq CLI
---@field info table        parsed result from parse_bq_error
---@field elapsed_ms integer

---@class bq.State
---@field bufs table<string, integer>
---@field winnr? integer
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
local M = {
    bufs = {},
    cur_pos = {},
    results_data = {},
    results_schema = {},
    stats_data = {},
    history = {},
    debug_log = {},
    query_error = nil,
}

return M
