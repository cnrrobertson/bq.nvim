local globals = require("bq.globals")

local M = {}

---@param text string
---@param group string
---@param clean boolean?
---@return string
M.hl = function(text, group, clean)
    local part = "%#" .. globals.HL_PREFIX .. group .. "#" .. text
    if clean == nil or clean then
        return part .. "%*"
    end
    return part
end

---@param text string
---@param module string
---@param handler string
---@param idx integer
---@return string
M.clickable = function(text, module, handler, idx)
    return "%" .. idx .. "@v:lua.require'" .. module .. "'." .. handler .. "@" .. text .. "%T"
end

return M
