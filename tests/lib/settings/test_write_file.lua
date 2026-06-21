-- Exercises the REAL default io_provider.write_file (no mock provider, no lfs).
--
--   warm path — write to a file in an already-existing directory. The first
--               io.open succeeds, so windower.create_dir is never called and
--               the content lands on disk verbatim.
--   cold path — write to a file whose directory does not exist. A pure recorder
--               stub captures the parent-first create_dir requests but creates
--               nothing, so the retry open fails and write_file raises the
--               documented "cannot open for writing" error.
--
-- A regression guard replaces os.execute with a raiser for both cases: any
-- shell-out fails the run. All globals are restored and temp files removed even
-- if an assertion bails out mid-case.

local pass = 0
local fail = 0

local function test(name, fn)
  local ok, err = pcall(fn)
  if ok then
    pass = pass + 1
    io.write('  pass: ' .. name .. '\n')
  else
    fail = fail + 1
    io.write('  FAIL: ' .. name .. '\n    ' .. tostring(err) .. '\n')
  end
end

local function assert_eq(expected, actual, msg)
  if expected ~= actual then
    error(string.format('%s\n    expected: %s\n      actual: %s',
      msg or 'values not equal', tostring(expected), tostring(actual)), 2)
  end
end

local function read_all(path)
  local f = io.open(path, 'r')
  if not f then return nil end
  local content = f:read('*all')
  f:close()
  return content
end

-- Load a fresh copy of the module so the real default io_provider is intact,
-- regardless of any provider another test file swapped in earlier in the run.
package.loaded['lib.settings.settings'] = nil
local settings = require('lib.settings.settings')
local write_file = settings._io_provider().write_file

-- os.tmpname() returns a path inside an existing temp directory. Its parent is a
-- guaranteed-existing home for the warm-path file; a never-created subdirectory
-- of it is the cold-path target.
math.randomseed(os.time())
local tmp         = os.tmpname()
os.remove(tmp)
local temp_dir    = tmp:match('^(.*)[/\\][^/\\]+$') or '.'
local stamp       = tostring(os.time()) .. '_' .. tostring(math.random(1, 1000000))
local warm_file   = temp_dir .. '/lib_settings_warm_' .. stamp .. '.json'
local missing_dir = temp_dir .. '/lib_settings_missing_' .. stamp
local cold_file   = missing_dir .. '/settings.json'

-- Run body with os.execute guarded and globals restored afterward, even on error.
local function with_guards(body)
  local saved_exec = os.execute
  local saved_dir  = windower.create_dir

  os.execute = function()
    error('os.execute must never be called')
  end

  local ok, err = pcall(body)

  os.execute          = saved_exec
  windower.create_dir = saved_dir

  if not ok then error(err, 0) end
end

local function cleanup()
  os.remove(warm_file)
  os.remove(cold_file)
end

-- ----

test('warm path: existing dir → write succeeds, no create_dir, no shell-out', function()
  with_guards(function()
    local called = false
    windower.create_dir = function() called = true return true end

    write_file(warm_file, '{"label":"warm"}')

    assert_eq('{"label":"warm"}', read_all(warm_file), 'warm-path file content')
    assert(not called, 'create_dir must not be called when the directory exists')
  end)
end)

test('cold path: missing dir → create_dir recorded parent-first, write errors, no shell-out', function()
  with_guards(function()
    local created = {}
    -- Pure recorder: capture each requested path, create nothing on disk.
    windower.create_dir = function(dir)
      table.insert(created, dir)
      return true
    end

    local ok, err = pcall(function()
      write_file(cold_file, '{"label":"cold"}')
    end)

    assert(not ok, 'write_file must raise when the directory cannot be created')
    assert(tostring(err):find('cannot open for writing: ' .. cold_file, 1, true),
      'error must report the unwritable path, got: ' .. tostring(err))

    -- Recorded parent-first, ending at the deepest missing directory.
    assert(#created > 0, 'create_dir must be invoked for the missing directory')
    assert_eq(missing_dir, created[#created], 'deepest dir created last (parent-first)')

    -- Each recorded path must be the previous one plus exactly one segment, so
    -- the chain is strictly ascending prefixes (independent of ensure_dir's code).
    for i = 2, #created do
      local prev, cur = created[i - 1], created[i]
      assert(cur:sub(1, #prev) == prev, 'segment ' .. i .. ' must extend the previous dir')
      local tail = cur:sub(#prev + 1)
      assert(tail:match('^[/\\][^/\\]+$'), 'segment ' .. i .. ' must add one path component')
    end

    -- Nothing was actually written.
    assert(read_all(cold_file) == nil, 'no file should exist on the cold path')
  end)
end)

-- ----

cleanup()
io.write(string.format('test_write_file: %d passed, %d failed\n', pass, fail))
if fail > 0 then
  error(fail .. ' test(s) failed in test_write_file.lua')
end
