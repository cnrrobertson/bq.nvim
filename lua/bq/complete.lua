local M = {}

---@param arg_lead string
---@return string[]
M.complete_projects = function(arg_lead)
    -- Optional: shell out to gcloud for project completion.
    -- For now return empty — projects are typically just typed.
    _ = arg_lead
    return {}
end

---@param arg_lead string
---@return string[]
M.complete_datasets = function(arg_lead)
    local state = require("bq.state")
    -- Return cached dataset names from the last schema browse, if any
    _ = arg_lead
    _ = state
    return {}
end

---@param arg_lead string
---@return string[]
M.complete_views = function(arg_lead)
    local sections = require("bq.setup").config.winbar.sections
    local result = {}
    for _, s in ipairs(sections) do
        if s:find(arg_lead or "", 1, true) == 1 then
            table.insert(result, s)
        end
    end
    return result
end

return M
