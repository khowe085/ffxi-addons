-- Tests for xivgamepad/tester.lua: open/close/is_open, the live button grid,
-- and the bounded scrolling gesture log.

local log_stub = { _lines = {} }
log_stub.debug = function(fmt, ...) table.insert(log_stub._lines, tostring(fmt)) end
log_stub.info  = log_stub.debug
log_stub.error = log_stub.debug
package.loaded['xivgamepad.log'] = log_stub

local tester = require('xivgamepad.tester')

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

local function assert_true(v, msg)
  if not v then error(msg or 'expected true', 2) end
end

local function fresh()
  tester.destroy()
  windower._reset()
  tester.init({ texts = texts })
end

-- ---- Guards ----

test('events before init are safe no-ops', function()
  tester.destroy()
  tester.on_button_event('LT', true)
  tester.on_gesture('auto_run', {})
  tester.close()
  tester.open()
  assert_eq(false, tester.is_open(), 'not open before init')
end)

test('init is idempotent: re-init reuses elements', function()
  fresh()
  tester.open()
  tester.on_button_event('LT', true)
  tester.init({ texts = texts })
  assert_eq(true, tester.is_open(), 'open state survives re-init')
  assert_true(tester._grid_text_for_test():find('[X] LT', 1, true) ~= nil,
    'button state survives re-init')
end)

-- ---- Open / close ----

test('open and close toggle is_open and element visibility', function()
  fresh()
  assert_eq(false, tester.is_open(), 'closed after init')
  tester.open()
  assert_eq(true, tester.is_open(), 'open after open()')
  tester.close()
  assert_eq(false, tester.is_open(), 'closed after close()')
end)

-- ---- Button grid ----

test('button grid reflects press and release', function()
  fresh()
  tester.open()
  assert_true(tester._grid_text_for_test():find('[ ] LT', 1, true) ~= nil, 'LT starts released')
  tester.on_button_event('LT', true)
  assert_true(tester._grid_text_for_test():find('[X] LT', 1, true) ~= nil, 'LT pressed')
  assert_true(tester._grid_text_for_test():find('[ ] RT', 1, true) ~= nil, 'RT still released')
  tester.on_button_event('LT', false)
  assert_true(tester._grid_text_for_test():find('[ ] LT', 1, true) ~= nil, 'LT released')
  tester.on_button_event('TRACKPAD_8', true)
  assert_true(tester._grid_text_for_test():find('[X] TRACKPAD_8', 1, true) ~= nil,
    'extended buttons tracked')
end)

test('events received while closed appear when opened', function()
  fresh()
  tester.on_button_event('RB', true)
  tester.on_gesture('cycle_set', {})
  tester.open()
  assert_true(tester._grid_text_for_test():find('[X] RB', 1, true) ~= nil,
    'state accumulated while closed')
  assert_true(tester._log_text_for_test():find('cycle_set', 1, true) ~= nil,
    'gestures accumulated while closed')
end)

-- ---- Gesture log ----

test('gesture log formats id and sorted params', function()
  fresh()
  tester.open()
  tester.on_gesture('execute_slot', { slot = 3, display_mode = 'xhb_l' })
  local lines = tester._log_lines_for_test()
  assert_eq('execute_slot (display_mode=xhb_l, slot=3)', lines[#lines], 'params sorted by key')
  tester.on_gesture('auto_run', {})
  lines = tester._log_lines_for_test()
  assert_eq('auto_run', lines[#lines], 'empty params render as the bare id')
  assert_true(tester._log_text_for_test():find('execute_slot', 1, true) ~= nil,
    'log element shows entries')
end)

test('gesture log stays bounded, dropping the oldest entries', function()
  fresh()
  tester.open()
  for i = 1, 15 do
    tester.on_gesture('g' .. i, {})
  end
  local lines = tester._log_lines_for_test()
  assert_eq(10, #lines, 'log capped at 10 entries')
  assert_eq('g6', lines[1], 'oldest surviving entry is the 6th')
  assert_eq('g15', lines[10], 'newest entry kept')
  assert_true(tester._log_text_for_test():find('g5', 1, true) == nil, 'dropped entry gone')
end)

-- ---- Destroy ----

test('destroy tears down and init rebuilds', function()
  fresh()
  tester.open()
  tester.destroy()
  assert_eq(false, tester.is_open(), 'not open after destroy')
  tester.destroy()
  tester.init({ texts = texts })
  tester.open()
  assert_eq(true, tester.is_open(), 'rebuilt after destroy')
end)

-- ----

tester.destroy()
windower._reset()

io.write(string.format('test_tester: %d passed, %d failed\n', pass, fail))
if fail > 0 then
  error(fail .. ' test(s) failed in test_tester.lua')
end
