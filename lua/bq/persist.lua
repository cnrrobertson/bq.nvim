-- Persistence layer for cross-session query history.
--
-- Stores the history index at:
--   vim.fn.stdpath("state")/bq/history.json
--
-- Stores per-query result rows at:
--   vim.fn.stdpath("state")/bq/results/<ts>-<rand>.json
--
-- Schema is NOT stored — it is re-derived from the first row's keys at load
-- time, exactly as actions.lua does after a live query.

local state = require("bq.state")
local setup = require("bq.setup")

local M = {}

-- ---------------------------------------------------------------------------
-- Path helpers
-- ---------------------------------------------------------------------------

local function state_dir()
    return vim.fn.stdpath("state") .. "/bq"
end

local function results_dir()
    return state_dir() .. "/results"
end

local function history_path()
    return state_dir() .. "/history.json"
end

local function result_path(id)
    return results_dir() .. "/" .. id .. ".json"
end

-- ---------------------------------------------------------------------------
-- M.setup — ensure dirs exist; load history.json → state.history
-- ---------------------------------------------------------------------------

M.setup = function()
    -- "p" flag creates parent dirs recursively; safe to call on every startup
    vim.fn.mkdir(results_dir(), "p")

    local f = io.open(history_path(), "r")
    if not f then return end

    local raw = f:read("*a")
    f:close()

    if not raw or raw == "" then return end

    local ok, decoded = pcall(vim.fn.json_decode, raw)
    -- Silently ignore corrupt history files — state.history stays as {}
    if ok and type(decoded) == "table" then
        state.history = decoded
    end
end

-- ---------------------------------------------------------------------------
-- M.save_results — write rows to a per-query JSON file; returns id or nil
-- ---------------------------------------------------------------------------

---@param rows table
---@return string|nil results_id
M.save_results = function(rows)
    if not rows or #rows == 0 then return nil end

    local id = tostring(os.time()) .. "-" .. string.format("%06d", math.random(999999))

    local ok, encoded = pcall(vim.fn.json_encode, rows)
    if not ok or not encoded then return nil end

    local f, err = io.open(result_path(id), "w")
    if not f then
        vim.notify("[bq] Failed to save results: " .. (err or "?"), vim.log.levels.WARN)
        return nil
    end

    f:write(encoded)
    f:close()
    return id
end

-- ---------------------------------------------------------------------------
-- M.load_results — read a result file by id; returns rows table or nil
-- ---------------------------------------------------------------------------

---@param id string
---@return table|nil rows
M.load_results = function(id)
    if not id then return nil end

    local f = io.open(result_path(id), "r")
    if not f then return nil end

    local raw = f:read("*a")
    f:close()

    if not raw or raw == "" then return nil end

    local ok, decoded = pcall(vim.fn.json_decode, raw)
    return (ok and type(decoded) == "table") and decoded or nil
end

-- ---------------------------------------------------------------------------
-- M.save_history — enforce max_entries, prune old result files, write JSON
-- ---------------------------------------------------------------------------

M.save_history = function()
    local max = setup.config.history.max_entries
    local history = state.history

    -- Prune oldest entries (front of array) when over budget.
    -- 0 means unlimited — skip pruning entirely.
    if max > 0 then
        while #history > max do
            local evicted = table.remove(history, 1)
            if evicted.results_id then
                os.remove(result_path(evicted.results_id))
            end
        end
    end

    local ok, encoded = pcall(vim.fn.json_encode, history)
    if not ok or not encoded then return end

    local f, err = io.open(history_path(), "w")
    if not f then
        vim.notify("[bq] Failed to save history: " .. (err or "?"), vim.log.levels.WARN)
        return
    end

    f:write(encoded)
    f:close()
end

return M
