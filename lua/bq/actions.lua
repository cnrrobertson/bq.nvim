local state = require("bq.state")
local setup = require("bq.setup")
local util = require("bq.util")
local globals = require("bq.globals")
local winbar = require("bq.options.winbar")

local M = {}

local api = vim.api
local go = vim.go

M.toggle = function()
    if util.is_win_valid(state.winnr) then
        M.close()
    else
        M.open()
    end
end

M.close = function()
    local winnr = state.winnr
    state.winnr = nil  -- clear first so WinClosed callback is a no-op

    if util.is_win_valid(winnr) then
        pcall(api.nvim_win_close, winnr, true)
    end

    for _, bufnr in pairs(state.bufs) do
        if util.is_buf_valid(bufnr) then
            pcall(api.nvim_buf_delete, bufnr, { force = true })
        end
    end
    state.bufs = {}
end

M.open = function()
    M.close()

    local cfg = setup.config.windows
    local pos = cfg.position
    local is_vertical = pos == "above" or pos == "below"
    local size_ = cfg.size
    local size = size_ < 1
        and math.floor((is_vertical and go.lines or go.columns) * size_)
        or math.floor(size_)

    -- Create one buffer per section
    local sections = setup.config.winbar.sections
    for _, section in ipairs(sections) do
        local bufnr = api.nvim_create_buf(false, false)
        assert(bufnr ~= 0, "[bq] Failed to create buffer for " .. section)
        local name = globals.buf_name(section)
        for _, buf in ipairs(api.nvim_list_bufs()) do
            if buf ~= bufnr and api.nvim_buf_get_name(buf) == name then
                pcall(api.nvim_buf_delete, buf, { force = true })
            end
        end
        api.nvim_buf_set_name(bufnr, name)
        require("bq.views.options").set_buf_options(bufnr)
        state.bufs[section] = bufnr
    end

    local initial_section = state.current_section or setup.config.winbar.default_section
    local initial_buf = state.bufs[initial_section]

    local winnr = api.nvim_open_win(initial_buf, false, {
        split  = pos,
        win    = -1,
        height = is_vertical and size or nil,
        width  = not is_vertical and size or nil,
    })
    assert(winnr ~= 0, "[bq] Failed to open window")
    state.winnr = winnr

    vim.w[winnr].bq_win = true

    require("bq.views.options").set_win_options()
    require("bq.views.keymaps").set_keymaps()

    state.current_section = initial_section

    winbar.set_action_keymaps()
    winbar.show_content(state.current_section)

    -- Clean up when window is closed directly by the user
    api.nvim_create_autocmd("WinClosed", {
        pattern = tostring(winnr),
        once = true,
        callback = function()
            if state.winnr then  -- not already handled by M.close()
                state.winnr = nil
                for _, bufnr in pairs(state.bufs) do
                    if util.is_buf_valid(bufnr) then
                        pcall(api.nvim_buf_delete, bufnr, { force = true })
                    end
                end
                state.bufs = {}
            end
        end,
    })
end

---@param opts {count: integer, wrap: boolean}
M.navigate = function(opts)
    local sections = setup.config.winbar.sections
    local current = state.current_section
    local idx = 1
    for i, v in ipairs(sections) do
        if v == current then
            idx = i
            break
        end
    end

    local new_idx = idx + (opts.count or 1)
    if opts.wrap then
        new_idx = ((new_idx - 1) % #sections) + 1
    else
        new_idx = math.max(1, math.min(#sections, new_idx))
    end

    require("bq.views").switch_to_view(sections[new_idx])
end

---@param view string
M.show_view = function(view)
    if not util.is_win_valid(state.winnr) then
        M.open()
    end
    require("bq.views").switch_to_view(view)
end

---@param sql string
M.run_query = function(sql)
    if not sql or sql:match("^%s*$") then
        vim.notify("[bq] No SQL to run", vim.log.levels.WARN)
        return
    end

    state.last_query = sql

    -- Open panel if not already open
    if not util.is_win_valid(state.winnr) then
        M.open()
    end

    -- Switch to results view and show loading indicator
    state.current_section = "results"
    winbar.refresh_winbar("results")
    util.set_lines(state.bufs["results"], 0, -1, false, { "  Running query…" })

    local start_ts = vim.uv.now()
    local project = state.project

    -- Record as pending in history
    local history_entry = {
        sql = sql,
        project = project,
        status = "running",
        ts = os.time(),
        elapsed_ms = nil,
    }
    table.insert(state.history, history_entry)

    require("bq.jobs.bq").run_query(sql, project, function(code, data, raw)
        local elapsed = vim.uv.now() - start_ts
        history_entry.elapsed_ms = elapsed

        if code ~= 0 then
            history_entry.status = "error"
            state.results_data = {}
            state.results_schema = {}
            state.stats_data = {
                status = "ERROR",
                elapsed_ms = elapsed,
            }
            local err_lines = { "  Query failed:", "" }
            for _, line in ipairs(vim.split(raw or "", "\n")) do
                table.insert(err_lines, "  " .. line)
            end
            util.set_lines(state.bufs["results"], 0, -1, false, err_lines)
            winbar.refresh_winbar("results")
            return
        end

        history_entry.status = "ok"

        local rows = data or {}
        state.results_data = rows
        state.stats_data = {
            status = "OK",
            total_rows = #rows,
            elapsed_ms = elapsed,
        }

        -- Extract column order from first row
        if #rows > 0 then
            local cols = {}
            for k in pairs(rows[1]) do
                table.insert(cols, k)
            end
            table.sort(cols)
            state.results_schema = cols
        else
            state.results_schema = {}
        end

        require("bq.views").switch_to_view(state.current_section or "results")
    end)
end

return M
