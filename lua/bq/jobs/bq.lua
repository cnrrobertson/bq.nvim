local jobs = require("bq.jobs")
local setup = require("bq.setup")

local M = {}

---@param project? string
---@return string[]
local function bq_base(project)
    local cmd = { setup.config.bq_path }
    if project and project ~= "" then
        table.insert(cmd, "--project_id=" .. project)
    end
    return cmd
end

---@param sql string
---@param project? string
---@param on_done fun(code: integer, data: table?, raw: string)
M.run_query = function(sql, project, on_done)
    local cmd = bq_base(project)
    vim.list_extend(cmd, {
        "--format=prettyjson",
        "query",
        "--nouse_legacy_sql",
        "--max_rows=" .. tostring(setup.config.max_results),
        sql,
    })
    jobs.run_job({
        cmd = cmd,
        on_exit = function(code, output)
            if code ~= 0 then
                on_done(code, nil, output)
                return
            end
            local ok, decoded = pcall(vim.fn.json_decode, output)
            if not ok then
                -- bq may return empty output for queries with no rows (DDL, etc.)
                on_done(0, {}, output)
                return
            end
            if type(decoded) ~= "table" then
                on_done(0, {}, output)
                return
            end
            on_done(0, decoded, output)
        end,
    })
end

---@param sql string
---@param project? string
---@param on_done fun(code: integer, output: string)
M.dry_run = function(sql, project, on_done)
    local cmd = bq_base(project)
    vim.list_extend(cmd, {
        "query",
        "--dry_run",
        "--nouse_legacy_sql",
        sql,
    })
    jobs.run_job({
        cmd = cmd,
        on_exit = on_done,
    })
end

---@param project? string
---@param dataset? string
---@param on_done fun(code: integer, data: table?)
M.ls = function(project, dataset, on_done)
    local cmd = bq_base(project)
    vim.list_extend(cmd, { "--format=prettyjson", "ls" })
    if dataset and dataset ~= "" then
        table.insert(cmd, dataset)
    end
    jobs.run_job({
        cmd = cmd,
        on_exit = function(code, output)
            if code ~= 0 then
                on_done(code, nil)
                return
            end
            local ok, decoded = pcall(vim.fn.json_decode, output)
            on_done(0, ok and decoded or {})
        end,
    })
end

---@param project? string
---@param ref string
---@param on_done fun(code: integer, data: table?)
M.show = function(project, ref, on_done)
    local cmd = bq_base(project)
    vim.list_extend(cmd, { "--format=prettyjson", "show", ref })
    jobs.run_job({
        cmd = cmd,
        on_exit = function(code, output)
            if code ~= 0 then
                on_done(code, nil)
                return
            end
            local ok, decoded = pcall(vim.fn.json_decode, output)
            on_done(0, ok and decoded or nil)
        end,
    })
end

return M
