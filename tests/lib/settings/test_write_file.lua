-- Exercises the REAL default io_provider.write_file (no mock provider, no lfs)
-- and commit's lazy, targeted directory creation.
--
--   write_file warm path — write to a file in an already-existing directory. The
--               io.open succeeds, content lands on disk verbatim, and (since
--               write_file is now pure IO) windower.create_dir is never touched.
--
--   commit cold path — when the per-character dir is missing the first
--               write_file fails, so commit calls ensure_char_dir exactly once,
--               creating ONLY data and data/<char> beneath addon_path
--               (parent-first, separators matching addon_path) and never any path
--               at or above addon_path. The retry write then succeeds.
--
--   commit warm path — when the first write_file succeeds, create_dir is never
--               called.
--
-- A regression guard replaces os.execute with a raiser: any shell-out fails the
-- run. All globals/providers are restored even if an assertion bails out.

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
local settings   = require('lib.settings.settings')
local write_file = settings._io_provider().write_file

-- os.tmpname() returns a path inside an existing temp directory. Its parent is a
-- guaranteed-existing home for the warm-path file.
math.randomseed(os.time())
local tmp       = os.tmpname()
os.remove(tmp)
local temp_dir  = tmp:match('^(.*)[/\\][^/\\]+$') or '.'
local stamp     = tostring(os.time()) .. '_' .. tostring(math.random(1, 1000000))
local warm_file = temp_dir .. '/lib_settings_warm_' .. stamp .. '.json'

-- Run body with os.execute guarded and globals/provider restored afterward.
local function with_guards(body)
  local saved_exec     = os.execute
  local saved_dir      = windower.create_dir
  local saved_player   = windower.ffxi._player
  local saved_provider = settings._io_provider()

  os.execute = function()
    error('os.execute must never be called')
  end

  local ok, err = pcall(body)

  os.execute          = saved_exec
  windower.create_dir = saved_dir
  windower.ffxi._player = saved_player
  settings._set_io_provider(saved_provider)

  if not ok then error(err, 0) end
end

local function cleanup()
  os.remove(warm_file)
end

-- ----

test('write_file warm path: existing dir → write succeeds, no create_dir, no shell-out', function()
  with_guards(function()
    local called = false
    windower.create_dir = function() called = true return true end

    write_file(warm_file, '{"label":"warm"}')

    assert_eq('{"label":"warm"}', read_all(warm_file), 'warm-path file content')
    assert(not called, 'create_dir must not be called when the directory exists')
  end)
end)

test('commit cold path: creates exactly data then data/<char> beneath addon_path, never above', function()
  with_guards(function()
    local addon_path = [[C:\Program Files (x86)\Windower4\addons\echo\]]
    windower.ffxi._player = { name = 'Mychar' }

    local created = {}
    -- Pure recorder: capture each requested path, create nothing on disk.
    windower.create_dir = function(dir)
      table.insert(created, dir)
      return true
    end

    -- write_file fails the first call (dir missing), succeeds afterward.
    local writes = 0
    settings._set_io_provider({
      read_file  = function() return nil end,
      write_file = function(path, content)
        writes = writes + 1
        if writes == 1 then
          error('cannot open for writing: ' .. path)
        end
      end,
    })

    settings.commit({ text = 'x' }, addon_path)

    local expected_data = [[C:\Program Files (x86)\Windower4\addons\echo\data]]
    local expected_char = [[C:\Program Files (x86)\Windower4\addons\echo\data\Mychar]]

    -- Exactly two creates, parent-first, backslash-uniform.
    assert_eq(2, #created, 'create_dir must be called exactly twice')
    assert_eq(expected_data, created[1], 'first create must be the data dir')
    assert_eq(expected_char, created[2], 'second create must be the per-character dir')

    -- Never C:, never a forward slash, never any path at/above addon_path.
    for _, dir in ipairs(created) do
      assert(dir ~= 'C:', 'must never create the drive root C:')
      assert(not dir:find('/', 1, true), 'no forward slash in: ' .. dir)
      assert(dir == expected_data or dir == expected_char,
        'must only create the two known subdirs, got: ' .. dir)
    end

    -- write_file was retried once after the dirs were created.
    assert_eq(2, writes, 'write_file should be attempted twice (fail then retry)')
  end)
end)

test('commit warm path: write succeeds first try → zero create_dir calls', function()
  with_guards(function()
    local addon_path = [[C:\Program Files (x86)\Windower4\addons\echo\]]
    windower.ffxi._player = { name = 'Mychar' }

    local created = {}
    windower.create_dir = function(dir)
      table.insert(created, dir)
      return true
    end

    local writes = 0
    settings._set_io_provider({
      read_file  = function() return nil end,
      write_file = function() writes = writes + 1 end,
    })

    settings.commit({ text = 'x' }, addon_path)

    assert_eq(0, #created, 'create_dir must not be called when the write succeeds')
    assert_eq(1, writes, 'write_file should be attempted exactly once')
  end)
end)

test('commit retry also fails: error propagates and the staging session survives (_in_setup stays true)', function()
  with_guards(function()
    local addon_path = [[C:\Program Files (x86)\Windower4\addons\echo\]]
    windower.ffxi._player = { name = 'Mychar' }

    -- An open staging session is the precondition: commit must NOT clear it on a
    -- failed save (no partial commit; staged changes survive).
    local staged = settings.open_setup({ text = '' })
    assert(settings.in_setup(), 'precondition: a staging session must be open')

    local created = {}
    windower.create_dir = function(dir)
      table.insert(created, dir)
      return true
    end

    -- Both the initial write and the post-create retry fail.
    local writes = 0
    settings._set_io_provider({
      read_file  = function() return nil end,
      write_file = function(path)
        writes = writes + 1
        error('cannot open for writing: ' .. path)
      end,
    })

    local ok = pcall(settings.commit, staged, addon_path)

    assert_eq(false, ok, 'commit must propagate the error when the retry write fails')
    assert(settings.in_setup(),
      'a failed save must preserve the staging session (_in_setup stays true)')
    assert_eq(2, writes, 'write_file should be attempted twice (fail then failed retry)')
    assert_eq(2, #created, 'ensure_char_dir must run, creating both subdirs')

    -- This test intentionally leaves _in_setup true; with_guards does not reset
    -- it, so drop the session here to avoid leaking into sibling tests.
    settings.discard()
    assert(not settings.in_setup(), 'cleanup: staging session must be dropped')
  end)
end)

test('commit cold path POSIX: creates exactly data then data/<char> with forward slashes', function()
  with_guards(function()
    local addon_path = '/opt/windower/addons/echo/'
    windower.ffxi._player = { name = 'Mychar' }

    local created = {}
    windower.create_dir = function(dir)
      table.insert(created, dir)
      return true
    end

    local writes = 0
    settings._set_io_provider({
      read_file  = function() return nil end,
      write_file = function(path, content)
        writes = writes + 1
        if writes == 1 then
          error('cannot open for writing: ' .. path)
        end
      end,
    })

    settings.commit({ text = 'x' }, addon_path)

    local expected_data = '/opt/windower/addons/echo/data'
    local expected_char = '/opt/windower/addons/echo/data/Mychar'

    assert_eq(2, #created, 'create_dir must be called exactly twice')
    assert_eq(expected_data, created[1], 'first create must be the data dir')
    assert_eq(expected_char, created[2], 'second create must be the per-character dir')

    -- Forward-slash-uniform: never a backslash anywhere.
    for _, dir in ipairs(created) do
      assert(not dir:find('\\', 1, true), 'no backslash in: ' .. dir)
      assert(dir == expected_data or dir == expected_char,
        'must only create the two known subdirs, got: ' .. dir)
    end

    assert_eq(2, writes, 'write_file should be attempted twice (fail then retry)')
  end)
end)

test('commit cold path: create_dir absent → ensure_char_dir guard early-returns, nothing created, error propagates', function()
  with_guards(function()
    local addon_path = '/opt/windower/addons/echo/'
    windower.ffxi._player = { name = 'Mychar' }
    windower.create_dir   = nil

    -- write_file always fails; with no create_dir the retry cannot recover.
    local writes = 0
    settings._set_io_provider({
      read_file  = function() return nil end,
      write_file = function(path)
        writes = writes + 1
        error('cannot open for writing: ' .. path)
      end,
    })

    local ok = pcall(settings.commit, { text = 'x' }, addon_path)

    assert_eq(false, ok, 'commit must propagate the error when no directory can be created')
    assert_eq(2, writes, 'write_file should be attempted twice (fail then failed retry)')
  end)
end)

-- ----

cleanup()
io.write(string.format('test_write_file: %d passed, %d failed\n', pass, fail))
if fail > 0 then
  error(fail .. ' test(s) failed in test_write_file.lua')
end
