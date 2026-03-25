local state = require("bq.state")
local util = require("bq.util")
local views = require("bq.views")
local globals = require("bq.globals")

local M = {}

local api = vim.api

local function fmt_ms(n)
    if not n then return "?" end
    n = tonumber(n)
    if not n then return "?" end
    if n >= 1000 then return string.format("%.1fs", n / 1000)
    else return string.format("%dms", n) end
end

---@param bufnr integer
M.show = function(bufnr)
    if not util.is_buf_valid(bufnr) or not util.is_win_valid(state.winnr) then
        return
    end

    if views.cleanup_view(bufnr, #state.history == 0, "  No query history") then
        return
    end

    -- Newest first
    local entries = vim.deepcopy(state.history)
    for i = 1, math.floor(#entries / 2) do
        entries[i], entries[#entries - i + 1] = entries[#entries - i + 1], entries[i]
    end

    local lines = {}
    local status_positions = {}

    for _, entry in ipairs(entries) do
        local time_str = os.date("%H:%M:%S", entry.ts)
        local status_icon
        local hl_group
        if entry.status == "ok" then
            status_icon = "✓"
            hl_group = "BQHistoryOk"
        elseif entry.status == "error" then
            status_icon = "✗"
            hl_group = "BQHistoryErr"
        else
            status_icon = "…"
            hl_group = "BQLoading"
        end

        local elapsed = fmt_ms(entry.elapsed_ms)
        local project = entry.project or "(default)"
        local sql_preview = (entry.sql:match("^%s*([^\n]+)") or "(empty)"):gsub("^%s+", "")
        if #sql_preview > 55 then sql_preview = sql_preview:sub(1, 52) .. "..." end

        local line = string.format("[%s] %s  %-6s  %-20s  %s",
            time_str, status_icon, elapsed, project, sql_preview)

        table.insert(status_positions, { #lines, 11, 11 + #status_icon, hl_group })
        table.insert(lines, line)
    end

    util.set_lines(bufnr, 0, -1, false, lines)

    local ns = globals.NAMESPACE
    for _, pos in ipairs(status_positions) do
        vim.hl.range(bufnr, ns, pos[4], { pos[1], pos[2] }, { pos[1], pos[3] })
    end

    -- <CR> to replay the query under cursor
    vim.keymap.set("n", "<CR>", function()
        if not util.is_win_valid(state.winnr) then return end
        local cursor = api.nvim_win_get_cursor(state.winnr)
        local line_idx = cursor[1]  -- 1-based
        local entry = entries[line_idx]
        if entry and entry.sql then
            require("bq.actions").run_query(entry.sql)
        end
    end, { buffer = bufnr, nowait = true, desc = "Replay query from history" })
end

return M
