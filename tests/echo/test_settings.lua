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

local char_path = '/addon/data/TestChar/settings.json'

-- Isolated echo instance + clean state per test
local function fresh()
  windower.ffxi._player = { name = 'TestChar' }
  vfs = {}
  settings.discard()
  local e = dofile('echo/echo.lua')
  e.init()
  return e
end

-- ----

test('load returns defaults when no file exists', function()
  local e = fresh()
  assert_eq('', e.get_live().text,  'text default')
  assert_eq(0,  e.get_live().pos_x, 'pos_x default')
  assert_eq(0,  e.get_live().pos_y, 'pos_y default')
end)

test('setup_open deep-copies live into staged; mutating staged does not affect live', function()
  local e = fresh()
  e.setup_open()
  local s = e.get_staged()
  s.pos_x = 99
  assert_eq(0, e.get_live().pos_x, 'live.pos_x must not change')
end)

test('change_pos updates staged pos_x/pos_y and the element; live unchanged', function()
  local e = fresh()
  e.setup_open()
  e.change_pos(50, 60)
  assert_eq(50, e.get_staged().pos_x, 'staged.pos_x')
  assert_eq(60, e.get_staged().pos_y, 'staged.pos_y')
  assert_eq(0,  e.get_live().pos_x,   'live.pos_x unchanged')
  assert_eq(0,  e.get_live().pos_y,   'live.pos_y unchanged')
  assert_eq(50, e.get_element()._x,   'element x')
  assert_eq(60, e.get_element()._y,   'element y')
end)

test('exit (save) commits staged to the vfs and returns as new live', function()
  local e = fresh()
  e.setup_open()
  e.change_pos(50, 60)
  e.setup_close_save()
  assert_eq(50, e.get_live().pos_x, 'live.pos_x after save')
  assert(vfs[char_path] ~= nil, 'settings file should exist after save')
  local reloaded = settings.load('/addon/', {})
  assert_eq(50, reloaded.pos_x, 'reloaded pos_x from disk')
  assert_eq(nil, e.get_staged(), 'staged should be nil after save')
  assert_eq(false, settings.in_setup(), 'in_setup false after save')
end)

test('exit -d discards: vfs unchanged, staged nil, live unchanged', function()
  local e = fresh()
  e.setup_open()
  e.change_pos(50, 60)
  e.setup_close_discard()
  assert_eq(0, e.get_live().pos_x, 'live.pos_x unchanged after discard')
  assert_eq(nil, e.get_staged(), 'staged should be nil after discard')
  assert_eq(nil, vfs[char_path], 'no file written after discard')
  assert_eq(false, settings.in_setup(), 'in_setup false after discard')
end)

test('on_mouse stages element position on mouse-up while in setup', function()
  local e = fresh()
  e.setup_open()
  local el = e.get_element()
  el._x = 120
  el._y = 250
  e.on_mouse(3, 0, 0)
  assert_eq(120, e.get_staged().pos_x, 'staged.pos_x from element on mouse-up')
  assert_eq(250, e.get_staged().pos_y, 'staged.pos_y from element on mouse-up')
end)

test('on_mouse is a no-op when not in setup', function()
  local e = fresh()
  local ok = pcall(function() e.on_mouse(3, 10, 20) end)
  assert_eq(true, ok, 'on_mouse must not error when not in setup')
  assert_eq(nil, e.get_staged(), 'staged should remain nil when not in setup')
end)

test('on_mouse ignores non-mouse-up events while in setup', function()
  local e = fresh()
  e.setup_open()
  local before_x = e.get_staged().pos_x
  e.on_mouse(1, 999, 999)
  assert_eq(before_x, e.get_staged().pos_x, 'staged.pos_x unchanged on non-up event')
end)

test('reload restores text and position from disk', function()
  vfs = {}
  settings.discard()
  local e1 = dofile('echo/echo.lua'); e1.init()
  e1.cmd_set('Persisted')
  e1.setup_open(); e1.change_pos(33, 44); e1.setup_close_save()
  local e2 = dofile('echo/echo.lua'); e2.init()
  assert_eq('Persisted', e2.get_live().text, 'text restored')
  assert_eq(33, e2.get_live().pos_x, 'pos_x restored')
  assert_eq(44, e2.get_live().pos_y, 'pos_y restored')
  assert_eq('Persisted', e2.get_element()._text, 'element shows restored text')
end)

-- ----

io.write(string.format('test_settings: %d passed, %d failed\n', pass, fail))
if fail > 0 then
  error(fail .. ' test(s) failed in test_settings.lua')
end
