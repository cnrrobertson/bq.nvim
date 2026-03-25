if vim.g.loaded_bq then return end
vim.g.loaded_bq = true

local api = vim.api

local subcommands = {
    open = {
        impl = function(_args, _opts)
            require("bq").open()
        end,
    },
    close = {
        impl = function(_args, _opts)
            require("bq").close()
        end,
    },
    toggle = {
        impl = function(_args, _opts)
            require("bq").toggle()
        end,
    },
    connect = {
        impl = function(args, _opts)
            require("bq").connect(args[1])
        end,
        complete = function(arg_lead)
            return require("bq.complete").complete_projects(arg_lead)
        end,
    },
    run = {
        impl = function(_args, opts)
            local sql
            if opts.range > 0 then
                local lines = api.nvim_buf_get_lines(0, opts.line1 - 1, opts.line2, false)
                sql = table.concat(lines, "\n")
            end
            require("bq").run(sql)
        end,
        range = true,
    },
    schema = {
        impl = function(args, _opts)
            local state = require("bq.state")
            local dataset = args[1]
            if dataset and dataset ~= "" then
                state.schema_dataset = dataset
                state.schema_table = nil
            else
                state.schema_dataset = nil
                state.schema_table = nil
            end
            require("bq").show_view("schema")
        end,
        complete = function(arg_lead)
            return require("bq.complete").complete_datasets(arg_lead)
        end,
    },
    view = {
        impl = function(args, _opts)
            local v = args[1]
            if not v or v == "" then
                vim.notify("[bq] Usage: BQ view <name>", vim.log.levels.WARN)
                return
            end
            require("bq").show_view(v)
        end,
        complete = function(arg_lead)
            return require("bq.complete").complete_views(arg_lead)
        end,
    },
    navigate = {
        impl = function(args, opts)
            local count = tonumber(args[1]) or 1
            require("bq").navigate({ count = count, wrap = opts.bang })
        end,
        bang = true,
    },
}

local function complete(arg_lead, cmdline, _cursor_pos)
    -- Complete subcommand names
    if cmdline:match("^BQ%s+%S*$") then
        return vim.iter(vim.tbl_keys(subcommands))
            :filter(function(k) return k:find(arg_lead, 1, true) == 1 end)
            :totable()
    end
    -- Complete subcommand arguments
    local subcmd_key = cmdline:match("^BQ%s+(%S+)%s+")
    if subcmd_key and subcommands[subcmd_key] and subcommands[subcmd_key].complete then
        return subcommands[subcmd_key].complete(arg_lead)
    end
    return {}
end

local function dispatch(opts)
    local fargs = opts.fargs
    local key = fargs[1]
    local args = vim.list_slice(fargs, 2, #fargs)
    local sub = subcommands[key]
    if not sub then
        vim.notify("[bq] Unknown subcommand: " .. tostring(key), vim.log.levels.ERROR)
        return
    end
    sub.impl(args, opts)
end

api.nvim_create_user_command("BQ", dispatch, {
    nargs = "+",
    range = true,
    bang = true,
    complete = complete,
    desc = "BQ — BigQuery client",
})
