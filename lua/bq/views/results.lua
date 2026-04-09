local state = require("bq.state")
local util = require("bq.util")
local views = require("bq.views")
local globals = require("bq.globals")
local setup = require("bq.setup")

local M = {}

local api = vim.api
local MAX_COL_WIDTH = 50

-- Filter stack: each entry is a filter expression string.
-- Filters are applied in sequence (AND between them).
-- |  within a single filter provides OR between conditions.
local active_filters = {}

-- Path of the last successfully exported CSV file (nil until first export).
local last_export_path = nil

--- Render the error stored in state.query_error into the results buffer.
--- Mirrors the label-aligned style of the stats view.
---@param bufnr integer
local function show_error(bufnr)
    local e   = state.query_error
    local ns  = globals.NAMESPACE
    local lines = {}
    local marks = {}  -- { line_idx, col_s, col_e, hl_group }

    local function push(text, col_s, col_e, hl)
        local idx = #lines
        table.insert(lines, text)
        if hl then table.insert(marks, { idx, col_s, col_e, hl }) end
    end

    local title = "  Query failed"
    push(title, 0, #title, "BQHistoryErr")
    push("")

    local meta = {}
    if e.info.job_ref then
        table.insert(meta, { "Job",      e.info.job_ref })
    end
    if e.info.err_line and e.info.err_col then
        table.insert(meta, { "Location", "line " .. e.info.err_line .. ", col " .. e.info.err_col })
    end
    table.insert(meta, { "Elapsed", string.format("%d ms", e.elapsed_ms) })

    local key_w = 0
    for _, m in ipairs(meta) do key_w = math.max(key_w, #m[1]) end
    for _, m in ipairs(meta) do
        local pad  = string.rep(" ", key_w - #m[1])
        local line = "  " .. m[1] .. pad .. "  " .. m[2]
        push(line, 2, 2 + #m[1], "BQStatKey")
    end

    if e.info.console_url then
        push("")
        push("  Console:", 2, 10, "BQStatKey")
        local url_line = "    " .. e.info.console_url
        push(url_line, 4, #url_line, "Underlined")
    end

    push("")
    push("  Detail:", 2, 9, "BQStatKey")
    for _, l in ipairs(vim.split(e.raw or "", "\n")) do
        l = l:match("^%s*(.-)%s*$")
        if l ~= "" then push("    " .. l) end
    end

    util.set_lines(bufnr, 0, -1, false, lines)
    for _, m in ipairs(marks) do
        api.nvim_buf_set_extmark(bufnr, ns, m[1], m[2], {
            end_col  = m[3],
            hl_group = m[4],
        })
    end

    -- `o` opens the console URL in the browser (only when error has a job URL)
    if e.info.console_url then
        local url = e.info.console_url
        vim.keymap.set("n", "o", function()
            vim.ui.open(url)
        end, { buffer = bufnr, nowait = true, desc = "Open job in BigQuery console" })
    end
end

-- Resolve a dimension value: fractions < 1 are treated as a percentage of
-- `total` (e.g. 0.8 → 80% of editor columns/lines), integers are used as-is.
local function resolve_dim(val, total)
    return val < 1 and math.floor(val * total) or val
end

-- Return the 1-based column index under the cursor in the results buffer.
-- Each data line contains exactly one real character per column, so the
-- character position of the cursor maps directly to a column index.
-- Returns nil when the cursor is not on a data row or a valid column.
local function get_col_idx(bufnr, winnr, num_cols, ROW_OFFSET)
    local cursor = api.nvim_win_get_cursor(winnr)
    local row_idx = cursor[1] - ROW_OFFSET
    if row_idx < 1 then return nil, nil end
    local line = api.nvim_buf_get_lines(bufnr, cursor[1] - 1, cursor[1], false)[1] or ""
    -- charidx returns the 0-based character index at the given byte offset,
    -- correctly handling multi-byte characters.
    local char_idx = vim.fn.charidx(line, cursor[2])
    local col_idx = char_idx + 1
    if col_idx < 1 or col_idx > num_cols then return nil, nil end
    return row_idx, col_idx
end

local function open_preview(row, cols)
    local lines = {}
    local max_key_len = 0
    for _, col in ipairs(cols) do
        if #col > max_key_len then max_key_len = #col end
    end

    -- Build lines (values only) and record each col's start line + line count
    local col_info = {}
    for _, col in ipairs(cols) do
        local raw = row[col]
        local val = (raw == nil or raw == vim.NIL) and "NULL" or tostring(raw)
        local val_lines = vim.split(val, "\n", { plain = true })
        table.insert(col_info, { col = col, line_idx = #lines, count = #val_lines })
        table.insert(lines, val_lines[1])
        for i = 2, #val_lines do
            table.insert(lines, val_lines[i])
        end
    end

    local cfg = setup.config.preview
    local max_w = resolve_dim(cfg.max_width, vim.o.columns)
    local max_h = resolve_dim(cfg.max_height, vim.o.lines)
    local width  = math.max(40, math.min(max_w, vim.o.columns - 6))
    local height = math.max(5,  math.min(#lines, max_h, vim.o.lines - 6))

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

    -- Column names as inline virtual text; values are the real buffer text.
    local ns = globals.NAMESPACE
    local indent = string.rep(" ", max_key_len + 2)

    for _, info in ipairs(col_info) do
        local label = info.col .. string.rep(" ", max_key_len - #info.col) .. "  "
        -- Label prepended as virtual text on the first value line
        api.nvim_buf_set_extmark(buf, ns, info.line_idx, 0, {
            virt_text     = { { label, "BQHeader" } },
            virt_text_pos = "inline",
            right_gravity = false,
        })
        -- Matching indent on continuation lines so values stay aligned
        for j = 1, info.count - 1 do
            api.nvim_buf_set_extmark(buf, ns, info.line_idx + j, 0, {
                virt_text     = { { indent, "" } },
                virt_text_pos = "inline",
                right_gravity = false,
            })
        end
    end

    -- close on q or <Esc>
    for _, key in ipairs({ "q", "<Esc>" }) do
        vim.keymap.set("n", key, function()
            pcall(api.nvim_win_close, win, true)
        end, { buffer = buf, nowait = true })
    end
end

-- Opens a floating window showing the full untruncated value of a single cell.
local function open_cell_preview(col_name, value)
    local raw = (value == nil or value == vim.NIL) and "NULL" or tostring(value)
    local val_lines = vim.split(raw:gsub("\r", ""), "\n", { plain = true })

    local cfg = setup.config.preview
    local max_w = resolve_dim(cfg.max_width, vim.o.columns)
    local max_h = resolve_dim(cfg.max_height, vim.o.lines)
    local width  = math.max(40, math.min(max_w, vim.o.columns - 6))
    local height = math.max(3,  math.min(#val_lines, max_h, vim.o.lines - 6))

    local buf = api.nvim_create_buf(false, true)
    api.nvim_buf_set_lines(buf, 0, -1, false, val_lines)
    vim.bo[buf].modifiable = false

    local win = api.nvim_open_win(buf, true, {
        relative  = "editor",
        width     = width,
        height    = height,
        row       = math.floor((vim.o.lines - height) / 2),
        col       = math.floor((vim.o.columns - width) / 2),
        style     = "minimal",
        border    = "rounded",
        title     = " Cell: " .. col_name .. " ",
        title_pos = "center",
    })
    vim.wo[win].wrap       = true
    vim.wo[win].cursorline = true

    local is_null = value == nil or value == vim.NIL
    if is_null then
        api.nvim_buf_set_extmark(buf, globals.NAMESPACE, 0, 0, {
            end_col  = #val_lines[1],
            hl_group = "BQNullValue",
        })
    end

    for _, key in ipairs({ "q", "<Esc>" }) do
        vim.keymap.set("n", key, function()
            pcall(api.nvim_win_close, win, true)
        end, { buffer = buf, nowait = true })
    end
end

-- Opens a floating window with all values for a single column across every row.
local function open_column_preview(rows, col_name)
    if #rows == 0 then return end

    local ns = globals.NAMESPACE
    -- Width of the row-number gutter
    local gutter = #tostring(#rows) + 2  -- "N  "
    local buf_lines = {}
    local hl_marks  = {}  -- { line_idx, col_s, col_e, hl_group }

    for i, row in ipairs(rows) do
        local raw     = row[col_name]
        local is_null = raw == nil or raw == vim.NIL
        local val_str = is_null and "NULL" or tostring(raw):gsub("\r", "")
        local val_lines = vim.split(val_str, "\n", { plain = true })

        local num_str = tostring(i)
        local pad     = string.rep(" ", gutter - #num_str - 1)
        local indent  = string.rep(" ", gutter)

        -- First line: "N  value"
        local first_line = num_str .. pad .. " " .. val_lines[1]
        if is_null then
            table.insert(hl_marks, { #buf_lines, gutter, gutter + #val_lines[1], "BQNullValue" })
        end
        table.insert(buf_lines, first_line)

        -- Continuation lines for multi-line values
        for li = 2, #val_lines do
            table.insert(buf_lines, indent .. val_lines[li])
        end
    end

    local cfg    = setup.config.preview
    local max_w  = resolve_dim(cfg.max_width, vim.o.columns)
    local max_h  = resolve_dim(cfg.max_height, vim.o.lines)
    local width  = math.max(40, math.min(max_w, vim.o.columns - 4))
    local height = math.max(5,  math.min(#buf_lines, max_h, vim.o.lines - 4))

    local buf = api.nvim_create_buf(false, true)
    api.nvim_buf_set_lines(buf, 0, -1, false, buf_lines)
    vim.bo[buf].modifiable = false

    local win = api.nvim_open_win(buf, true, {
        relative  = "editor",
        width     = width,
        height    = height,
        row       = math.floor((vim.o.lines - height) / 2),
        col       = math.floor((vim.o.columns - width) / 2),
        style     = "minimal",
        border    = "rounded",
        title     = " Column: " .. col_name .. " (" .. #rows .. " rows) ",
        title_pos = "center",
    })
    vim.wo[win].wrap       = false
    vim.wo[win].cursorline = true

    for _, m in ipairs(hl_marks) do
        api.nvim_buf_set_extmark(buf, ns, m[1], m[2], {
            end_col  = m[3],
            hl_group = m[4],
        })
    end

    for _, key in ipairs({ "q", "<Esc>" }) do
        vim.keymap.set("n", key, function()
            pcall(api.nvim_win_close, win, true)
        end, { buffer = buf, nowait = true })
    end
end

-- Opens a floating window with all rows rendered as full plain text (no
-- truncation) so that native / and ? search work across the entire result set.
-- `display_cols` is an optional subset of cols to show; defaults to all cols.
local function open_search_window(rows, cols, display_cols)
    if #rows == 0 then return end
    display_cols = display_cols or cols

    local ns = globals.NAMESPACE
    local max_key_len = 0
    for _, col in ipairs(display_cols) do
        if #col > max_key_len then max_key_len = #col end
    end

    local divider_width = math.max(40, max_key_len + 30)
    local buf_lines = {}
    -- hl_marks: { line_idx (0-based), byte_start, byte_end, hl_group }
    local hl_marks = {}

    for i, row in ipairs(rows) do
        -- Row divider
        local divider = string.rep("─", divider_width)
        local divider_line = " Row " .. i .. " " .. divider
        table.insert(hl_marks, { #buf_lines, 0, #divider_line, "BQBorderChar" })
        table.insert(buf_lines, divider_line)

        -- One line per field; multi-line values span additional indented lines
        for _, col in ipairs(display_cols) do
            local raw = row[col]
            local is_null = raw == nil or raw == vim.NIL
            local val_str = is_null and "NULL" or tostring(raw):gsub("\r", "")
            local val_lines = vim.split(val_str, "\n", { plain = true })
            local pad = string.rep(" ", max_key_len - #col + 2)
            local indent = string.rep(" ", 2 + #col + #pad)
            local key_end = 2 + #col
            local val_start = key_end + #pad

            -- First line: "  fieldname    value"
            table.insert(hl_marks, { #buf_lines, 2, key_end, "BQHeader" })
            if is_null then
                table.insert(hl_marks, { #buf_lines, val_start, val_start + #val_lines[1], "BQNullValue" })
            end
            table.insert(buf_lines, "  " .. col .. pad .. val_lines[1])

            -- Continuation lines (if value contained newlines)
            for li = 2, #val_lines do
                table.insert(buf_lines, indent .. val_lines[li])
            end
        end

        -- Blank line between rows (except after the last)
        if i < #rows then
            table.insert(buf_lines, "")
        end
    end

    local cfg = setup.config.preview
    local max_w = resolve_dim(cfg.max_width, vim.o.columns)
    local max_h = resolve_dim(cfg.max_height, vim.o.lines)
    local width  = math.max(60, math.min(max_w, vim.o.columns - 4))
    local height = math.max(10, math.min(max_h, vim.o.lines - 4))

    local buf = api.nvim_create_buf(false, true)
    api.nvim_buf_set_lines(buf, 0, -1, false, buf_lines)
    vim.bo[buf].modifiable = false

    local win = api.nvim_open_win(buf, true, {
        relative  = "editor",
        width     = width,
        height    = height,
        row       = math.floor((vim.o.lines - height) / 2),
        col       = math.floor((vim.o.columns - width) / 2),
        style     = "minimal",
        border    = "rounded",
        title     = (#display_cols < #cols)
            and " Search results (" .. #rows .. " rows · cols: " .. table.concat(display_cols, ", ") .. ") "
            or  " Search results (" .. #rows .. " rows) ",
        title_pos = "center",
    })
    vim.wo[win].wrap      = false
    vim.wo[win].cursorline = true

    -- Apply highlights
    for _, m in ipairs(hl_marks) do
        api.nvim_buf_set_extmark(buf, ns, m[1], m[2], {
            end_col  = m[3],
            hl_group = m[4],
        })
    end

    -- q / <Esc> close the window
    for _, key in ipairs({ "q", "<Esc>" }) do
        vim.keymap.set("n", key, function()
            pcall(api.nvim_win_close, win, true)
        end, { buffer = buf, nowait = true })
    end
end

-- Write `rows` as a CSV file to `path`.
-- Values are RFC-4180 escaped: wrapped in quotes when they contain a comma,
-- double-quote, or newline; embedded double-quotes are doubled.
-- NULL / nil values are written as empty fields.
-- Returns true on success, or nil + error string on failure.
local function write_csv(rows, cols, path)
    local f, err = io.open(path, "w")
    if not f then return nil, err end

    local function escape(v)
        if v == nil or v == vim.NIL then return "" end
        local s = tostring(v)
        if s:find('[,"\n\r]') then
            return '"' .. s:gsub('"', '""') .. '"'
        end
        return s
    end

    -- Header row
    local header = {}
    for _, col in ipairs(cols) do table.insert(header, escape(col)) end
    f:write(table.concat(header, ",") .. "\n")

    -- Data rows
    for _, row in ipairs(rows) do
        local fields = {}
        for _, col in ipairs(cols) do table.insert(fields, escape(row[col])) end
        f:write(table.concat(fields, ",") .. "\n")
    end

    f:close()
    return true
end

-- Parse one filter expression into a list of OR conditions.
-- Supports: bare pattern, col=pat, col!=pat, and | to separate OR terms.
-- Returns { conditions = [{col, op, pat}, ...] }
local function parse_filter(input)
    local parts = input:find("|", 1, true)
        and vim.split(input, "|", { plain = true })
        or  { input }
    local conditions = {}
    for _, part in ipairs(parts) do
        part = vim.trim(part)
        if part ~= "" then
            -- Lua patterns don't support | alternation, so try != then = separately
            local col, pat = part:match("^([%w_]+)%s*!=%s*(.+)$")
            local op = "!="
            if not col then
                col, pat = part:match("^([%w_]+)%s*=%s*(.+)$")
                op = "="
            end
            if col then
                -- Strip surrounding quotes from the pattern value
                pat = pat:match("^'(.*)'$") or pat:match('^"(.*)"$') or pat
                table.insert(conditions, { col = col, op = op, pat = vim.trim(pat) })
            else
                table.insert(conditions, { col = nil, op = "=", pat = part })
            end
        end
    end
    return { conditions = conditions }
end

-- Return true if `row` matches the parsed filter (OR across conditions).
local function row_matches(row, cols, filter)
    local function cell_matches(v, pat)
        local s = (v == nil or v == vim.NIL) and "NULL" or tostring(v)
        local ok, m = pcall(string.find, s:lower(), pat:lower())
        return ok and m ~= nil
    end
    local function cond_matches(cond)
        if cond.col then
            local m = cell_matches(row[cond.col], cond.pat)
            if cond.op == "=" then return m else return not m end
        end
        for _, col in ipairs(cols) do
            if cell_matches(row[col], cond.pat) then return true end
        end
        return false
    end
    for _, cond in ipairs(filter.conditions) do
        if cond_matches(cond) then return true end
    end
    return false
end

---@param bufnr integer
M.show = function(bufnr)
    if not util.is_buf_valid(bufnr) or not util.is_win_valid(state.winnr) then
        return
    end

    -- Re-render query error (persists across tab switches)
    if state.query_error then
        vim.wo[state.winnr][0].cursorlineopt = "number"
        show_error(bufnr)
        return
    end

    -- Remove the error-only `o` keymap when showing normal results
    pcall(vim.keymap.del, "n", "o", { buffer = bufnr })

    -- Clear all extmarks before re-rendering to prevent accumulation when
    -- M.show is called directly (e.g. from filter keymaps) rather than via
    -- switch_to_view (which already clears before calling show).
    api.nvim_buf_clear_namespace(bufnr, globals.NAMESPACE, 0, -1)

    local all_rows = state.results_data
    local cols = state.results_schema

    -- Apply each stacked filter in sequence (AND between filters, OR within each)
    local rows = all_rows
    for _, filter_str in ipairs(active_filters) do
        local filtered = {}
        local f = parse_filter(filter_str)
        for _, row in ipairs(rows) do
            if row_matches(row, cols, f) then table.insert(filtered, row) end
        end
        rows = filtered
    end

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

    -- Sep parts for border lines
    local sep_parts = {}
    for _, col in ipairs(cols) do
        table.insert(sep_parts, string.rep("─", widths[col] + 2))
    end

    -- Layout:
    --   line 0        hint text (real, always visible)
    --   line 1        header: first char of each col name (real) + inline virt_text
    --                   virt_lines_above → top border ┌─┐  (non-navigable)
    --                   virt_lines after → mid border ├─┤  (non-navigable)
    --   lines 2..2+N-1  data rows (real first chars + inline virt_text)
    --                   last data row gets virt_lines after → bot border └─┘ (non-navigable)
    --   line 2+N      spacer
    local ROW_OFFSET = 2

    local hint_str
    local base_keys = "<CR> row · c cell · C col · f filter · e export · o open · / search"
    if #active_filters == 0 then
        hint_str = string.format(
            "  %d row%s  (%s)",
            #rows, #rows == 1 and "" or "s", base_keys)
    else
        local tags
        if #active_filters <= 2 then
            local t = {}
            for _, fs in ipairs(active_filters) do table.insert(t, "[" .. fs .. "]") end
            tags = table.concat(t, "")
        else
            tags = "[" .. #active_filters .. " filters]"
        end
        hint_str = string.format(
            "  %d/%d rows  %s  (<BS> undo · F clear · %s)",
            #rows, #all_rows, tags, base_keys)
    end

    -- Build header cells (same first-char pattern as data rows)
    local hdr_real_chars = {}
    local hdr_cells      = {}
    for _, col in ipairs(cols) do
        local w          = widths[col]
        local first_char = #col > 0 and vim.fn.strcharpart(col, 0, 1) or " "
        local rest       = vim.fn.strcharpart(col, 1)
        local trail      = string.rep(" ", w - #col + 1)
        table.insert(hdr_real_chars, first_char)
        table.insert(hdr_cells, { first_char = first_char, rest = rest, trail = trail })
    end

    local buf_lines      = { hint_str, table.concat(hdr_real_chars) }
    local row_cells_list = {}

    for _, row in ipairs(rows) do
        local real_chars = {}
        local cells = {}
        for _, col in ipairs(cols) do
            local w = widths[col]
            local raw = row[col]
            local is_null = raw == nil or raw == vim.NIL
            local val = is_null and "NULL" or tostring(raw):gsub("[\n\r]", " ")
            if #val > w then val = val:sub(1, w - 1) .. "…" end
            local first_char = #val > 0 and vim.fn.strcharpart(val, 0, 1) or " "
            local rest = vim.fn.strcharpart(val, 1)
            local trail = string.rep(" ", w - #val + 1)
            table.insert(real_chars, first_char)
            table.insert(cells, { first_char = first_char, rest = rest, trail = trail, is_null = is_null })
        end
        table.insert(buf_lines, table.concat(real_chars))
        table.insert(row_cells_list, cells)
    end

    table.insert(buf_lines, "")  -- spacer after bottom border
    util.set_lines(bufnr, 0, -1, false, buf_lines)

    local ns = globals.NAMESPACE

    -- Hint line: style with Comment
    api.nvim_buf_set_extmark(bufnr, ns, 0, 0, {
        end_row = 0, end_col = #hint_str, hl_group = "Comment",
    })

    local top_border = "┌" .. table.concat(sep_parts, "┬") .. "┐"
    local mid_border = "├" .. table.concat(sep_parts, "┼") .. "┤"
    local bot_border = "└" .. table.concat(sep_parts, "┴") .. "┘"

    -- Top border: virt_lines_above on header line → cursor cannot navigate to it
    api.nvim_buf_set_extmark(bufnr, ns, 1, 0, {
        virt_lines       = { { { top_border, "BQBorderChar" } } },
        virt_lines_above = true,
    })
    -- Mid border: virt_lines after header line → cursor cannot navigate to it
    api.nvim_buf_set_extmark(bufnr, ns, 1, 0, {
        virt_lines = { { { mid_border, "BQBorderChar" } } },
    })
    -- Bottom border: virt_lines after last data row → cursor cannot navigate to it
    api.nvim_buf_set_extmark(bufnr, ns, ROW_OFFSET + #rows - 1, 0, {
        virt_lines = { { { bot_border, "BQBorderChar" } } },
    })

    -- Header row: same virtual-text structure as data rows; first char already
    -- written as real text above. Highlight it with BQHeader.
    api.nvim_buf_set_extmark(bufnr, ns, 1, 0, {
        virt_text     = { { "│", "BQBorderChar" }, { " ", "" } },
        virt_text_pos = "inline",
        right_gravity = false,
    })
    local hbyte_off = 0
    for k, cell in ipairs(hdr_cells) do
        local after = hbyte_off + #cell.first_char
        -- highlight the real first char of the column name
        api.nvim_buf_set_extmark(bufnr, ns, 1, hbyte_off, {
            end_col  = after,
            hl_group = "BQHeader",
        })
        local vt = {}
        if #cell.rest > 0 then
            table.insert(vt, { cell.rest, "BQHeader" })
        end
        table.insert(vt, { cell.trail, "" })
        table.insert(vt, { "│", "BQBorderChar" })
        if k < #hdr_cells then
            table.insert(vt, { " ", "" })
        end
        api.nvim_buf_set_extmark(bufnr, ns, 1, after, {
            virt_text     = vt,
            virt_text_pos = "inline",
        })
        hbyte_off = after
    end

    -- Data rows: first char of each value is real text for cursor navigation;
    -- all surrounding structure (borders, padding, rest of value) is virtual.
    for i, cells in ipairs(row_cells_list) do
        local line_idx = ROW_OFFSET + i - 1
        local n = #cells
        local byte_off = 0

        -- Prepend "│ " before the first real char
        api.nvim_buf_set_extmark(bufnr, ns, line_idx, 0, {
            virt_text = { { "│", "BQBorderChar" }, { " ", "" } },
            virt_text_pos = "inline",
            right_gravity = false,
        })

        for k, cell in ipairs(cells) do
            local after = byte_off + #cell.first_char

            -- Virtual text after this cell's real char:
            -- rest of value, trailing padding, delimiter, leading space for next cell
            local vt = {}
            if #cell.rest > 0 then
                table.insert(vt, { cell.rest, cell.is_null and "BQNullValue" or "" })
            end
            table.insert(vt, { cell.trail, "" })
            table.insert(vt, { "│", "BQBorderChar" })
            if k < n then
                table.insert(vt, { " ", "" })
            end
            api.nvim_buf_set_extmark(bufnr, ns, line_idx, after, {
                virt_text = vt,
                virt_text_pos = "inline",
            })

            -- Highlight the real first char of NULL cells
            if cell.is_null then
                api.nvim_buf_set_extmark(bufnr, ns, line_idx, byte_off, {
                    end_col = after,
                    hl_group = "BQNullValue",
                })
            end

            byte_off = after
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

    -- c: preview the single cell under cursor (full untruncated value)
    vim.keymap.set("n", "c", function()
        if not util.is_win_valid(state.winnr) then return end
        local row_idx, col_idx = get_col_idx(bufnr, state.winnr, #cols, ROW_OFFSET)
        if not row_idx or row_idx > #rows then return end
        local col_name = cols[col_idx]
        open_cell_preview(col_name, rows[row_idx][col_name])
    end, { buffer = bufnr, nowait = true, desc = "Preview cell value" })

    -- C: preview all values in the column under cursor
    vim.keymap.set("n", "C", function()
        if not util.is_win_valid(state.winnr) then return end
        local _, col_idx = get_col_idx(bufnr, state.winnr, #cols, ROW_OFFSET)
        if not col_idx then return end
        open_column_preview(rows, cols[col_idx])
    end, { buffer = bufnr, nowait = true, desc = "Preview column values" })

    -- f: push a new filter onto the stack; re-renders with narrowed rows
    vim.keymap.set("n", "f", function()
        vim.ui.input({
            prompt = "Add filter (e.g. foo · status=ok · name!=NULL · a|b): ",
        }, function(input)
            if input == nil or input == "" then return end
            table.insert(active_filters, input)
            M.show(bufnr)
        end)
    end, { buffer = bufnr, nowait = true, desc = "Add filter" })

    -- F: clear all filters and re-render
    vim.keymap.set("n", "F", function()
        active_filters = {}
        M.show(bufnr)
    end, { buffer = bufnr, nowait = true, desc = "Clear all filters" })

    -- e: export currently displayed rows (respects active filters) to CSV
    vim.keymap.set("n", "e", function()
        local cfg_export = setup.config.export
        local fname   = os.date(cfg_export.name)
        local default = vim.fn.expand(cfg_export.dir) .. "/" .. fname
        vim.ui.input({ prompt = "Export CSV to: ", default = default }, function(path)
            if path == nil or path == "" then return end
            local ok, err = write_csv(rows, cols, path)
            if ok then
                last_export_path = path
                vim.notify(string.format("[bq] Exported %d row%s to %s",
                    #rows, #rows == 1 and "" or "s", path), vim.log.levels.INFO)
                M.show(bufnr)
            else
                vim.notify("[bq] Export failed: " .. (err or "unknown error"), vim.log.levels.ERROR)
            end
        end)
    end, { buffer = bufnr, nowait = true, desc = "Export results to CSV" })

    -- o: open the last exported CSV (auto-exports to /tmp/ if none yet)
    vim.keymap.set("n", "o", function()
        local function do_open(path)
            last_export_path = path
            vim.ui.open(path)
        end
        if last_export_path then
            do_open(last_export_path)
        else
            local fname = os.date("bq-export-%Y%m%d-%H%M%S.csv")
            local path  = "/tmp/" .. fname
            local ok, err = write_csv(rows, cols, path)
            if ok then
                vim.notify("[bq] Quick-exported to " .. path, vim.log.levels.INFO)
                do_open(path)
            else
                vim.notify("[bq] Export failed: " .. (err or "unknown error"), vim.log.levels.ERROR)
            end
        end
    end, { buffer = bufnr, nowait = true, desc = "Open last exported CSV" })

    -- <BS>: pop the last filter off the stack and re-render
    vim.keymap.set("n", "<BS>", function()
        if #active_filters > 0 then
            table.remove(active_filters)
            M.show(bufnr)
        end
    end, { buffer = bufnr, nowait = true, desc = "Remove last filter" })

    -- Visual <CR>: dispatches on visual mode type
    --   V (line)   → preview the selected rows
    --   <C-v> (block) → preview the selected columns across all rows
    vim.keymap.set("x", "<CR>", function()
        local mode = vim.fn.mode()
        local esc  = api.nvim_replace_termcodes("<Esc>", true, false, true)

        if mode == "V" then
            -- Visual-line: collect selected rows
            local s = math.min(vim.fn.line("v"), vim.fn.line("."))
            local e = math.max(vim.fn.line("v"), vim.fn.line("."))
            local sel = {}
            for ln = s, e do
                local ri = ln - ROW_OFFSET
                if ri >= 1 and ri <= #rows then
                    table.insert(sel, rows[ri])
                end
            end
            api.nvim_feedkeys(esc, "n", false)
            if #sel > 0 then open_search_window(sel, cols) end

        elseif mode == "\22" then
            -- Visual-block: map selected byte columns → column indices via header
            local start_col = math.min(vim.fn.col("v"), vim.fn.col(".")) - 1  -- 0-based byte
            local end_col   = math.max(vim.fn.col("v"), vim.fn.col(".")) - 1
            local hdr = api.nvim_buf_get_lines(bufnr, 1, 2, false)[1] or ""
            local c1  = math.max(1, math.min(vim.fn.charidx(hdr, start_col) + 1, #cols))
            local c2  = math.max(1, math.min(vim.fn.charidx(hdr, end_col)   + 1, #cols))
            if c1 > c2 then c1, c2 = c2, c1 end
            local sel_cols = {}
            for ci = c1, c2 do table.insert(sel_cols, cols[ci]) end
            api.nvim_feedkeys(esc, "n", false)
            if #sel_cols > 0 then open_search_window(rows, cols, sel_cols) end
        end
    end, { buffer = bufnr, nowait = true, desc = "Preview selected rows/columns" })

    -- / and ? open the full-text search window (all rows, no truncation)
    -- then immediately feed the key so the user lands in the search prompt
    for _, key in ipairs({ "/", "?" }) do
        vim.keymap.set("n", key, function()
            open_search_window(rows, cols)
            vim.api.nvim_feedkeys(key, "t", false)
        end, { buffer = bufnr, nowait = true, desc = "Search all rows" })
    end
end

-- Called by actions.lua when new query results arrive to reset the filter stack.
M.clear_filter = function()
    active_filters = {}
end

-- Allow external callers (including tests) to push a filter programmatically.
M.push_filter = function(str)
    table.insert(active_filters, str)
end

-- Test-only access to private helpers (not part of the public API).
M._test = {
    parse_filter = parse_filter,
    row_matches  = row_matches,
    write_csv    = write_csv,
}

return M
