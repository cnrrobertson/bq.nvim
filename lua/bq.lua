require("bq.highlight")
require("bq.autocmds")

local actions = require("bq.actions")
local state = require("bq.state")

local M = {}

---@param user_config? bq.Config
M.setup = function(user_config)
    require("bq.setup").setup(user_config)
end

M.open = function()
    actions.open()
end

M.close = function()
    actions.close()
end

M.toggle = function()
    actions.toggle()
end

---@param project? string
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
    end
end

---@param sql? string
M.run = function(sql)
    if not sql then
        local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
        sql = table.concat(lines, "\n")
    end
    actions.run_query(sql)
end

---@param view string
M.show_view = function(view)
    actions.show_view(view)
end

---@param opts {count: integer, wrap: boolean}
M.navigate = function(opts)
    actions.navigate(opts)
end

return M
