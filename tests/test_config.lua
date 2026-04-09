-- Tests for bq.setup config merging.
-- These run directly in the headless test host (no child Neovim needed).

local T      = MiniTest.new_set()
local eq     = MiniTest.expect.equality
local no_eq  = MiniTest.expect.no_equality

-- Re-require setup fresh before each case so state doesn't bleed between tests.
local function fresh_setup()
    package.loaded['bq.setup'] = nil
    package.loaded['bq.config'] = nil
    return require('bq.setup')
end

-- ---------------------------------------------------------------------------
-- Defaults
-- ---------------------------------------------------------------------------

T['defaults'] = MiniTest.new_set()

T['defaults']['all top-level fields present'] = function()
    local s = fresh_setup()
    s.setup()
    eq(s.config.bq_path,     'bq')
    eq(s.config.max_results, 1000)
end

T['defaults']['windows defaults'] = function()
    local s = fresh_setup()
    s.setup()
    eq(s.config.windows.size,     0.35)
    eq(s.config.windows.position, 'below')
end

T['defaults']['preview defaults'] = function()
    local s = fresh_setup()
    s.setup()
    eq(s.config.preview.max_width,  0.8)
    eq(s.config.preview.max_height, 0.6)
end

T['defaults']['export defaults'] = function()
    local s = fresh_setup()
    s.setup()
    eq(s.config.export.dir,  '~/Downloads')
    eq(s.config.export.name, 'bq-export-%Y%m%d-%H%M%S.csv')
end

T['defaults']['winbar default section'] = function()
    local s = fresh_setup()
    s.setup()
    eq(s.config.winbar.default_section, 'results')
    eq(s.config.winbar.show, true)
end

-- ---------------------------------------------------------------------------
-- Overrides
-- ---------------------------------------------------------------------------

T['overrides'] = MiniTest.new_set()

T['overrides']['top-level field changed, others preserved'] = function()
    local s = fresh_setup()
    s.setup({ max_results = 500 })
    eq(s.config.max_results, 500)
    eq(s.config.bq_path,     'bq')  -- unchanged
end

T['overrides']['bq_path override'] = function()
    local s = fresh_setup()
    s.setup({ bq_path = '/usr/local/bin/bq' })
    eq(s.config.bq_path, '/usr/local/bin/bq')
    eq(s.config.max_results, 1000)  -- unchanged
end

T['overrides']['deep merge: sibling key preserved'] = function()
    -- Override only export.dir; export.name should remain the default.
    local s = fresh_setup()
    s.setup({ export = { dir = '~/Desktop' } })
    eq(s.config.export.dir,  '~/Desktop')
    eq(s.config.export.name, 'bq-export-%Y%m%d-%H%M%S.csv')  -- preserved
end

T['overrides']['deep merge: windows sibling preserved'] = function()
    local s = fresh_setup()
    s.setup({ windows = { size = 0.5 } })
    eq(s.config.windows.size,     0.5)
    eq(s.config.windows.position, 'below')  -- preserved
end

T['overrides']['second setup() call replaces first'] = function()
    local s = fresh_setup()
    s.setup({ max_results = 500 })
    s.setup({ max_results = 200 })
    eq(s.config.max_results, 200)
end

T['overrides']['second setup() restores un-overridden defaults'] = function()
    local s = fresh_setup()
    s.setup({ bq_path = 'custom-bq' })
    s.setup({})  -- empty override should restore everything
    eq(s.config.bq_path, 'bq')
end

-- ---------------------------------------------------------------------------
-- Edge cases
-- ---------------------------------------------------------------------------

T['edge cases'] = MiniTest.new_set()

T['edge cases']['nil user config uses defaults'] = function()
    local s = fresh_setup()
    s.setup(nil)
    eq(s.config.max_results, 1000)
    eq(s.config.bq_path,     'bq')
end

T['edge cases']['empty table uses defaults'] = function()
    local s = fresh_setup()
    s.setup({})
    eq(s.config.max_results, 1000)
    eq(s.config.bq_path,     'bq')
end

T['edge cases']['config is a new table each call (no mutation of defaults)'] = function()
    local s = fresh_setup()
    s.setup({ max_results = 42 })
    local first = s.config.max_results

    -- Re-setup with no override — defaults must not have been mutated
    s.setup()
    eq(s.config.max_results, 1000)
    no_eq(s.config.max_results, first)
end

return T
