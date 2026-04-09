---@tag bq.config
---@signature bq.config
---
--- Configuration table passed to |bq.setup|. All fields are optional —
--- unset fields fall back to the defaults shown below.
---
---@class bq.WinbarSectionConfig
---@field label string Display label shown in the winbar tab
---@field keymap string Key that switches to this section (set per buffer)

---@class bq.WinbarConfig
---@field show boolean Show the winbar tab strip
---@field sections string[] Ordered list of section names to include
---@field default_section string Section shown when the panel first opens
---@field show_keymap_hints boolean Append `[key]` hints to each tab label
---@field base_sections table<string, bq.WinbarSectionConfig> Per-section label and keymap

---@class bq.WindowsConfig
---@field size number Split size: fraction of editor (< 1) or absolute lines/columns
---@field position string Split direction: `"above"`, `"below"`, `"left"`, or `"right"`

---@class bq.PreviewConfig
---@field max_width number Maximum width of the preview float. Fractions < 1 are a percentage of editor width (e.g. 0.8 = 80%); integers are absolute columns.
---@field max_height number Maximum height of the preview float. Fractions < 1 are a percentage of editor height (e.g. 0.6 = 60%); integers are absolute lines.

---@class bq.ExportConfig
---@field dir string Default directory for CSV exports. `~` is expanded to the home directory.
---@field name string Filename template; supports `os.date` format codes (e.g. `%Y%m%d-%H%M%S`). Use a fixed name like `"bq-export.csv"` to always overwrite.

---@class bq.Config
---@field winbar bq.WinbarConfig Winbar / tab-strip configuration
---@field windows bq.WindowsConfig Panel window configuration
---@field preview bq.PreviewConfig Row preview window configuration
---@field export bq.ExportConfig CSV export configuration
---@field bq_path string Path or name of the `bq` CLI executable
---@field max_results integer Maximum rows fetched per query

---@text Default values:
---@eval return MiniDoc.afterlines_to_code(MiniDoc.current.eval_section)
--minidoc_replace_start bq.config = {
local M = {
    --minidoc_replace_end
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
    preview = {
        max_width  = 0.8,
        max_height = 0.6,
    },
    export = {
        dir  = "~/Downloads",
        name = "bq-export-%Y%m%d-%H%M%S.csv",
    },
    bq_path = "bq",
    max_results = 1000,
}
--minidoc_afterlines_end

return M
