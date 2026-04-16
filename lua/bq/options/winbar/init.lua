local state = require("bq.state")
local setup = require("bq.setup")
local statusline = require("bq.util.statusline")
local util = require("bq.util")

-- NOTE: this module path is used in the clickable statusline expression,
-- so the variable `module` must capture it at load time.
local module = ...

local M = {}

local api = vim.api

---@param view string
local wrapped_action = function(view)
    if not util.is_win_valid(state.winnr) then
        return
    end
    require("bq.views").switch_to_view(view)
end

M.set_action_keymaps = function()
    local winbar_cfg = setup.config.winbar
    for _, bufnr in pairs(state.bufs) do
        for _, view in ipairs(winbar_cfg.sections) do
            local section = winbar_cfg.base_sections[view]
            if section then
                vim.keymap.set("n", section.keymap, function()
                    wrapped_action(view)
                end, { buffer = bufnr, nowait = true })
            end
        end
    end
end

---@param idx integer
M.on_click = function(idx)
    local view = setup.config.winbar.sections[idx]
    if view then
        wrapped_action(view)
    end
end

M.set_winbar_opt = function()
    if not util.is_win_valid(state.winnr) then return end

    local winbar_cfg = setup.config.winbar
    local parts = {}

    table.insert(parts, statusline.hl("", "TabFill", false))

    local win_width = api.nvim_win_get_width(state.winnr)
    _ = win_width  -- available for future label truncation

    for k, view in ipairs(winbar_cfg.sections) do
        local section = winbar_cfg.base_sections[view]
        if section then
            local label = type(section.label) == "function"
                and section.label(state.current_section)
                or section.label

            ---@cast label string
            local desc = " " .. label .. " "
            if winbar_cfg.show_keymap_hints then
                desc = desc .. "[" .. section.keymap .. "] "
            end

            desc = statusline.clickable(desc, module, "on_click", k)

            if state.current_section == view then
                desc = statusline.hl(desc, "TabSelected")
            else
                desc = statusline.hl(desc, "Tab")
            end

            table.insert(parts, desc)
        end
    end

    -- Right-align a subtle "g? help" hint
    table.insert(parts, "%=")
    table.insert(parts, statusline.hl(" g? help ", "Hint"))
    table.insert(parts, statusline.hl("", "TabFill", false))

    vim.wo[state.winnr][0].winbar = table.concat(parts, "")
end

---@param view? string
M.refresh_winbar = function(view)
    if setup.config.winbar.show then
        if view then
            state.current_section = view
        end
        M.set_winbar_opt()
    end
end

---@param view string
M.show_content = function(view)
    wrapped_action(view)
end

return M
