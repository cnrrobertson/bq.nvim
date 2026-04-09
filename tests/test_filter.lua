-- Tests for parse_filter and row_matches in bq.views.results.
-- These run directly in the headless test host (no child Neovim needed).

local T      = MiniTest.new_set()
local eq     = MiniTest.expect.equality
local no_err = MiniTest.expect.no_error

local helpers    = require('bq.views.results')._test
local parse_filter = helpers.parse_filter
local row_matches  = helpers.row_matches

-- ---------------------------------------------------------------------------
-- parse_filter
-- ---------------------------------------------------------------------------

T['parse_filter'] = MiniTest.new_set()

T['parse_filter']['bare pattern → single condition, no column'] = function()
    local f = parse_filter('foo')
    eq(#f.conditions, 1)
    eq(f.conditions[1].col, nil)
    eq(f.conditions[1].op,  '=')
    eq(f.conditions[1].pat, 'foo')
end

T['parse_filter']['col=pat → column equality'] = function()
    local f = parse_filter('status=active')
    eq(#f.conditions, 1)
    eq(f.conditions[1].col, 'status')
    eq(f.conditions[1].op,  '=')
    eq(f.conditions[1].pat, 'active')
end

T['parse_filter']['col!=pat → column negation'] = function()
    local f = parse_filter('name!=NULL')
    eq(#f.conditions, 1)
    eq(f.conditions[1].col, 'name')
    eq(f.conditions[1].op,  '!=')
    eq(f.conditions[1].pat, 'NULL')
end

T['parse_filter']['OR pipe splits into two bare conditions'] = function()
    local f = parse_filter('pending|complete')
    eq(#f.conditions, 2)
    eq(f.conditions[1].col, nil)
    eq(f.conditions[1].pat, 'pending')
    eq(f.conditions[2].col, nil)
    eq(f.conditions[2].pat, 'complete')
end

T['parse_filter']['OR pipe splits two column conditions'] = function()
    local f = parse_filter('status=ok|name!=NULL')
    eq(#f.conditions, 2)
    eq(f.conditions[1].col, 'status')
    eq(f.conditions[1].op,  '=')
    eq(f.conditions[2].col, 'name')
    eq(f.conditions[2].op,  '!=')
end

T['parse_filter']['spaces around = are tolerated'] = function()
    local f = parse_filter('status = active')
    eq(#f.conditions, 1)
    eq(f.conditions[1].col, 'status')
    eq(f.conditions[1].op,  '=')
    eq(f.conditions[1].pat, 'active')
end

T['parse_filter']['spaces around != are tolerated'] = function()
    local f = parse_filter('status != NULL')
    eq(#f.conditions, 1)
    eq(f.conditions[1].col, 'status')
    eq(f.conditions[1].op,  '!=')
    eq(f.conditions[1].pat, 'NULL')
end

T['parse_filter']['single quotes stripped from value'] = function()
    local f = parse_filter("status='active'")
    eq(f.conditions[1].col, 'status')
    eq(f.conditions[1].pat, 'active')
end

T['parse_filter']['double quotes stripped from value'] = function()
    local f = parse_filter('status="active"')
    eq(f.conditions[1].col, 'status')
    eq(f.conditions[1].pat, 'active')
end

T['parse_filter']['leading/trailing pipe characters produce no extra conditions'] = function()
    local f = parse_filter('|foo|')
    eq(#f.conditions, 1)
    eq(f.conditions[1].pat, 'foo')
end

T['parse_filter']['three OR terms produce three conditions'] = function()
    local f = parse_filter('a|b|c')
    eq(#f.conditions, 3)
    eq(f.conditions[1].pat, 'a')
    eq(f.conditions[2].pat, 'b')
    eq(f.conditions[3].pat, 'c')
end

-- ---------------------------------------------------------------------------
-- row_matches
-- ---------------------------------------------------------------------------

T['row_matches'] = MiniTest.new_set()

local cols = { 'name', 'status' }
local function row(name, status) return { name = name, status = status } end

T['row_matches']['bare pattern matches any column (case-insensitive)'] = function()
    -- "alice" should match the name column value "Alice"
    eq(row_matches(row('Alice', 'active'), cols, parse_filter('alice')), true)
end

T['row_matches']['bare pattern matches value in second column'] = function()
    eq(row_matches(row('Alice', 'active'), cols, parse_filter('activ')), true)
end

T['row_matches']['bare pattern with no match returns false'] = function()
    eq(row_matches(row('Alice', 'active'), cols, parse_filter('xyz')), false)
end

T['row_matches']['col= matches when column contains pattern'] = function()
    eq(row_matches(row('Alice', 'active'), cols, parse_filter('status=active')), true)
end

T['row_matches']['col= partial substring match'] = function()
    -- "activ" is a substring of "active"
    eq(row_matches(row('Alice', 'active'), cols, parse_filter('status=activ')), true)
end

T['row_matches']['col= no match returns false'] = function()
    eq(row_matches(row('Alice', 'active'), cols, parse_filter('status=xyz')), false)
end

T['row_matches']['col!= excludes row when column matches pattern'] = function()
    -- status IS "active", so status!=active should NOT match
    eq(row_matches(row('Alice', 'active'), cols, parse_filter('status!=active')), false)
end

T['row_matches']['col!= passes row when column does not contain pattern'] = function()
    -- "disabled" does not contain "active"
    eq(row_matches(row('Alice', 'disabled'), cols, parse_filter('status!=active')), true)
end

T['row_matches']['matching is case-insensitive'] = function()
    eq(row_matches(row('Alice', 'ACTIVE'), cols, parse_filter('active')), true)
    eq(row_matches(row('Alice', 'active'), cols, parse_filter('ACTIVE')), true)
end

T['row_matches']['nil value is treated as NULL string'] = function()
    local r = { name = nil, status = 'active' }
    eq(row_matches(r, cols, parse_filter('NULL')), true)
end

T['row_matches']['nil value does not match non-NULL pattern'] = function()
    local r = { name = nil, status = 'active' }
    eq(row_matches(r, cols, parse_filter('name=something')), false)
end

T['row_matches']['OR: any matching condition returns true'] = function()
    -- status="active" matches second OR term
    eq(row_matches(row('Alice', 'active'), cols, parse_filter('pending|active')), true)
end

T['row_matches']['OR: first condition matches'] = function()
    eq(row_matches(row('Alice', 'pending'), cols, parse_filter('pending|complete')), true)
end

T['row_matches']['OR: no condition matches returns false'] = function()
    eq(row_matches(row('Alice', 'disabled'), cols, parse_filter('pending|complete')), false)
end

T['row_matches']['invalid Lua pattern does not raise an error'] = function()
    no_err(function()
        row_matches(row('Alice', 'active'), cols, parse_filter('('))
    end)
end

T['row_matches']['invalid Lua pattern returns false'] = function()
    eq(row_matches(row('Alice', 'active'), cols, parse_filter('(')), false)
end

T['row_matches']['column filter only checks named column, not others'] = function()
    -- "alice" in name column but we filter on status
    eq(row_matches(row('alice', 'active'), cols, parse_filter('status=alice')), false)
    eq(row_matches(row('alice', 'active'), cols, parse_filter('name=alice')),   true)
end

T['row_matches']['Lua regex special chars in value match literally via pcall'] = function()
    -- Dot is a wildcard in Lua patterns — "a.c" matches "abc"
    -- This is expected behaviour (Lua patterns, not plain text)
    eq(row_matches(row('Alice', 'abc'), cols, parse_filter('a.c')), true)
end

return T
