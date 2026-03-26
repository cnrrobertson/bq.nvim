local state = require("bq.state")
local util = require("bq.util")
local views = require("bq.views")
local globals = require("bq.globals")
local setup = require("bq.setup")

local M = {}

local api = vim.api
local MAX_COL_WIDTH = 50

-- Resolve a dimension value: fractions < 1 are treated as a percentage of
-- `total` (e.g. 0.8 → 80% of editor columns/lines), integers are used as-is.
local function resolve_dim(val, total)
    return val < 1 and math.floor(val * total) or val
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

    -- Sep parts for border lines
    local sep_parts = {}
    for _, col in ipairs(cols) do
        table.insert(sep_parts, string.rep("─", widths[col] + 2))
    end

    -- Build buf_lines: data rows have first char of each cell value as real text.
    -- The header chrome (top border, column names, middle border) is rendered as
    -- virt_lines_above on line 0 so it cannot be navigated to.
    local ROW_OFFSET = 0
    local buf_lines = {}
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

    table.insert(buf_lines, "")  -- bottom border
    table.insert(buf_lines, "")  -- spacer
    table.insert(buf_lines, string.format(
        "  %d row%s  (press <CR> on a row to preview full values)",
        #rows, #rows == 1 and "" or "s"))
    util.set_lines(bufnr, 0, -1, false, buf_lines)

    -- All visual structure is rendered as inline virtual text
    local ns = globals.NAMESPACE

    local function place_border(line_idx, left, mid, right)
        api.nvim_buf_set_extmark(bufnr, ns, line_idx, 0, {
            virt_text = { { left .. table.concat(sep_parts, mid) .. right, "BQBorderChar" } },
            virt_text_pos = "inline",
        })
    end

    place_border(#rows, "└", "┴", "┘")

    -- Header chrome: top border, column names, middle border — rendered as
    -- virt_lines_above so the cursor cannot navigate to these lines.
    local header_line = { { "│", "BQBorderChar" } }
    for _, col in ipairs(cols) do
        local w = widths[col]
        table.insert(header_line, { " " .. col .. string.rep(" ", w - #col + 1), "BQHeader" })
        table.insert(header_line, { "│", "BQBorderChar" })
    end
    api.nvim_buf_set_extmark(bufnr, ns, 0, 0, {
        virt_lines = {
            { { "┌" .. table.concat(sep_parts, "┬") .. "┐", "BQBorderChar" } },
            header_line,
            { { "├" .. table.concat(sep_parts, "┼") .. "┤", "BQBorderChar" } },
        },
        virt_lines_above = true,
    })

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
end

return M
