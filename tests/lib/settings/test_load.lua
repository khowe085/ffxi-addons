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

-- ----

test('load returns defaults when no file exists', function()
  vfs = {}
  local result = settings.load(addon_path, { x = 10, y = 20, label = 'hi' })
  assert_eq(10,   result.x,     'x')
  assert_eq(20,   result.y,     'y')
  assert_eq('hi', result.label, 'label')
end)

test('load returns a copy of defaults, not the original table', function()
  vfs = {}
  local defaults = { x = 10 }
  local result = settings.load(addon_path, defaults)
  result.x = 99
  assert_eq(10, defaults.x, 'mutation of result must not affect defaults')
end)

test('load merges saved values over defaults', function()
  vfs = {}
  vfs[char_path] = '{"x":42,"label":"saved"}'
  local result = settings.load(addon_path, { x = 10, y = 20, label = 'default' })
  assert_eq(42,      result.x,     'x should come from file')
  assert_eq(20,      result.y,     'y should fall back to default')
  assert_eq('saved', result.label, 'label should come from file')
end)

test('load fills missing keys from defaults when file is partial', function()
  vfs = {}
  vfs[char_path] = '{"x":5}'
  local result = settings.load(addon_path, { x = 0, y = 0, z = 0 })
  assert_eq(5, result.x, 'x from file')
  assert_eq(0, result.y, 'y from default')
  assert_eq(0, result.z, 'z from default')
end)

test('load handles nested table defaults', function()
  vfs = {}
  local result = settings.load(addon_path, { pos = { x = 3, y = 7 } })
  assert_eq(3, result.pos.x, 'nested x')
  assert_eq(7, result.pos.y, 'nested y')
end)

test('load handles boolean and number values from file', function()
  vfs = {}
  vfs[char_path] = '{"visible":true,"opacity":0.75,"count":3}'
  local result = settings.load(addon_path, { visible = false, opacity = 1.0, count = 0 })
  assert_eq(true, result.visible, 'boolean true')
  assert_eq(0.75, result.opacity, 'float')
  assert_eq(3,    result.count,   'integer')
end)

-- ----

io.write(string.format('test_load: %d passed, %d failed\n', pass, fail))
if fail > 0 then
  error(fail .. ' test(s) failed in test_load.lua')
end
