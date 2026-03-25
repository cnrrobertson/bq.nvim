local state = require("bq.state")
local util = require("bq.util")
local globals = require("bq.globals")
local bq = require("bq.jobs.bq")

local M = {}

local api = vim.api

-- Render a list of datasets
local function show_datasets(bufnr, datasets)
    if not util.is_buf_valid(bufnr) then return end

    local lines = { "  Datasets  (press <CR> to browse)", "" }
    local ds_names = {}

    if type(datasets) == "table" and #datasets > 0 then
        -- Compute max name width for alignment
        local max_name = 0
        local entries = {}
        for _, ds in ipairs(datasets) do
            local id = (ds.datasetReference and ds.datasetReference.datasetId)
                or (type(ds) == "string" and ds)
                or tostring(ds)
            local loc = (type(ds) == "table" and ds.location) or ""
            table.insert(entries, { id = id, loc = loc })
            if #id > max_name then max_name = #id end
        end

        for _, e in ipairs(entries) do
            table.insert(ds_names, e.id)
            local pad = string.rep(" ", max_name - #e.id)
            local loc_part = e.loc ~= "" and ("  " .. e.loc) or ""
            table.insert(lines, "  " .. e.id .. pad .. loc_part)
        end
    elseif type(datasets) == "table" then
        table.insert(lines, "  (no datasets found)")
    end

    util.set_lines(bufnr, 0, -1, false, lines)

    -- <CR> to drill into dataset
    vim.keymap.set("n", "<CR>", function()
        if not util.is_win_valid(state.winnr) then return end
        local cursor = api.nvim_win_get_cursor(state.winnr)
        local line_idx = cursor[1]
        -- datasets start at line 3 (0-indexed line 2)
        local ds_idx = line_idx - 2
        if ds_names[ds_idx] then
            state.schema_dataset = ds_names[ds_idx]
            state.schema_table = nil
            M.show(bufnr)
        end
    end, { buffer = bufnr, nowait = true, desc = "Browse dataset" })
end

-- Render a list of tables in a dataset
local function show_tables(bufnr, dataset, tables_data)
    if not util.is_buf_valid(bufnr) then return end

    local lines = {
        "  " .. dataset .. "  (press <CR> for schema, <BS> to go up)",
        "",
    }
    local table_names = {}

    if type(tables_data) == "table" and #tables_data > 0 then
        local max_id = 0
        local entries = {}
        for _, tbl in ipairs(tables_data) do
            local id = (tbl.tableReference and tbl.tableReference.tableId)
                or (type(tbl) == "string" and tbl)
                or tostring(tbl)
            local kind = tbl.type or "TABLE"
            local created = ""
            if tbl.creationTime then
                local ts = math.floor(tonumber(tbl.creationTime) / 1000)
                created = os.date("%Y-%m-%d", ts)
            end
            table.insert(entries, { id = id, kind = kind, created = created })
            if #id > max_id then max_id = #id end
        end

        for _, e in ipairs(entries) do
            table.insert(table_names, e.id)
            local created_part = e.created ~= "" and ("  " .. e.created) or ""
            table.insert(lines, string.format("  %-" .. max_id .. "s  %-20s%s", e.id, e.kind, created_part))
        end
    else
        table.insert(lines, "  (no tables found)")
    end

    util.set_lines(bufnr, 0, -1, false, lines)

    -- <CR> to show table schema
    vim.keymap.set("n", "<CR>", function()
        if not util.is_win_valid(state.winnr) then return end
        local cursor = api.nvim_win_get_cursor(state.winnr)
        local tbl_idx = cursor[1] - 2
        if table_names[tbl_idx] then
            state.schema_table = table_names[tbl_idx]
            M.show(bufnr)
        end
    end, { buffer = bufnr, nowait = true, desc = "Show table schema" })
end

-- Render a table's schema fields
local function show_table_schema(bufnr, dataset, table_name, schema_data)
    if not util.is_buf_valid(bufnr) then return end

    local lines = {
        "  " .. dataset .. "." .. table_name .. "  (<BS> to go up)",
        "",
    }

    local fields = schema_data and schema_data.schema and schema_data.schema.fields or {}

    if #fields > 0 then
        local max_name = 4   -- "name"
        local max_type = 4   -- "type"
        local max_mode = 4   -- "mode"
        for _, f in ipairs(fields) do
            if f.name and #f.name > max_name then max_name = #f.name end
            if f.type and #f.type > max_type then max_type = #f.type end
            if f.mode and #f.mode > max_mode then max_mode = #f.mode end
        end

        local fmt = "  %-" .. max_name .. "s  %-" .. max_type .. "s  %-" .. max_mode .. "s  %s"
        table.insert(lines, string.format(fmt, "name", "type", "mode", "description"))
        table.insert(lines, "  " .. string.rep("─", max_name + max_type + max_mode + #"description" + 8))

        for _, f in ipairs(fields) do
            table.insert(lines, string.format(fmt,
                f.name or "",
                f.type or "",
                f.mode or "",
                f.description or ""))
        end
    else
        table.insert(lines, "  (no fields found)")
    end

    -- Table metadata
    if schema_data then
        table.insert(lines, "")
        if schema_data.numRows then
            table.insert(lines, "  Rows:  " .. schema_data.numRows)
        end
        if schema_data.numBytes then
            local n = tonumber(schema_data.numBytes) or 0
            local size_str
            if n >= 1e9 then size_str = string.format("%.2f GB", n / 1e9)
            elseif n >= 1e6 then size_str = string.format("%.2f MB", n / 1e6)
            else size_str = string.format("%d B", n) end
            table.insert(lines, "  Size:  " .. size_str)
        end
        if schema_data.creationTime then
            local ts = math.floor(tonumber(schema_data.creationTime) / 1000)
            table.insert(lines, "  Created:  " .. os.date("%Y-%m-%d %H:%M:%S", ts))
        end
    end

    util.set_lines(bufnr, 0, -1, false, lines)

    -- Highlight header
    local ns = globals.NAMESPACE
    if lines[4] then
        vim.hl.range(bufnr, ns, "BQHeader", { 3, 0 }, { 3, #lines[4] })
    end
end

---@param bufnr integer
M.show = function(bufnr)
    if not util.is_buf_valid(bufnr) or not util.is_win_valid(state.winnr) then
        return
    end

    vim.keymap.set("n", "<bs>", function()
        if state.schema_table then
            state.schema_table = nil
            M.show(bufnr)
        elseif state.schema_dataset then
            state.schema_dataset = nil
            M.show(bufnr)
        end
    end, { buffer = bufnr, nowait = true, desc = "Go up in schema browser" })

    if state.schema_table and state.schema_dataset then
        -- Show table schema
        util.set_lines(bufnr, 0, -1, false, { "  Loading schema…" })
        local ref = state.schema_dataset .. "." .. state.schema_table
        bq.show(state.project, ref, function(code, data)
            vim.schedule(function()
                if not util.is_buf_valid(bufnr) then return end
                if code ~= 0 then
                    util.set_lines(bufnr, 0, -1, false, { "  Failed to load schema for " .. ref })
                    return
                end
                show_table_schema(bufnr, state.schema_dataset, state.schema_table, data)
            end)
        end)

    elseif state.schema_dataset then
        -- Show tables in dataset
        util.set_lines(bufnr, 0, -1, false, { "  Loading tables…" })
        bq.ls(state.project, state.schema_dataset, function(code, data)
            vim.schedule(function()
                if not util.is_buf_valid(bufnr) then return end
                if code ~= 0 then
                    util.set_lines(bufnr, 0, -1, false,
                        { "  Failed to list tables in " .. state.schema_dataset })
                    return
                end
                show_tables(bufnr, state.schema_dataset, data)
            end)
        end)

    else
        -- Show top-level datasets
        util.set_lines(bufnr, 0, -1, false, { "  Loading datasets…" })
        bq.ls(state.project, nil, function(code, data)
            vim.schedule(function()
                if not util.is_buf_valid(bufnr) then return end
                if code ~= 0 then
                    util.set_lines(bufnr, 0, -1, false, { "  Failed to list datasets" })
                    return
                end
                show_datasets(bufnr, data)
            end)
        end)
    end
end

return M
