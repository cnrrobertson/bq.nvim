local state = require("bq.state")
local util = require("bq.util")
local views = require("bq.views")
local globals = require("bq.globals")
local persist = require("bq.persist")

local M = {}

local api = vim.api

local function fmt_ms(n)
    if not n then return "?" end
    n = tonumber(n)
    if not n then return "?" end
    if n >= 1000 then return string.format("%.1fs", n / 1000)
    else return string.format("%dms", n) end
end

-- Find the original (non-copied) entry in state.history by timestamp.
-- Used when mutating entries (e.g. setting a name).
local function find_original(ts)
    for i, e in ipairs(state.history) do
        if e.ts == ts then return i, e end
    end
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

    local hint = "  <CR> load results · r re-run · o see query · n rename"
    local lines = { hint }
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

        -- Show name in brackets when set; otherwise show truncated SQL
        local label
        if entry.name and entry.name ~= "" then
            label = "[" .. entry.name .. "]"
        else
            local sql_preview = (entry.sql:match("^%s*([^\n]+)") or "(empty)"):gsub("^%s+", "")
            if #sql_preview > 55 then sql_preview = sql_preview:sub(1, 52) .. "..." end
            label = sql_preview
        end

        -- ● (U+25CF, 3 bytes UTF-8) at byte 15 when results are cached; space otherwise
        local cache_dot = entry.results_id and "●" or " "
        local line = string.format("[%s] %s %s  %-6s  %-20s  %s",
            time_str, status_icon, cache_dot, elapsed, project, label)

        table.insert(status_positions, { #lines, 11, 11 + #status_icon, hl_group })
        if entry.results_id then
            -- cache_dot starts at byte 15: 11 (prefix) + 3 (status_icon) + 1 (space)
            table.insert(status_positions, { #lines, 15, 18, "Comment" })
        end
        table.insert(lines, line)
    end

    util.set_lines(bufnr, 0, -1, false, lines)

    local ns = globals.NAMESPACE

    -- Dim the hint line like the results view hint
    vim.hl.range(bufnr, ns, "BQHint", { 0, 0 }, { 0, #hint })

    for _, pos in ipairs(status_positions) do
        vim.hl.range(bufnr, ns, pos[4], { pos[1], pos[2] }, { pos[1], pos[3] })
    end

    -- <CR>: load cached results if available, otherwise re-run against BigQuery
    vim.keymap.set("n", "<CR>", function()
        if not util.is_win_valid(state.winnr) then return end
        local entry = entries[api.nvim_win_get_cursor(state.winnr)[1] - 1]
        if not entry or not entry.sql then return end

        if entry.results_id then
            local rows = persist.load_results(entry.results_id)
            if rows then
                state.results_data = rows
                local cols = {}
                if rows[1] then
                    for k in pairs(rows[1]) do table.insert(cols, tostring(k)) end
                    table.sort(cols)
                end
                state.results_schema = cols
                require("bq.views.results").clear_filter()
                require("bq.views").switch_to_view("results")
                vim.notify(("[bq] Loaded cached results (%d rows)"):format(#rows),
                    vim.log.levels.INFO)
                return
            end
            -- Result file missing (deleted externally) — fall through to live re-run
            vim.notify("[bq] Cache file missing — re-running query…", vim.log.levels.WARN)
        end

        require("bq.actions").run_query(entry.sql)
    end, { buffer = bufnr, nowait = true, desc = "Load cached results or replay query" })

    -- r: always force a live re-run against BigQuery, ignoring any cache
    vim.keymap.set("n", "r", function()
        if not util.is_win_valid(state.winnr) then return end
        local entry = entries[api.nvim_win_get_cursor(state.winnr)[1] - 1]
        if entry and entry.sql then require("bq.actions").run_query(entry.sql) end
    end, { buffer = bufnr, nowait = true, desc = "Force re-run query against BigQuery" })

    -- o: show full SQL in a centred floating window
    vim.keymap.set("n", "o", function()
        if not util.is_win_valid(state.winnr) then return end
        local entry = entries[api.nvim_win_get_cursor(state.winnr)[1] - 1]
        if not entry or not entry.sql then return end

        local sql_lines = vim.split(entry.sql, "\n", { plain = true })

        -- Width: widest line + 4 padding, capped at 75% of editor width
        local max_w = math.max(40, math.floor(vim.o.columns * 0.75))
        local content_w = 0
        for _, l in ipairs(sql_lines) do content_w = math.max(content_w, #l) end
        local width = math.min(max_w, content_w + 4)

        -- Height: line count + 2 for border, capped at 60% of editor height
        local height = math.min(math.floor(vim.o.lines * 0.6), #sql_lines + 2)
        height = math.max(height, 3)

        local float_buf = api.nvim_create_buf(false, true)
        api.nvim_buf_set_lines(float_buf, 0, -1, false, sql_lines)
        vim.bo[float_buf].modifiable = false
        vim.bo[float_buf].filetype = "sql"

        local title = entry.name and (" " .. entry.name .. " ") or " Query "
        local win = api.nvim_open_win(float_buf, true, {
            relative  = "editor",
            width     = width,
            height    = height,
            row       = math.floor((vim.o.lines - height) / 2),
            col       = math.floor((vim.o.columns - width) / 2),
            style     = "minimal",
            border    = "rounded",
            title     = title,
            title_pos = "center",
        })
        vim.wo[win].wrap = true

        for _, key in ipairs({ "q", "<Esc>" }) do
            vim.keymap.set("n", key, function()
                pcall(api.nvim_win_close, win, true)
            end, { buffer = float_buf, nowait = true })
        end
    end, { buffer = bufnr, nowait = true, desc = "Preview full query SQL" })

    -- n: set or rename a query (persisted immediately)
    vim.keymap.set("n", "n", function()
        if not util.is_win_valid(state.winnr) then return end
        local entry = entries[api.nvim_win_get_cursor(state.winnr)[1] - 1]
        if not entry then return end

        local _, orig = find_original(entry.ts)
        if not orig then return end

        vim.ui.input({
            prompt  = "Query name (empty to clear): ",
            default = orig.name or "",
        }, function(input)
            if input == nil then return end  -- user cancelled with <Esc>
            orig.name = (input ~= "" and input or nil)
            persist.save_history()
            -- Re-render so the name appears immediately
            M.show(bufnr)
        end)
    end, { buffer = bufnr, nowait = true, desc = "Name / rename query" })
end

return M
