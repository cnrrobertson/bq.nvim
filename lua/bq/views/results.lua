local state = require("bq.state")
local util = require("bq.util")
local views = require("bq.views")
local globals = require("bq.globals")

local M = {}

local api = vim.api
local MAX_COL_WIDTH = 50

local function open_preview(row, cols)
    local lines = {}
    local max_key_len = 0
    for _, col in ipairs(cols) do
        if #col > max_key_len then max_key_len = #col end
    end

    for _, col in ipairs(cols) do
        local raw = row[col]
        local val = (raw == nil or raw == vim.NIL) and "NULL" or tostring(raw)
        local label = col .. string.rep(" ", max_key_len - #col) .. "  "
        -- split value on newlines, indent continuation lines
        local val_lines = vim.split(val, "\n", { plain = true })
        table.insert(lines, label .. val_lines[1])
        local indent = string.rep(" ", #label)
        for i = 2, #val_lines do
            table.insert(lines, indent .. val_lines[i])
        end
    end

    local width = math.min(math.max(40, max_key_len + 4 + 60), vim.o.columns - 6)
    local height = math.min(#lines, vim.o.lines - 6)

    local buf = api.nvim_create_buf(false, true)
    api.nvim_buf_set_lines(buf, 0, -1, false, lines)
    vim.bo[buf].modifiable = false

    local win = api.nvim_open_win(buf, true, {
        relative = "editor",
        width = width,
        height = height,
        row = math.floor((vim.o.lines - height) / 2),
        col = math.floor((vim.o.columns - width) / 2),
        style = "minimal",
        border = "rounded",
        title = " Row preview ",
        title_pos = "center",
    })
    vim.wo[win].wrap = true
    vim.wo[win].cursorline = true

    -- highlight keys
    local ns = globals.NAMESPACE
    for i, col in ipairs(cols) do
        -- find the line index for this col (first line of this col's block)
        local line_idx = 0
        for j = 1, i - 1 do
            local r = row[cols[j]]
            local v = (r == nil or r == vim.NIL) and "NULL" or tostring(r)
            line_idx = line_idx + #vim.split(v, "\n", { plain = true })
        end
        vim.hl.range(buf, ns, "BQHeader", { line_idx, 0 }, { line_idx, max_key_len })
    end

    -- close on q or <Esc>
    for _, key in ipairs({ "q", "<Esc>" }) do
        vim.keymap.set("n", key, function()
            pcall(api.nvim_win_close, win, true)
        end, { buffer = buf, nowait = true })
    end
end

---@param bufnr integer
M.show = function(bufnr)
    if not util.is_buf_valid(bufnr) or not util.is_win_valid(state.winnr) then
        return
    end

    local rows = state.results_data
    local cols = state.results_schema

    if views.cleanup_view(bufnr, #rows == 0 and #cols == 0, "  No results") then
        return
    end

    -- Compute column display widths (capped at MAX_COL_WIDTH)
    local widths = {}
    for _, col in ipairs(cols) do
        widths[col] = #col
    end
    for _, row in ipairs(rows) do
        for _, col in ipairs(cols) do
            local val = tostring(row[col] ~= nil and row[col] or "NULL"):gsub("[\n\r]", " ")
            local display_len = math.min(#val, MAX_COL_WIDTH)
            if display_len > widths[col] then
                widths[col] = display_len
            end
        end
    end

    -- Box drawing characters
    local sep_parts = {}
    local header_parts = {}
    for _, col in ipairs(cols) do
        local w = widths[col]
        table.insert(sep_parts, string.rep("─", w + 2))
        table.insert(header_parts, " " .. col .. string.rep(" ", w - #col + 1))
    end

    local lines = {}
    table.insert(lines, "┌" .. table.concat(sep_parts, "┬") .. "┐")
    table.insert(lines, "│" .. table.concat(header_parts, "│") .. "│")
    table.insert(lines, "├" .. table.concat(sep_parts, "┼") .. "┤")

    local ROW_OFFSET = 3  -- 0-based line index of first data row
    local null_positions = {}

    for _, row in ipairs(rows) do
        local row_parts = {}
        local col_offset = 1
        local line_idx = #lines
        for _, col in ipairs(cols) do
            local w = widths[col]
            local raw = row[col]
            local is_null = raw == nil or raw == vim.NIL
            local val = is_null and "NULL" or tostring(raw):gsub("[\n\r]", " ")
            local truncated = #val > w
            if truncated then
                val = val:sub(1, w - 1) .. "…"
            end
            local padded = " " .. val .. string.rep(" ", w - #val + 1)
            if is_null then
                table.insert(null_positions, { line_idx, col_offset + 1, col_offset + 1 + #val })
            end
            table.insert(row_parts, padded)
            col_offset = col_offset + #padded + 1
        end
        table.insert(lines, "│" .. table.concat(row_parts, "│") .. "│")
    end

    table.insert(lines, "└" .. table.concat(sep_parts, "┴") .. "┘")
    table.insert(lines, "")
    table.insert(lines, string.format("  %d row%s  (press <CR> on a row to preview full values)",
        #rows, #rows == 1 and "" or "s"))

    util.set_lines(bufnr, 0, -1, false, lines)

    local ns = globals.NAMESPACE

    vim.hl.range(bufnr, ns, "BQHeader", { 1, 0 }, { 1, #lines[2] })

    for _, pos in ipairs(null_positions) do
        vim.hl.range(bufnr, ns, "BQNullValue", { pos[1], pos[2] }, { pos[1], pos[3] })
    end

    for _, li in ipairs({ 0, 2, #lines - 4 }) do
        if lines[li + 1] then
            vim.hl.range(bufnr, ns, "BQBorderChar", { li, 0 }, { li, #lines[li + 1] })
        end
    end

    -- <CR> to preview the row under cursor
    vim.keymap.set("n", "<CR>", function()
        if not util.is_win_valid(state.winnr) then return end
        local cursor = api.nvim_win_get_cursor(state.winnr)
        local row_idx = cursor[1] - ROW_OFFSET  -- 1-based
        if row_idx < 1 or row_idx > #rows then return end
        open_preview(rows[row_idx], cols)
    end, { buffer = bufnr, nowait = true, desc = "Preview full row values" })
end

return M
