--- *bq* BigQuery client for Neovim
--- *Bq*
---
--- MIT License Copyright (c) 2025 Connor Robertson
---
--- ===========================================================================
---
--- Key features:
--- - Run BigQuery SQL queries from the current buffer or a visual selection.
--- - Browse results, stats, query history, and schema in a split panel.
--- - Navigate datasets → tables → fields with the built-in schema browser.
--- - Connect to any GCP project or fall back to the active `gcloud` project.
---
--- # Setup ~
---
--- Call |bq.setup| once in your Neovim config (lazy-load on the `:BQ` command
--- is fine — setup is optional if the defaults suit you):
---
--- >lua
---   require("bq").setup({
---     windows = { position = "below", size = 0.35 },
---     max_results = 500,
---   })
--- <
---
--- See |bq.config| for all available options.
---
--- # User Commands ~
---
--- All functionality is exposed through a single `:BQ` command with
--- subcommands. Optional arguments are marked with `?`.
---
---   Open the bq panel.
---   `:BQ open`
---
---   Close the bq panel.
---   `:BQ close`
---
---   Toggle the bq panel.
---   `:BQ toggle`
---
---   Connect to a GCP project (omit to use the active `gcloud` project).
---   `:BQ connect project?`
---
---   Run the entire current buffer as SQL (or a visual selection).
---   `:'<,'>BQ run`
---
---   Open the schema browser, optionally starting at a dataset.
---   `:BQ schema dataset?`
---
---   Switch to a named panel view.
---   `:BQ view name`
---
---   Navigate views forward/backward by count; add `!` to wrap around.
---   `:BQ navigate count?`
---
--- # Panel Views ~
---
--- The bq panel contains several views, switchable via the winbar tabs or
--- keymaps. Default keymaps (active inside the bq window):
---
---   *R*     Results view — tabular output with `<CR>` row preview
---   *S*     Stats view — elapsed time, row count, bytes billed, …
---   *H*     History view — past queries with status; `<CR>` to replay
---   *C*     Schema view — dataset/table/field browser
---   *D*     Debug view — raw bq CLI output log
---   *]v*    Next view
---   *[v*    Previous view
---   *gr*    Re-run last query
---   *q*     Close panel
---   *g?*    Show keymap help
---
--- # Highlight Groups ~
---
--- All highlight groups are prefixed with `BQ` and link to standard Neovim
--- groups by default:
---
---   *BQTab*         linked to |hl-TabLine|
---   *BQTabSelected* linked to |hl-TabLineSel|
---   *BQTabFill*     linked to |hl-TabLineFill|
---   *BQHeader*      linked to |hl-Title|
---   *BQStatKey*     linked to |hl-Identifier|
---   *BQHistoryOk*   linked to |hl-DiagnosticOk|
---   *BQHistoryErr*  linked to |hl-DiagnosticError|
---   *BQNullValue*   linked to |hl-Comment|
---   *BQLoading*     linked to |hl-Comment|
---   *BQMissingData* linked to |hl-DiagnosticVirtualTextWarn|
---   *BQBorderChar*  linked to |hl-Comment|

require("bq.highlight")
require("bq.autocmds")

local actions = require("bq.actions")
local state = require("bq.state")

local M = {}

--- Setup bq.nvim with optional user configuration.
--- Merges `user_config` on top of the defaults from |bq.config|.
---@param user_config? bq.Config
M.setup = function(user_config)
    require("bq.setup").setup(user_config)
end

--- Open the bq panel. Creates one buffer per configured section and opens
--- a split window according to `windows.position` and `windows.size`.
M.open = function()
    actions.open()
end

--- Close the bq panel and delete all associated section buffers.
M.close = function()
    actions.close()
end

--- Toggle the bq panel open or closed.
M.toggle = function()
    actions.toggle()
end

--- Connect to a GCP project.
--- When `project` is omitted the active `gcloud` project is used.
---@param project? string GCP project ID
M.connect = function(project)
    state.project = project
    local log = require("bq.log")
    if project then
        log.append("CONNECT project=" .. project)
        vim.notify("[bq] Connected to project: " .. project)
    else
        local setup = require("bq.setup")
        local stdout_lines = {}
        vim.fn.jobstart({ "gcloud", "config", "get-value", "project" }, {
            stdout_buffered = true,
            on_stdout = function(_, data)
                if data then
                    for _, line in ipairs(data) do
                        if line ~= "" then table.insert(stdout_lines, line) end
                    end
                end
            end,
            on_exit = function(_, code)
                vim.schedule(function()
                    if code == 0 and #stdout_lines > 0 then
                        log.append("CONNECT project=" .. stdout_lines[1] .. " (default)")
                    vim.notify("[bq] Using default project: " .. stdout_lines[1])
                    else
                        vim.notify("[bq] Using default project (from bq CLI config)")
                    end
                end)
            end,
        })
        _ = setup
    end
end

--- Run SQL against BigQuery.
--- When `sql` is omitted the entire current buffer is used as the query.
--- Opens the panel and switches to the Results view automatically.
---@param sql? string SQL query string
M.run = function(sql)
    if not sql then
        local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
        sql = table.concat(lines, "\n")
    end
    actions.run_query(sql)
end

--- Switch the panel to the named view.
--- Opens the panel first if it is not already visible.
---@param view string One of `"results"`, `"stats"`, `"history"`, `"schema"`, `"debug"`
M.show_view = function(view)
    actions.show_view(view)
end

--- Navigate between panel views by `opts.count` steps.
--- Wraps around when `opts.wrap` is `true`.
---@param opts {count: integer, wrap: boolean}
M.navigate = function(opts)
    actions.navigate(opts)
end

return M
