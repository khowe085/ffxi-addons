local settings = require('lib.settings.settings')

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

-- In-memory filesystem for this test file
local vfs = {}
settings._set_io_provider({
  read_file  = function(path) return vfs[path] end,
  write_file = function(path, content) vfs[path] = content end,
})

local addon_path = '/addon/'

-- Ensure clean state between test files
settings.discard()

-- ----

test('logged_in is true when a player with a name is present', function()
  windower.ffxi._player = { name = 'TestChar' }
  assert_eq(true, settings.logged_in(), 'should be logged in')
end)

test('logged_in is false when get_player() returns nil', function()
  windower.ffxi._player = nil
  assert_eq(false, settings.logged_in(), 'should not be logged in')
end)

test('logged_in is false when player name is empty', function()
  windower.ffxi._player = { name = '' }
  assert_eq(false, settings.logged_in(), 'empty name is not logged in')
end)

test('load errors clearly when not logged in', function()
  windower.ffxi._player = nil
  local ok, err = pcall(settings.load, addon_path, { x = 1 })
  assert_eq(false, ok, 'load should error when not logged in')
  assert(tostring(err):find('logged in', 1, true) ~= nil, 'error must mention "logged in": ' .. tostring(err))
end)

test('commit errors clearly when not logged in', function()
  windower.ffxi._player = nil
  local ok, err = pcall(settings.commit, { x = 1 }, addon_path)
  assert_eq(false, ok, 'commit should error when not logged in')
  assert(tostring(err):find('logged in', 1, true) ~= nil, 'error must mention "logged in": ' .. tostring(err))
end)

test('load/commit resolve per-character paths (no cross-character clobber)', function()
  vfs = {}

  windower.ffxi._player = { name = 'Alpha' }
  local staged = settings.open_setup({ x = 1 })
  settings.stage_set(staged, 'x', 11)
  settings.commit(staged, addon_path)

  windower.ffxi._player = { name = 'Beta' }
  local b = settings.load(addon_path, { x = 0 })
  assert_eq(0, b.x, 'Beta has no file -> defaults')

  windower.ffxi._player = { name = 'Alpha' }
  local a = settings.load(addon_path, { x = 0 })
  assert_eq(11, a.x, 'Alpha file intact')

  assert(vfs['/addon/data/Alpha/settings.json'] ~= nil, 'Alpha file should exist')
  assert(vfs['/addon/data/Beta/settings.json'] == nil, 'Beta file should not exist')
end)

-- ----

-- Restore default so later test files are unaffected
windower.ffxi._player = { name = 'TestChar' }
settings.discard()

io.write(string.format('test_login: %d passed, %d failed\n', pass, fail))
if fail > 0 then
  error(fail .. ' test(s) failed in test_login.lua')
end
