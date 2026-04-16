local defaults = require("bq.config")

local M = {}

---@type bq.Config
M.config = vim.deepcopy(defaults)

---@param user_config? bq.Config
M.setup = function(user_config)
    M.config = vim.tbl_deep_extend("force", vim.deepcopy(defaults), user_config or {})
    require("bq.persist").setup()   -- ensure dirs exist; load persisted history
end

return M
