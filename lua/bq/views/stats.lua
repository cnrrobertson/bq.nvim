local state = require("bq.state")
local util = require("bq.util")
local views = require("bq.views")
local globals = require("bq.globals")

local M = {}

local function fmt_bytes(n)
    if not n then return "—" end
    n = tonumber(n)
    if not n then return "—" end
    if n >= 1e9 then return string.format("%.2f GB", n / 1e9)
    elseif n >= 1e6 then return string.format("%.2f MB", n / 1e6)
    elseif n >= 1e3 then return string.format("%.1f KB", n / 1e3)
    else return string.format("%d B", n)
    end
end

local function fmt_ms(n)
    if not n then return "—" end
    n = tonumber(n)
    if not n then return "—" end
    if n >= 60000 then return string.format("%.1f min", n / 60000)
    elseif n >= 1000 then return string.format("%.2f s", n / 1000)
    else return string.format("%d ms", n)
    end
end

---@param bufnr integer
M.show = function(bufnr)
    if not util.is_buf_valid(bufnr) or not util.is_win_valid(state.winnr) then
        return
    end

    if views.cleanup_view(bufnr, vim.tbl_isempty(state.stats_data), "  Run a query to see stats") then
        return
    end

    local data = state.stats_data

    local items = {
        { "Status",          data.status or "—" },
        { "Total Rows",      data.total_rows and tostring(data.total_rows) or "—" },
        { "Elapsed",         fmt_ms(data.elapsed_ms) },
        { "Bytes Processed", fmt_bytes(data.bytes_processed) },
        { "Bytes Billed",    fmt_bytes(data.bytes_billed) },
        { "Slot ms",         data.slot_ms and fmt_ms(data.slot_ms) or "—" },
        { "Cache Hit",       data.cache_hit ~= nil and (data.cache_hit and "yes" or "no") or "—" },
        { "Job ID",          data.job_id or "—" },
        { "Project",         state.project or "(default)" },
    }

    local key_width = 0
    for _, item in ipairs(items) do
        if #item[1] > key_width then key_width = #item[1] end
    end

    local lines = { "" }
    local key_ranges = {}

    for _, item in ipairs(items) do
        local padding = string.rep(" ", key_width - #item[1])
        local line = "  " .. item[1] .. padding .. "  " .. item[2]
        table.insert(key_ranges, { #lines, 2, 2 + #item[1] })
        table.insert(lines, line)
    end
    table.insert(lines, "")

    util.set_lines(bufnr, 0, -1, false, lines)

    local ns = globals.NAMESPACE
    for _, r in ipairs(key_ranges) do
        vim.hl.range(bufnr, ns, "BQStatKey", { r[1], r[2] }, { r[1], r[3] })
    end
end

return M
