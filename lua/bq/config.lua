---@class bq.WinbarSectionConfig
---@field label string
---@field keymap string

---@class bq.WinbarConfig
---@field show boolean
---@field sections string[]
---@field default_section string
---@field show_keymap_hints boolean
---@field base_sections table<string, bq.WinbarSectionConfig>

---@class bq.WindowsConfig
---@field size number
---@field position string

---@class bq.Config
---@field winbar bq.WinbarConfig
---@field windows bq.WindowsConfig
---@field bq_path string
---@field max_results integer

---@type bq.Config
local M = {
    winbar = {
        show = true,
        sections = { "results", "stats", "history", "schema", "debug" },
        default_section = "results",
        show_keymap_hints = true,
        base_sections = {
            results = { label = "Results", keymap = "R" },
            stats   = { label = "Stats",   keymap = "S" },
            history = { label = "History", keymap = "H" },
            schema  = { label = "Schema",  keymap = "C" },
            debug   = { label = "Debug",   keymap = "D" },
        },
    },
    windows = {
        size = 0.35,
        position = "below",
    },
    bq_path = "bq",
    max_results = 1000,
}

return M
