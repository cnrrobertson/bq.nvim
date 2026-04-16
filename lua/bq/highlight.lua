local api = vim.api
local prefix = require("bq.globals").HL_PREFIX

local function hl(name, link)
    api.nvim_set_hl(0, prefix .. name, { default = true, link = link })
end

local function define()
    hl("Tab",         "TabLine")
    hl("TabSelected", "TabLineSel")
    hl("TabFill",     "TabLineFill")
    hl("Header",      "Title")
    hl("StatKey",     "Identifier")
    hl("HistoryOk",   "DiagnosticOk")
    hl("HistoryErr",  "DiagnosticError")
    hl("NullValue",   "Comment")
    hl("Loading",     "Comment")
    hl("MissingData", "DiagnosticVirtualTextWarn")
    hl("BorderChar",  "Comment")
    hl("Hint",        "Comment")
end

define()

api.nvim_create_autocmd("ColorScheme", {
    group = api.nvim_create_augroup("bq_hl", { clear = true }),
    callback = define,
})
