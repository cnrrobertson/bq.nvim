local state = require("bq.state")

local M = {}

---@param msg string
M.append = function(msg)
    local ts = os.date("%H:%M:%S")
    local prefix = string.format("[%s] ", ts)
    for line in (msg .. "\n"):gmatch("([^\n]*)\n") do
        if line ~= "" then
            table.insert(state.debug_log, prefix .. line)
            prefix = string.rep(" ", #prefix)  -- indent continuation lines
        end
    end
end

return M
