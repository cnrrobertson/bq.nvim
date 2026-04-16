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

--- Extract structured fields from bq CLI stderr on query failure.
--- BQ stderr format: "BigQuery error in query operation: Error processing job
--- 'project:LOCATION.job_name': <message> [at LINE:COL]"
---@param raw string
---@return { job_ref: string?, project: string?, location: string?, job_name: string?, err_line: string?, err_col: string?, detail: string, console_url: string? }
local function parse_bq_error(raw)
    local job_ref    = raw:match("Error processing job '([^']+)'")
    local project, location, job_name
    if job_ref then
        project, location, job_name = job_ref:match("^([^:]+):([^%.]+)%.(.+)$")
    end
    local err_line, err_col = raw:match("at %[(%d+):(%d+)%]")

    -- bq --format=prettyjson writes JSON to stdout on failure; parse it if present
    -- Expected shape: { status: { errorResult: { message, reason }, jobReference: {...} } }
    local detail
    local ok, decoded = pcall(vim.fn.json_decode, raw)
    if ok and type(decoded) == "table" then
        local status = decoded.status
        if type(status) == "table" then
            local err_result = status.errorResult
            if type(err_result) == "table" and err_result.message then
                detail = err_result.message
            end
        end
        -- Also try to get job reference from JSON when the plain-text form was absent
        if not job_ref then
            local job_ref_tbl = decoded.jobReference
            if type(job_ref_tbl) == "table"
                and job_ref_tbl.projectId and job_ref_tbl.location and job_ref_tbl.jobId
            then
                project  = job_ref_tbl.projectId
                location = job_ref_tbl.location
                job_name = job_ref_tbl.jobId
                job_ref  = project .. ":" .. location .. "." .. job_name
            end
        end
    end

    -- Fallback: strip boilerplate from plain-text stderr
    if not detail then
        detail = raw:match("Error processing job '[^']+':%s*(.+)$") or raw
        detail = (detail:match("^([^\n]+)") or detail):match("^%s*(.-)%s*$")
    end
    if detail == "" then detail = "unknown error (check debug log)" end

    local console_url
    if project and location and job_name then
        console_url = ("https://console.cloud.google.com/bigquery"
            .. "?project=" .. project
            .. "&j=bq:" .. location .. ":" .. job_name
            .. "&page=queryresults")
    end
    return {
        job_ref     = job_ref,
        project     = project,
        location    = location,
        job_name    = job_name,
        err_line    = err_line,
        err_col     = err_col,
        detail      = detail,
        console_url = console_url,
    }
end


---@param sql string
M.run_query = function(sql)
    if not sql or sql:match("^%s*$") then
        vim.notify("[bq] No SQL to run", vim.log.levels.WARN)
        return
    end

    state.last_query = sql
    state.query_error = nil  -- clear any previous error

    -- Open panel if not already open
    if not util.is_win_valid(state.winnr) then
        M.open()
    end

    -- Switch to results view and show loading indicator
    state.current_section = "results"
    winbar.refresh_winbar("results")
    local results_buf = state.bufs["results"]
    api.nvim_buf_clear_namespace(results_buf, globals.NAMESPACE, 0, -1)
    util.set_lines(results_buf, 0, -1, false, { "  Running query…" })
    -- Physically swap the window buffer so the results pane is visible immediately
    -- (refresh_winbar only updates the tab label, not the displayed buffer)
    if util.is_win_valid(state.winnr) then
        local cur_buf = api.nvim_win_get_buf(state.winnr)
        if cur_buf ~= results_buf then
            vim.wo[state.winnr][0].winfixbuf = false
            api.nvim_win_set_buf(state.winnr, results_buf)
            vim.wo[state.winnr][0].winfixbuf = true
        end
    end

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
            require("bq.views.results").clear_filter()
            local info = parse_bq_error(raw or "")
            state.stats_data = {
                status     = "ERROR",
                elapsed_ms = elapsed,
                job_id     = info.job_ref,
            }
            -- Store error so results.show can re-render it on any tab switch
            state.query_error = { raw = raw or "", info = info, elapsed_ms = elapsed }
            api.nvim_buf_clear_namespace(state.bufs["results"], globals.NAMESPACE, 0, -1)
            require("bq.views.results").show(state.bufs["results"])
            winbar.refresh_winbar("results")
            vim.notify("[bq] " .. info.detail, vim.log.levels.ERROR)
            return
        end

        history_entry.status = "ok"

        local rows = data or {}
        state.results_data = rows
        require("bq.views.results").clear_filter()
        state.stats_data = {
            status = "OK",
            total_rows = #rows,
            elapsed_ms = elapsed,
        }

        -- Extract column order from first row; coerce keys to strings so that
        -- queries like `SELECT 1, 2` (which produce numeric keys) don't break
        -- the results renderer.
        if #rows > 0 then
            local cols = {}
            for k in pairs(rows[1]) do
                table.insert(cols, tostring(k))
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
