-- Tests for per-tab window tracking.
--
-- Covers two areas introduced since v0.3.0:
--
--   1. state.lua metatable — state.winnr is a virtual field backed by
--      state.tab_wins[current_tabpage].  Tests verify that reads/writes route
--      to the correct tab slot and that tabs are fully isolated.
--
--   2. actions.lua multi-tab open/close — open() reuses shared buffers across
--      tabs; close() only deletes shared buffers when every tab's panel is gone.
--
-- NOTE: child.lua_get() evaluates a SINGLE expression — no `local` statements.
-- Multi-step logic uses child.lua() to stash results in _G._var, then retrieves
-- them with child.lua_get("_G._var").

local child = MiniTest.new_child_neovim()
local T = MiniTest.new_set({
    hooks = {
        pre_case = function()
            child.restart({ '--headless', '--noplugin', '-u', 'scripts/minimal_init.lua' })
        end,
        post_case = function()
            child.stop()
        end,
    },
})

local eq    = MiniTest.expect.equality
local no_eq = MiniTest.expect.no_equality

-- Returns the number of entries in state.tab_wins.
-- Tab page IDs are non-sequential integers so # is unreliable; uses pairs().
local function count_tab_wins()
    child.lua([[
        _G._tw_count = (function()
            local n = 0
            for _ in pairs(require('bq.state').tab_wins) do n = n + 1 end
            return n
        end)()
    ]])
    return child.lua_get("_G._tw_count")
end

-- ---------------------------------------------------------------------------
-- Section 1: state metatable
-- Tests that state.winnr transparently routes to state.tab_wins[tabpage_id].
-- Does NOT require full plugin setup — just loads bq.state directly.
-- ---------------------------------------------------------------------------

T['state metatable'] = MiniTest.new_set()

T['state metatable']['winnr is nil on fresh state'] = function()
    -- No writes; __index should return nil for the initial tabpage.
    child.lua("_G._winnr = require('bq.state').winnr")
    eq(child.lua_get("_G._winnr"), vim.NIL)
end

T['state metatable']['winnr write and read round-trips correctly'] = function()
    -- 42 is not a real window ID but the metatable stores any value.
    child.lua("require('bq.state').winnr = 42")
    child.lua("_G._winnr = require('bq.state').winnr")
    eq(child.lua_get("_G._winnr"), 42)
end

T['state metatable']['winnr is isolated per tabpage'] = function()
    child.lua([[
        local state = require('bq.state')
        state.winnr = 42          -- stored in tab 1's slot
        vim.cmd('tabnew')
        state.winnr = 99          -- stored in tab 2's slot
        _G._tab2 = state.winnr
        vim.cmd('tabprev')
        _G._tab1 = state.winnr
    ]])
    eq(child.lua_get("_G._tab1"), 42)
    eq(child.lua_get("_G._tab2"), 99)
end

T['state metatable']['winnr nil clears only current tab, other tab preserved'] = function()
    child.lua([[
        local state = require('bq.state')
        state.winnr = 42
        vim.cmd('tabnew')
        state.winnr = 99
        state.winnr = nil         -- clear tab 2 only
        _G._tab2_after = state.winnr
        vim.cmd('tabprev')
        _G._tab1_after = state.winnr
    ]])
    eq(child.lua_get("_G._tab2_after"), vim.NIL)
    eq(child.lua_get("_G._tab1_after"), 42)
end

T['state metatable']['tab_wins count is 2 after writing two tabs'] = function()
    child.lua([[
        local state = require('bq.state')
        state.winnr = 10
        vim.cmd('tabnew')
        state.winnr = 20
    ]])
    eq(count_tab_wins(), 2)
end

T['state metatable']['tab_wins is empty after all entries are cleared'] = function()
    child.lua([[
        local state = require('bq.state')
        state.winnr = 10
        vim.cmd('tabnew')
        state.winnr = 20
        state.winnr = nil         -- clear tab 2
        vim.cmd('tabprev')
        state.winnr = nil         -- clear tab 1
    ]])
    eq(count_tab_wins(), 0)
end

-- ---------------------------------------------------------------------------
-- Section 2: multi-tab window management
-- Each test boots the full plugin so open()/close() can create real windows.
-- ---------------------------------------------------------------------------

T['multi-tab window management'] = MiniTest.new_set()

T['multi-tab window management']['open creates a window in current tab'] = function()
    child.lua("require('bq').setup({})")
    child.lua("require('bq.actions').open()")
    child.lua("_G._winnr = require('bq.state').winnr")
    no_eq(child.lua_get("_G._winnr"), vim.NIL)
end

T['multi-tab window management']['open in two tabs produces distinct window IDs'] = function()
    child.lua("require('bq').setup({})")
    child.lua([[
        local actions = require('bq.actions')
        local state   = require('bq.state')
        actions.open()
        _G._win1 = state.winnr
        vim.cmd('tabnew')
        actions.open()
        _G._win2 = state.winnr
    ]])
    -- Each tab gets its own real window handle
    no_eq(child.lua_get("_G._win1"), child.lua_get("_G._win2"))
    -- Both tabs are tracked in tab_wins
    eq(count_tab_wins(), 2)
end

T['multi-tab window management']['shared buffers are reused across tabs'] = function()
    child.lua("require('bq').setup({})")
    child.lua([[
        local actions = require('bq.actions')
        local state   = require('bq.state')
        actions.open()
        _G._buf1 = state.bufs.results    -- capture after first open
        vim.cmd('tabnew')
        actions.open()
        _G._buf2 = state.bufs.results    -- should be the same buffer
    ]])
    -- open() reuses valid buffers; if the guard is broken a new ID is created
    eq(child.lua_get("_G._buf1"), child.lua_get("_G._buf2"))
end

T['multi-tab window management']['close in tab2 does not affect tab1 window or buffers'] = function()
    child.lua("require('bq').setup({})")
    child.lua([[
        local actions = require('bq.actions')
        local state   = require('bq.state')
        -- Open in tab 1 and stash its window ID before switching tabs
        actions.open()
        _G._win1 = state.winnr
        vim.cmd('tabnew')
        actions.open()
        -- Close panel in tab 2 only
        actions.close()
        -- Switch back and inspect tab 1
        vim.cmd('tabprev')
        _G._win1_after   = state.winnr
        _G._bufs_present = not vim.tbl_isempty(state.bufs)
    ]])
    -- Tab 1's window handle must be unchanged
    eq(child.lua_get("_G._win1"), child.lua_get("_G._win1_after"))
    -- Shared buffers must NOT be deleted while tab 1 still has a panel
    eq(child.lua_get("_G._bufs_present"), true)
end

T['multi-tab window management']['close on last open tab deletes shared buffers'] = function()
    child.lua("require('bq').setup({})")
    child.lua([[
        local actions = require('bq.actions')
        local state   = require('bq.state')
        actions.open()
        actions.close()
        _G._bufs_empty = vim.tbl_isempty(state.bufs)
    ]])
    -- When the last panel closes, state.bufs must be reset to {}
    eq(child.lua_get("_G._bufs_empty"), true)
end

T['multi-tab window management']['tab_wins count tracks open and close across tabs'] = function()
    child.lua("require('bq').setup({})")
    -- Open in both tabs
    child.lua([[
        local actions = require('bq.actions')
        actions.open()
        vim.cmd('tabnew')
        actions.open()
    ]])
    eq(count_tab_wins(), 2)

    -- Close tab 2 → one entry remains
    child.lua("require('bq.actions').close()")
    eq(count_tab_wins(), 1)

    -- Close tab 1 → empty
    child.lua([[
        vim.cmd('tabprev')
        require('bq.actions').close()
    ]])
    eq(count_tab_wins(), 0)
end

return T
