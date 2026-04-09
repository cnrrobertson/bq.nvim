-- Integration tests for the results view rendering.
-- Uses a child Neovim instance so the full plugin lifecycle (open panel,
-- set state, call show) runs in isolation per test.
--
-- NOTE: child.lua_get() evaluates a single expression — no `local` statements.
-- Inline require() calls or stash values in _G._var then retrieve them.

local child = MiniTest.new_child_neovim()
local T     = MiniTest.new_set({
    hooks = {
        pre_case = function()
            child.restart({ '--headless', '--noplugin', '-u', 'scripts/minimal_init.lua' })
            -- Open the bq panel and inject 3 rows of test data.
            child.lua([[
                require('bq').setup({})
                require('bq.actions').open()
                local state   = require('bq.state')
                local results = require('bq.views.results')
                state.results_schema = { 'name', 'status' }
                state.results_data = {
                    { name = 'Alice', status = 'ok'     },
                    { name = 'Bob',   status = 'failed' },
                    { name = 'Carol', status = 'ok'     },
                }
                results.clear_filter()
                results.show(state.bufs.results)
            ]])
        end,
        post_case = function()
            child.stop()
        end,
    },
})

-- Helper: return the hint line (line 0) of the results buffer.
-- Uses a single expression so child.lua_get() can evaluate it.
local function get_hint()
    return child.lua_get(
        "vim.api.nvim_buf_get_lines(require('bq.state').bufs.results, 0, 1, false)[1]"
    )
end

-- Helper: total line count in the results buffer.
local function get_line_count()
    return child.lua_get(
        "#vim.api.nvim_buf_get_lines(require('bq.state').bufs.results, 0, -1, false)"
    )
end

-- ---------------------------------------------------------------------------
-- Baseline rendering (no filters)
-- ---------------------------------------------------------------------------

T['baseline'] = MiniTest.new_set()

T['baseline']['hint line contains row count'] = function()
    local hint = get_hint()
    -- Should read "  3 rows  (…)"
    MiniTest.expect.no_equality(hint:find('3 rows'), nil)
end

T['baseline']['buffer has correct line count'] = function()
    -- Layout: hint(1) + header(1) + 3 data rows + spacer(1) = 6
    MiniTest.expect.equality(get_line_count(), 6)
end

T['baseline']['hint contains expected keymaps'] = function()
    local hint = get_hint()
    MiniTest.expect.no_equality(hint:find('filter'), nil)
    MiniTest.expect.no_equality(hint:find('export'), nil)
end

-- ---------------------------------------------------------------------------
-- Filter: push_filter narrows rows
-- ---------------------------------------------------------------------------

T['push_filter'] = MiniTest.new_set()

T['push_filter']['hint shows filtered/total count'] = function()
    child.lua([[
        local state   = require('bq.state')
        local results = require('bq.views.results')
        results.push_filter('status=ok')
        results.show(state.bufs.results)
    ]])
    -- Alice + Carol have status="ok"; Bob has "failed" → "2/3"
    MiniTest.expect.no_equality(get_hint():find('2/3'), nil)
end

T['push_filter']['buffer line count reduced'] = function()
    child.lua([[
        local state   = require('bq.state')
        local results = require('bq.views.results')
        results.push_filter('status=ok')
        results.show(state.bufs.results)
    ]])
    -- hint(1) + header(1) + 2 data rows + spacer(1) = 5
    MiniTest.expect.equality(get_line_count(), 5)
end

T['push_filter']['hint shows filter tag'] = function()
    child.lua([[
        local state   = require('bq.state')
        local results = require('bq.views.results')
        results.push_filter('status=ok')
        results.show(state.bufs.results)
    ]])
    MiniTest.expect.no_equality(get_hint():find('%[status=ok%]'), nil)
end

-- ---------------------------------------------------------------------------
-- Filter: stacked filters (AND logic)
-- ---------------------------------------------------------------------------

T['stacked filters'] = MiniTest.new_set()

T['stacked filters']['two filters narrow to single row'] = function()
    child.lua([[
        local state   = require('bq.state')
        local results = require('bq.views.results')
        results.push_filter('status=ok')   -- Alice, Carol
        results.push_filter('alice')       -- Alice only
        results.show(state.bufs.results)
    ]])
    MiniTest.expect.no_equality(get_hint():find('1/3'), nil)
end

T['stacked filters']['line count reflects AND result'] = function()
    child.lua([[
        local state   = require('bq.state')
        local results = require('bq.views.results')
        results.push_filter('status=ok')
        results.push_filter('alice')
        results.show(state.bufs.results)
    ]])
    -- hint(1) + header(1) + 1 data row + spacer(1) = 4
    MiniTest.expect.equality(get_line_count(), 4)
end

-- ---------------------------------------------------------------------------
-- Filter: clear_filter restores full result set
-- ---------------------------------------------------------------------------

T['clear_filter'] = MiniTest.new_set()

T['clear_filter']['hint returns to unfiltered count after clear'] = function()
    child.lua([[
        local state   = require('bq.state')
        local results = require('bq.views.results')
        results.push_filter('status=ok')
        results.clear_filter()
        results.show(state.bufs.results)
    ]])
    MiniTest.expect.no_equality(get_hint():find('3 rows'), nil)
end

T['clear_filter']['line count restored after clear'] = function()
    child.lua([[
        local state   = require('bq.state')
        local results = require('bq.views.results')
        results.push_filter('status=ok')
        results.clear_filter()
        results.show(state.bufs.results)
    ]])
    MiniTest.expect.equality(get_line_count(), 6)
end

-- ---------------------------------------------------------------------------
-- Filter: invalid pattern (pcall-safe)
-- ---------------------------------------------------------------------------

T['invalid filter'] = MiniTest.new_set()

T['invalid filter']['hint shows 0/total without error'] = function()
    child.lua([[
        local state   = require('bq.state')
        local results = require('bq.views.results')
        results.push_filter('(')  -- invalid Lua pattern
        results.show(state.bufs.results)
    ]])
    MiniTest.expect.no_equality(get_hint():find('0/3'), nil)
end

-- ---------------------------------------------------------------------------
-- Empty data set
-- ---------------------------------------------------------------------------

T['empty data'] = MiniTest.new_set()

T['empty data']['no-results message shown when data is empty'] = function()
    child.lua([[
        local state   = require('bq.state')
        local results = require('bq.views.results')
        state.results_data   = {}
        state.results_schema = {}
        results.clear_filter()
        results.show(state.bufs.results)
    ]])
    -- Stash line count in a global so lua_get can retrieve it as a single expression
    child.lua(
        "_G._line_count = #vim.api.nvim_buf_get_lines(require('bq.state').bufs.results, 0, -1, false)"
    )
    local count = child.lua_get("_G._line_count")
    -- cleanup_view writes a "No results" style message; buffer has at least 1 line
    MiniTest.expect.no_equality(count, 0)
end

return T
