local state = require("bq.state")

local M = {}

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

    -- Help
    map("g?", function()
        local lines = {
            "bq keymaps:",
            "  R         Results view",
            "  S         Stats view",
            "  H         History view",
            "  C         Schema view",
            "  D         Debug view",
            "  ]v / [v   Navigate views",
            "  gr        Re-run last query",
            "  q         Close panel",
            "  <CR>      Preview row (Results) / action (History/Schema)",
            "  -         Go up (Schema)",
            "",
            "bq commands:",
            "  :BQ open / close / toggle",
            "  :BQ connect [project]",
            "  :BQ run  (or :'<,'>BQ run)",
            "  :BQ schema [dataset]",
            "  :BQ view <name>",
            "  :BQ navigate <n>[!]",
        }
        vim.notify(table.concat(lines, "\n"), vim.log.levels.INFO)
    end, "Show bq help")
end

M.set_keymaps = function()
    for _, buf in pairs(state.bufs) do
        set_keymaps_for_buf(buf)
    end
end

return M
