local state = require("bq.state")

local M = {}

local api = vim.api

local pane_keymaps = {
    results = {
        "## Results",
        "",
        "| Key    | Action                   |",
        "|--------|--------------------------|",
        "| `<CR>` | Preview focused row      |",
        "| `c`    | Preview focused cell     |",
        "| `C`    | Preview full column      |",
        "| `f`    | Add filter               |",
        "| `<BS>` | Remove last filter       |",
        "| `F`    | Clear all filters        |",
        "| `e`    | Export to CSV            |",
        "| `o`    | Open last exported CSV   |",
        "| `/ ?`  | Full-text search         |",
    },
    history = {
        "## History",
        "",
        "| Key    | Action                           |",
        "|--------|----------------------------------|",
        "| `<CR>` | Load cached results (or re-run)  |",
        "| `r`    | Force re-run against BigQuery    |",
        "| `p`    | Preview full SQL                 |",
        "| `n`    | Name / rename query              |",
    },
    schema = {
        "## Schema",
        "",
        "| Key    | Action                   |",
        "|--------|--------------------------|",
        "| `<CR>` | Drill into dataset/table |",
        "| `-`    | Go up one level          |",
    },
    stats = {},
    debug = {},
}

local function open_help_float(section)
    local global_lines = {
        "# bq Keymaps",
        "",
        "## Global",
        "",
        "| Key              | Action              |",
        "|------------------|---------------------|",
        "| `R/S/H/C/D`      | Switch view         |",
        "| `]v` / `[v`      | Navigate views      |",
        "| `gr`             | Re-run last query   |",
        "| `q`              | Close panel         |",
        "| `g?`             | This help           |",
        "",
    }

    local pane = pane_keymaps[section] or {}
    local lines = vim.list_extend(vim.deepcopy(global_lines), vim.deepcopy(pane))

    if #pane > 0 then table.insert(lines, "") end

    vim.list_extend(lines, {
        "## Commands",
        "",
        "| Command              | Description         |",
        "|----------------------|---------------------|",
        "| `:BQ open/close/toggle` | Panel control    |",
        "| `:BQ connect [project]` | Connect project  |",
        "| `:BQ run`            | Run selection/buffer|",
        "| `:BQ schema [dataset]`  | Browse schema    |",
        "| `:BQ view <name>`    | Switch view         |",
        "| `:BQ navigate <n>[!]`   | Navigate views   |",
    })

    -- Sizing: content-driven, capped at 60% width / 80% height
    local max_w = math.max(50, math.floor(vim.o.columns * 0.60))
    local content_w = 0
    for _, l in ipairs(lines) do content_w = math.max(content_w, #l) end
    local width = math.min(max_w, content_w + 4)

    local height = math.min(math.floor(vim.o.lines * 0.80), #lines + 2)
    height = math.max(height, 5)

    local float_buf = api.nvim_create_buf(false, true)
    api.nvim_buf_set_lines(float_buf, 0, -1, false, lines)
    vim.bo[float_buf].modifiable = false
    vim.bo[float_buf].filetype = "markdown"

    local title = " Keymaps [" .. section .. "] "
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
    vim.wo[win].wrap = false
    vim.wo[win].cursorline = true
    vim.wo[win].conceallevel = 2

    -- Close on q / <Esc>
    for _, key in ipairs({ "q", "<Esc>" }) do
        vim.keymap.set("n", key, function()
            pcall(api.nvim_win_close, win, true)
        end, { buffer = float_buf, nowait = true })
    end

    -- Cleanup buffer when window is closed
    api.nvim_create_autocmd("WinClosed", {
        pattern = tostring(win),
        once = true,
        callback = function()
            pcall(api.nvim_buf_delete, float_buf, { force = true })
        end,
    })
end

local function set_keymaps_for_buf(buf)
    local function map(lhs, rhs, desc)
        vim.keymap.set("n", lhs, rhs, { buffer = buf, nowait = true, desc = desc })
    end

    -- Navigate between views
    map("]v", function()
        require("bq").navigate({ count = 1, wrap = true })
    end, "Next bq section")

    map("[v", function()
        require("bq").navigate({ count = -1, wrap = true })
    end, "Previous bq section")

    -- Close panel
    map("q", function()
        require("bq").close()
    end, "Close bq")

    -- Re-run last query
    map("gr", function()
        if state.last_query then
            require("bq").run(state.last_query)
        else
            vim.notify("[bq] No previous query to re-run", vim.log.levels.WARN)
        end
    end, "Re-run last query")

    -- Help (context-aware: global keymaps + current pane's keymaps)
    map("g?", function()
        open_help_float(state.current_section or "results")
    end, "Show bq help")
end

M.set_keymaps = function()
    for _, buf in pairs(state.bufs) do
        set_keymaps_for_buf(buf)
    end
end

return M
