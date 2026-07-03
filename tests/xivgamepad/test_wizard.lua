-- Tests for xivgamepad/wizard.lua: the full capture walk (14 required plus
-- skippable optional buttons), ctrl-pair capture, collision rejection naming
-- the owner, d-pad trigger gating (with held-state tracking from the raw
-- stream), back(), skip(), and cancel-leaves-mapping-untouched.

local log_stub = { _lines = {} }
log_stub.debug = function(fmt, ...) table.insert(log_stub._lines, tostring(fmt)) end
log_stub.info  = log_stub.debug
log_stub.error = log_stub.debug
package.loaded['xivgamepad.log'] = log_stub

local wizard = require('xivgamepad.wizard')

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

-- The contract's default key_mapping (DIK codes).
local function default_mapping()
  return {
    LT = { code = 2 }, RT = { code = 3 }, LB = { code = 4 }, RB = { code = 5 },
    A = { code = 6 }, B = { code = 7 }, X = { code = 8 }, Y = { code = 9 },
    DPAD_UP = { code = 10 }, DPAD_RIGHT = { code = 11 },
    DPAD_DOWN = { code = 41 }, DPAD_LEFT = { code = 13 },
    BACK = { code = 2, ctrl = true }, START = { code = 3, ctrl = true },
    TRACKPAD_1 = { code = 4, ctrl = true }, TRACKPAD_2 = { code = 5, ctrl = true },
    TRACKPAD_3 = { code = 6, ctrl = true }, TRACKPAD_4 = { code = 7, ctrl = true },
    TRACKPAD_5 = { code = 8, ctrl = true }, TRACKPAD_6 = { code = 9, ctrl = true },
    TRACKPAD_7 = { code = 10, ctrl = true }, TRACKPAD_8 = { code = 11, ctrl = true },
    L4 = { code = 67 }, L5 = { code = 68 }, R4 = { code = 87 }, R5 = { code = 88 },
  }
end

local finished
local cancelled

local function start(mapping)
  wizard.cancel()
  finished = nil
  cancelled = 0
  wizard.start({
    current_mapping = mapping,
    on_finish       = function(m) finished = m end,
    on_cancel       = function() cancelled = cancelled + 1 end,
    texts           = texts,
  })
end

-- Feed the 14 required captures matching the default mapping (LT re-pressed
-- and held for the d-pad chord steps).
local function feed_required_defaults()
  wizard.on_raw_key(2, false)
  wizard.on_raw_key(3, false)
  wizard.on_raw_key(4, false)
  wizard.on_raw_key(5, false)
  wizard.on_raw_key(2, true)
  wizard.on_raw_key(3, true)
  wizard.on_raw_key(6, false)
  wizard.on_raw_key(7, false)
  wizard.on_raw_key(8, false)
  wizard.on_raw_key(9, false)
  wizard.on_raw_key(2, false)
  wizard.on_raw_key(10, false)
  wizard.on_raw_key(11, false)
  wizard.on_raw_key(41, false)
  wizard.on_raw_key(13, false)
end

-- ---- Guards ----

test('inactive wizard ignores every entry point', function()
  wizard.cancel()
  assert_eq(false, wizard.is_active(), 'inactive before start')
  wizard.on_raw_key(2, false)
  wizard.skip()
  wizard.back()
  wizard.cancel()
  assert_eq(false, wizard.is_active(), 'still inactive')
end)

test('start opens the session at LT and shows the prompt', function()
  start(default_mapping())
  assert_eq(true, wizard.is_active(), 'active after start')
  assert_eq('LT', wizard._current_button_for_test(), 'first button is LT')
  assert_true(wizard._prompt_text_for_test():find('LT', 1, true) ~= nil, 'prompt names LT')
end)

test('start again restarts the session from the beginning', function()
  start(default_mapping())
  wizard.on_raw_key(2, false)
  assert_eq('RT', wizard._current_button_for_test(), 'advanced to RT')
  start(default_mapping())
  assert_eq('LT', wizard._current_button_for_test(), 'restart returns to LT')
end)

-- ---- Happy path ----

test('full required walk plus optional skips finishes with the completed mapping', function()
  local mapping = default_mapping()
  start(mapping)
  feed_required_defaults()
  assert_eq('L4', wizard._current_button_for_test(), 'optional buttons follow the d-pad')
  for _ = 1, 12 do
    wizard.skip()
  end
  assert_eq(false, wizard.is_active(), 'session closed on finish')
  assert_true(finished ~= nil, 'on_finish called')
  assert_eq(2, finished.LT.code, 'LT captured')
  assert_eq(3, finished.RT.code, 'RT captured')
  assert_eq(4, finished.LB.code, 'LB captured')
  assert_eq(5, finished.RB.code, 'RB captured')
  assert_eq(2, finished.BACK.code, 'BACK captured')
  assert_eq(true, finished.BACK.ctrl, 'BACK ctrl recorded')
  assert_eq(true, finished.START.ctrl, 'START ctrl recorded')
  assert_eq(nil, finished.A.ctrl, 'bare capture omits ctrl')
  assert_eq(6, finished.A.code, 'A captured')
  assert_eq(10, finished.DPAD_UP.code, 'DPAD_UP captured')
  assert_eq(41, finished.DPAD_DOWN.code, 'DPAD_DOWN captured')
  assert_eq(13, finished.DPAD_LEFT.code, 'DPAD_LEFT captured')
  assert_eq(67, finished.L4.code, 'skip keeps the pre-loaded optional value')
  assert_eq(88, finished.R5.code, 'trailing optional value kept')
  assert_true(finished ~= mapping, 'finished mapping is a staging copy')
end)

test('an optional button can be captured instead of skipped', function()
  start(default_mapping())
  feed_required_defaults()
  wizard.on_raw_key(70, false)
  assert_eq('L5', wizard._current_button_for_test(), 'L4 capture advances')
  for _ = 1, 11 do
    wizard.skip()
  end
  assert_eq(70, finished.L4.code, 'captured optional value kept')
  assert_eq(68, finished.L5.code, 'skipped optional value kept')
end)

-- ---- Collisions ----

test('a key captured earlier this session is rejected naming its owner', function()
  start(default_mapping())
  wizard.on_raw_key(2, false)
  wizard.on_raw_key(2, false)
  assert_eq('RT', wizard._current_button_for_test(), 'RT re-prompted after collision')
  assert_true(wizard._status_for_test():find('LT', 1, true) ~= nil, 'owner named')
  assert_true(wizard._prompt_text_for_test():find('LT', 1, true) ~= nil, 'status rendered')
  wizard.on_raw_key(3, false)
  assert_eq('LB', wizard._current_button_for_test(), 'different key accepted')
end)

test('a key remaining in the staged mapping is rejected naming its owner', function()
  start(default_mapping())
  wizard.on_raw_key(4, false)
  assert_eq('LT', wizard._current_button_for_test(), 'LT re-prompted')
  assert_true(wizard._status_for_test():find('LB', 1, true) ~= nil, 'staged owner named')
end)

test('re-pressing the current button\'s own key re-confirms it', function()
  start(default_mapping())
  wizard.on_raw_key(2, false)
  assert_eq('RT', wizard._current_button_for_test(), 'own prior key accepted')
  assert_eq(2, wizard._staged_for_test().LT.code, 'value unchanged')
end)

test('the same code with a different ctrl state is not a collision', function()
  start(default_mapping())
  feed_required_defaults()
  assert_eq(2, wizard._staged_for_test().BACK.code, 'BACK shares LT code under ctrl')
  assert_eq(true, wizard._staged_for_test().BACK.ctrl, 'distinguished by ctrl')
end)

-- ---- D-pad trigger gating ----

test('d-pad keys are rejected with guidance until a captured trigger is held', function()
  start({})
  wizard.on_raw_key(20, false)
  wizard.on_raw_key(21, false)
  wizard.on_raw_key(22, false)
  wizard.on_raw_key(23, false)
  wizard.on_raw_key(24, false)
  wizard.on_raw_key(25, false)
  wizard.on_raw_key(26, false)
  wizard.on_raw_key(27, false)
  wizard.on_raw_key(28, false)
  wizard.on_raw_key(40, false)
  assert_eq('DPAD_UP', wizard._current_button_for_test(), 'at the first d-pad step')
  assert_true(wizard._prompt_text_for_test():find('Hold LT', 1, true) ~= nil,
    'prompt carries the hold guidance')
  wizard.on_raw_key(30, false)
  assert_eq('DPAD_UP', wizard._current_button_for_test(), 'bare key rejected')
  assert_true(wizard._status_for_test():find('Hold LT', 1, true) ~= nil, 'guidance status set')
  assert_eq(nil, wizard._staged_for_test().DPAD_UP, 'nothing captured')
  wizard.on_raw_key(20, false)
  assert_eq('DPAD_UP', wizard._current_button_for_test(), 'trigger press is not a capture')
  wizard.on_raw_key(30, false)
  assert_eq('DPAD_RIGHT', wizard._current_button_for_test(), 'accepted while LT held')
  assert_eq(30, wizard._staged_for_test().DPAD_UP.code, 'd-pad key captured')
end)

test('trigger release re-gates the d-pad; RB also anchors', function()
  start({})
  wizard.on_raw_key(20, false)
  wizard.on_raw_key(21, false)
  wizard.on_raw_key(22, false)
  wizard.on_raw_key(23, false)
  wizard.on_raw_key(24, false)
  wizard.on_raw_key(25, false)
  wizard.on_raw_key(26, false)
  wizard.on_raw_key(27, false)
  wizard.on_raw_key(28, false)
  wizard.on_raw_key(40, false)
  wizard.on_raw_key(20, false)
  wizard.on_raw_key(30, false)
  assert_eq('DPAD_RIGHT', wizard._current_button_for_test(), 'DPAD_UP captured under LT')
  wizard.on_raw_key(20, false, false)
  wizard.on_raw_key(31, false)
  assert_eq('DPAD_RIGHT', wizard._current_button_for_test(), 'rejected after LT release')
  wizard.on_raw_key(23, false)
  wizard.on_raw_key(31, false)
  assert_eq('DPAD_DOWN', wizard._current_button_for_test(), 'accepted under held RB')
  assert_eq(31, wizard._staged_for_test().DPAD_RIGHT.code, 'captured under the RB anchor')
end)

-- ---- Skip / back ----

test('skip is refused on required buttons', function()
  start(default_mapping())
  wizard.skip()
  assert_eq('LT', wizard._current_button_for_test(), 'still on LT')
  assert_true(wizard._status_for_test():find('required', 1, true) ~= nil, 'refusal explained')
  assert_eq(true, wizard.is_active(), 'session still open')
end)

test('back restores the previous button\'s prior value and frees its code', function()
  start(default_mapping())
  wizard.on_raw_key(2, false)
  wizard.on_raw_key(30, false)
  assert_eq('LB', wizard._current_button_for_test(), 'RT captured as 30')
  wizard.back()
  assert_eq('RT', wizard._current_button_for_test(), 'backed up to RT')
  assert_eq(3, wizard._staged_for_test().RT.code, 'prior value restored')
  wizard.on_raw_key(31, false)
  assert_eq('LB', wizard._current_button_for_test(), 'RT re-captured')
  assert_eq(31, wizard._staged_for_test().RT.code, 'new value staged')
  wizard.on_raw_key(30, false)
  assert_eq(30, wizard._staged_for_test().LB.code, 'code 30 freed by back and reusable')
end)

test('back at the first step is a no-op', function()
  start(default_mapping())
  wizard.back()
  assert_eq('LT', wizard._current_button_for_test(), 'still on LT')
  assert_eq(true, wizard.is_active(), 'session still open')
end)

-- ---- Cancel ----

test('cancel fires on_cancel and leaves the prior mapping untouched', function()
  local mapping = default_mapping()
  start(mapping)
  wizard.on_raw_key(99, false)
  assert_eq(99, wizard._staged_for_test().LT.code, 'staged copy holds the capture')
  wizard.cancel()
  assert_eq(1, cancelled, 'on_cancel called')
  assert_eq(nil, finished, 'on_finish not called')
  assert_eq(false, wizard.is_active(), 'session closed')
  assert_eq(2, mapping.LT.code, 'caller mapping untouched')
  wizard.on_raw_key(50, false)
  assert_eq(false, wizard.is_active(), 'raw keys ignored after cancel')
end)

-- ---- Ctrl key handling ----

test('ctrl DIK codes themselves are never captured', function()
  start(default_mapping())
  wizard.on_raw_key(29, false)
  wizard.on_raw_key(157, false)
  assert_eq('LT', wizard._current_button_for_test(), 'ctrl keys ignored')
  wizard.on_raw_key(2, false)
  assert_eq('RT', wizard._current_button_for_test(), 'capture proceeds normally')
end)

-- ----

wizard.cancel()
windower._reset()

io.write(string.format('test_wizard: %d passed, %d failed\n', pass, fail))
if fail > 0 then
  error(fail .. ' test(s) failed in test_wizard.lua')
end
