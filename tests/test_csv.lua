-- Tests for write_csv in bq.views.results.
-- Writes to /tmp/ and reads the file back to assert exact RFC-4180 content.
-- These run directly in the headless test host (no child Neovim needed).

local T         = MiniTest.new_set()
local eq        = MiniTest.expect.equality
local no_eq     = MiniTest.expect.no_equality

local write_csv = require('bq.views.results')._test.write_csv

-- Read a file's full contents, return nil on failure.
local function read_file(path)
    local f = io.open(path, 'r')
    if not f then return nil end
    local content = f:read('*a')
    f:close()
    return content
end

-- Generate a unique temp path to avoid inter-test collisions.
local function tmp_path()
    return string.format('/tmp/bq_test_%d_%d.csv', os.time(), math.random(1, 1000000))
end

-- ---------------------------------------------------------------------------
-- Return values
-- ---------------------------------------------------------------------------

T['return values'] = MiniTest.new_set()

T['return values']['returns true on success'] = function()
    local ok, err = write_csv({}, { 'col' }, tmp_path())
    eq(ok,  true)
    eq(err, nil)
end

T['return values']['returns nil + error string on bad path'] = function()
    local ok, err = write_csv({}, { 'col' }, '/nonexistent_dir/file.csv')
    eq(ok, nil)
    no_eq(err, nil)
end

-- ---------------------------------------------------------------------------
-- Header row
-- ---------------------------------------------------------------------------

T['header'] = MiniTest.new_set()

T['header']['single column written as header'] = function()
    local path = tmp_path()
    write_csv({}, { 'name' }, path)
    eq(read_file(path), 'name\n')
end

T['header']['multiple columns written as comma-separated header'] = function()
    local path = tmp_path()
    write_csv({}, { 'name', 'status', 'count' }, path)
    eq(read_file(path), 'name,status,count\n')
end

T['header']['column name with comma is quoted'] = function()
    local path = tmp_path()
    write_csv({}, { 'a,b' }, path)
    eq(read_file(path), '"a,b"\n')
end

-- ---------------------------------------------------------------------------
-- Data rows
-- ---------------------------------------------------------------------------

T['data rows'] = MiniTest.new_set()

T['data rows']['single row with plain values'] = function()
    local path = tmp_path()
    write_csv({ { name = 'Alice', status = 'active' } }, { 'name', 'status' }, path)
    eq(read_file(path), 'name,status\nAlice,active\n')
end

T['data rows']['two rows produce three total lines'] = function()
    local path = tmp_path()
    local rows = {
        { id = '1', name = 'Alice' },
        { id = '2', name = 'Bob'   },
    }
    write_csv(rows, { 'id', 'name' }, path)
    eq(read_file(path), 'id,name\n1,Alice\n2,Bob\n')
end

T['data rows']['nil value written as empty field'] = function()
    local path = tmp_path()
    write_csv({ { name = 'Alice', val = nil } }, { 'name', 'val' }, path)
    eq(read_file(path), 'name,val\nAlice,\n')
end

T['data rows']['vim.NIL value written as empty field'] = function()
    local path = tmp_path()
    write_csv({ { name = 'Alice', val = vim.NIL } }, { 'name', 'val' }, path)
    eq(read_file(path), 'name,val\nAlice,\n')
end

-- ---------------------------------------------------------------------------
-- RFC-4180 escaping
-- ---------------------------------------------------------------------------

T['RFC-4180 escaping'] = MiniTest.new_set()

T['RFC-4180 escaping']['value with comma is wrapped in quotes'] = function()
    local path = tmp_path()
    write_csv({ { name = 'Smith, John' } }, { 'name' }, path)
    eq(read_file(path), 'name\n"Smith, John"\n')
end

T['RFC-4180 escaping']['value with double-quote doubles it'] = function()
    local path = tmp_path()
    write_csv({ { name = 'Say "hello"' } }, { 'name' }, path)
    eq(read_file(path), 'name\n"Say ""hello"""\n')
end

T['RFC-4180 escaping']['value with newline is wrapped in quotes'] = function()
    local path = tmp_path()
    write_csv({ { text = 'line1\nline2' } }, { 'text' }, path)
    eq(read_file(path), 'text\n"line1\nline2"\n')
end

T['RFC-4180 escaping']['value with carriage return is wrapped in quotes'] = function()
    local path = tmp_path()
    write_csv({ { text = 'line1\r\nline2' } }, { 'text' }, path)
    -- \r triggers quoting; the literal \r\n is preserved inside the field
    local content = read_file(path)
    -- Just verify the field is quoted (starts with `text\n"`)
    no_eq(content:find('^text\n"'), nil)
end

T['RFC-4180 escaping']['plain value without special chars is not quoted'] = function()
    local path = tmp_path()
    write_csv({ { val = 'hello' } }, { 'val' }, path)
    eq(read_file(path), 'val\nhello\n')
end

T['RFC-4180 escaping']['numeric-like string value is not quoted'] = function()
    local path = tmp_path()
    write_csv({ { val = '12345' } }, { 'val' }, path)
    eq(read_file(path), 'val\n12345\n')
end

T['RFC-4180 escaping']['value with both comma and quote is properly escaped'] = function()
    local path = tmp_path()
    write_csv({ { val = 'say "hi", friend' } }, { 'val' }, path)
    eq(read_file(path), 'val\n"say ""hi"", friend"\n')
end

-- ---------------------------------------------------------------------------
-- Column ordering
-- ---------------------------------------------------------------------------

T['column ordering'] = MiniTest.new_set()

T['column ordering']['fields written in cols order, not row table order'] = function()
    local path = tmp_path()
    local rows = { { b = 'B', a = 'A' } }
    write_csv(rows, { 'a', 'b' }, path)
    eq(read_file(path), 'a,b\nA,B\n')
end

T['column ordering']['missing column in row written as empty field'] = function()
    local path = tmp_path()
    local rows = { { name = 'Alice' } }  -- 'status' key absent
    write_csv(rows, { 'name', 'status' }, path)
    eq(read_file(path), 'name,status\nAlice,\n')
end

return T
