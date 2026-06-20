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
local char_path  = addon_path .. 'data/TestChar/settings.json'

-- Ensure clean state between test files
settings.discard()

-- ----

test('in_setup is false before any session', function()
  assert_eq(false, settings.in_setup(), 'should start false')
end)

test('open_setup sets in_setup to true', function()
  settings.open_setup({ x = 1 })
  assert_eq(true, settings.in_setup(), 'should be true after open_setup')
  settings.discard()
end)

test('open_setup returns a deep copy — scalar mutation does not affect live', function()
  local live   = { x = 5 }
  local staged = settings.open_setup(live)
  staged.x = 99
  assert_eq(5, live.x, 'live.x must not change')
  settings.discard()
end)

test('open_setup returns a deep copy — nested mutation does not affect live', function()
  local live   = { pos = { x = 10, y = 20 } }
  local staged = settings.open_setup(live)
  staged.pos.x = 99
  assert_eq(10, live.pos.x, 'live.pos.x must not change')
  settings.discard()
end)

test('stage_set updates the staged table', function()
  local live   = { x = 1 }
  local staged = settings.open_setup(live)
  settings.stage_set(staged, 'x', 42)
  assert_eq(42, staged.x, 'staged.x should be updated')
  assert_eq(1,  live.x,   'live.x must not change')
  settings.discard()
end)

test('stage_set can add new keys to staged', function()
  local live   = { x = 1 }
  local staged = settings.open_setup(live)
  settings.stage_set(staged, 'new_key', 'hello')
  assert_eq('hello', staged.new_key, 'new key should be set')
  settings.discard()
end)

test('discard sets in_setup to false', function()
  settings.open_setup({ x = 1 })
  settings.discard()
  assert_eq(false, settings.in_setup(), 'in_setup should be false after discard')
end)

test('discard does not write anything', function()
  vfs = {}
  local staged = settings.open_setup({ x = 1 })
  settings.stage_set(staged, 'x', 99)
  settings.discard()
  assert_eq(nil, vfs[char_path], 'no file should be written after discard')
end)

test('commit writes staged values to the correct path', function()
  vfs = {}
  local staged = settings.open_setup({ x = 1, label = 'old' })
  settings.stage_set(staged, 'x', 7)
  settings.stage_set(staged, 'label', 'new')
  settings.commit(staged, addon_path)
  assert(vfs[char_path] ~= nil, 'settings file should exist after commit')
  local reloaded = settings.load(addon_path, {})
  assert_eq(7,     reloaded.x,     'committed x')
  assert_eq('new', reloaded.label, 'committed label')
end)

test('commit returns the new live table matching staged values', function()
  vfs = {}
  local staged   = settings.open_setup({ x = 1 })
  settings.stage_set(staged, 'x', 55)
  local new_live = settings.commit(staged, addon_path)
  assert_eq(55, new_live.x, 'returned live table should reflect staged value')
end)

test('commit returns a copy — mutation of result does not corrupt next load', function()
  vfs = {}
  local staged   = settings.open_setup({ x = 1 })
  local new_live = settings.commit(staged, addon_path)
  new_live.x = 999
  local reloaded = settings.load(addon_path, {})
  assert_eq(1, reloaded.x, 'disk value should be unchanged after mutating returned table')
end)

test('commit sets in_setup to false', function()
  vfs = {}
  local staged = settings.open_setup({ x = 1 })
  settings.commit(staged, addon_path)
  assert_eq(false, settings.in_setup(), 'in_setup should be false after commit')
end)

test('full session: open → stage → commit persists changes', function()
  vfs = {}
  local live   = settings.load(addon_path, { x = 0, y = 0 })
  local staged = settings.open_setup(live)
  assert_eq(true, settings.in_setup(), 'in setup')
  settings.stage_set(staged, 'x', 100)
  settings.stage_set(staged, 'y', 200)
  assert_eq(0, live.x, 'live unchanged during session')
  live = settings.commit(staged, addon_path)
  assert_eq(false, settings.in_setup(), 'not in setup after commit')
  assert_eq(100, live.x, 'x persisted')
  assert_eq(200, live.y, 'y persisted')
end)

test('full session: open → stage → discard leaves live unchanged', function()
  vfs = {}
  local live   = settings.load(addon_path, { x = 5 })
  local staged = settings.open_setup(live)
  settings.stage_set(staged, 'x', 999)
  settings.discard()
  assert_eq(5,   live.x,        'live unchanged after discard')
  assert_eq(nil, vfs[char_path], 'no file written after discard')
end)

-- ----

io.write(string.format('test_staging: %d passed, %d failed\n', pass, fail))
if fail > 0 then
  error(fail .. ' test(s) failed in test_staging.lua')
end
