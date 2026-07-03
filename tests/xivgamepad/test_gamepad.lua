-- Preload a logger stub before requiring the module under test: the real
-- log module is built in a parallel task and must never be stubbed in the
-- shared mock (.planning/xivgamepad-contracts.md).
package.loaded['log'] = {
  init      = function() end,
  debug     = function() end,
  info      = function() end,
  error     = function() end,
  set_debug = function() end,
  toggle    = function() return false end,
  is_debug  = function() return false end,
}

local gamepad = require('gamepad')

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

-- Local fake scheduler: presses queue one-shot timers; run_timers drains the
-- queue in order, simulating all pending thresholds/windows elapsing.
local queue
local fired
local displays

local function run_timers()
  local guard = 0
  while #queue > 0 do
    guard = guard + 1
    if guard > 1000 then
      error('runaway scheduler loop', 2)
    end
    local entry = table.remove(queue, 1)
    entry.fn()
  end
end

local function setup(gestures)
  queue = {}
  gamepad.set_gesture_callback(nil)
  gamepad.set_display_callback(nil)
  gamepad.reset()
  gamepad.init({
    schedule = function(fn, seconds)
      queue[#queue + 1] = { fn = fn, at = seconds }
    end,
  })
  gamepad.set_gestures(gestures or gamepad.default_gestures())
  fired = {}
  displays = {}
  gamepad.set_gesture_callback(function(id, params)
    fired[#fired + 1] = { id = id, params = params }
  end)
  gamepad.set_display_callback(function(mode)
    displays[#displays + 1] = mode or 'idle'
  end)
end

local function run_next_timer()
  local entry = table.remove(queue, 1)
  entry.fn()
end

local function press(button)
  gamepad.on_button_event(button, true)
end

local function release(button)
  gamepad.on_button_event(button, false)
end

local function display_seq()
  return table.concat(displays, ' ')
end

local function fired_seq()
  local parts = {}
  for _, f in ipairs(fired) do
    parts[#parts + 1] = f.id
  end
  return table.concat(parts, ' ')
end

-- ---- Display state machine

test('hold LT engages xhb_l and release returns to idle', function()
  setup()
  press('LT')
  assert_eq(nil, gamepad.get_display_mode(), 'not engaged before min_hold')
  run_timers()
  assert_eq('xhb_l', gamepad.get_display_mode(), 'engaged after min_hold')
  run_timers()
  assert_eq('xhb_l', display_seq(), 'exactly one engage transition')
  release('LT')
  assert_eq(nil, gamepad.get_display_mode(), 'idle after release')
  assert_eq('xhb_l idle', display_seq(), 'both transitions reported')
  assert_eq('', fired_seq(), 'display gestures never hit the gesture callback')
end)

test('hold RT engages xhb_r', function()
  setup()
  press('RT')
  run_timers()
  assert_eq('xhb_r', gamepad.get_display_mode(), 'right trigger shows right half')
  release('RT')
  assert_eq('xhb_r idle', display_seq(), 'transitions reported')
end)

test('hold released before min_hold never engages', function()
  setup()
  press('LT')
  release('LT')
  run_timers()
  assert_eq(nil, gamepad.get_display_mode(), 'stale timers are inert')
  assert_eq('', display_seq(), 'no transitions')
  assert_eq('', fired_seq(), 'no gestures')
end)

test('LT then RT transitions to expand_lt_rt', function()
  setup()
  press('LT')
  run_timers()
  press('RT')
  run_timers()
  assert_eq('expand_lt_rt', gamepad.get_display_mode(), 'expanded engaged')
  assert_eq('xhb_l expand_lt_rt', display_seq(), 'transition path reported')
end)

test('expanded second-trigger release returns to the anchor XHB', function()
  setup()
  press('LT')
  run_timers()
  press('RT')
  run_timers()
  release('RT')
  assert_eq('xhb_l', gamepad.get_display_mode(), 'anchor XHB restored')
  release('LT')
  assert_eq('xhb_l expand_lt_rt xhb_l idle', display_seq(), 'full path reported')
end)

test('expanded anchor release transitions to the other trigger XHB', function()
  setup()
  press('LT')
  run_timers()
  press('RT')
  run_timers()
  release('LT')
  assert_eq('xhb_r', gamepad.get_display_mode(), 'held trigger takes over')
  release('RT')
  assert_eq('xhb_l expand_lt_rt xhb_r idle', display_seq(), 'full path reported')
end)

test('RT then LT engages expand_rt_lt with RT as anchor', function()
  setup()
  press('RT')
  run_timers()
  press('LT')
  run_timers()
  assert_eq('expand_rt_lt', gamepad.get_display_mode(), 'reverse order expanded')
  release('LT')
  assert_eq('xhb_r', gamepad.get_display_mode(), 'anchor is RT')
  release('RT')
  assert_eq('xhb_r expand_rt_lt xhb_r idle', display_seq(), 'full path reported')
end)

test('rapid release-rehold of the second trigger re-expands', function()
  setup()
  press('LT')
  run_timers()
  press('RT')
  run_timers()
  release('RT')
  press('RT')
  run_timers()
  assert_eq('expand_lt_rt', gamepad.get_display_mode(), 're-engaged')
  assert_eq('xhb_l expand_lt_rt xhb_l expand_lt_rt', display_seq(), 'path reported')
end)

test('both triggers pressed together expand with the first as anchor', function()
  setup()
  press('LT')
  press('RT')
  run_timers()
  assert_eq('expand_lt_rt', gamepad.get_display_mode(), 'LT pressed first anchors')
  release('LT')
  assert_eq('xhb_r', gamepad.get_display_mode(), 'anchor release falls to RT')
end)

test('anchor release inside the pending window falls back once the second trigger matures', function()
  setup()
  press('LT')
  run_timers()
  press('RT')
  release('LT')
  assert_eq(nil, gamepad.get_display_mode(), 'second trigger not yet past its min_hold')
  run_timers()
  assert_eq('xhb_r', gamepad.get_display_mode(), 'surviving trigger falls back to its XHB')
  release('RT')
  assert_eq('xhb_l idle xhb_r idle', display_seq(), 'deterministic fallback path')
end)

test('anchor release after the second trigger matured falls back immediately', function()
  setup()
  press('LT')
  run_timers()
  press('RT')
  run_next_timer()
  run_next_timer()
  assert_eq('xhb_l', gamepad.get_display_mode(), 'still on the anchor XHB before release')
  release('LT')
  assert_eq('xhb_r', gamepad.get_display_mode(), 'immediate fallback on anchor release')
  run_timers()
  assert_eq('xhb_r', gamepad.get_display_mode(), 'the stale expanded pending cannot re-engage')
  release('RT')
  assert_eq('xhb_l idle xhb_r idle', display_seq(), 'deterministic fallback path')
end)

test('paddle wxhb_l engages from xhb_l and paddle release drops back', function()
  setup()
  press('LT')
  run_timers()
  press('L4')
  run_timers()
  assert_eq('wxhb_l', gamepad.get_display_mode(), 'LT+L4 shows WXHB-L')
  release('L4')
  assert_eq('xhb_l', gamepad.get_display_mode(), 'paddle release drops to XHB-L')
  press('L4')
  run_timers()
  assert_eq('wxhb_l', gamepad.get_display_mode(), 'paddle re-hold re-engages')
  release('LT')
  assert_eq(nil, gamepad.get_display_mode(), 'trigger release ends the display')
  release('L4')
  assert_eq('xhb_l wxhb_l xhb_l wxhb_l idle', display_seq(), 'full path reported')
end)

test('paddle wxhb_r engages via RT+R4', function()
  setup()
  press('RT')
  run_timers()
  press('R4')
  run_timers()
  assert_eq('wxhb_r', gamepad.get_display_mode(), 'RT+R4 shows WXHB-R')
  release('RT')
  assert_eq('xhb_r wxhb_r idle', display_seq(), 'trigger release ends the display')
end)

test('the wrong-trigger paddle does not engage wxhb', function()
  setup()
  press('RT')
  run_timers()
  press('L4')
  run_timers()
  assert_eq('xhb_r', gamepad.get_display_mode(), 'RT+L4 stays on XHB-R')
  assert_eq('xhb_r', display_seq(), 'no spurious transition')
end)

test('quick paddle release below min_hold_second never engages', function()
  setup()
  press('LT')
  run_timers()
  press('L4')
  release('L4')
  run_timers()
  assert_eq('xhb_l', gamepad.get_display_mode(), 'wxhb not engaged')
  assert_eq('xhb_l', display_seq(), 'no transition recorded')
end)

test('double-tap LT engages wxhb_l', function()
  setup()
  press('LT')
  release('LT')
  press('LT')
  run_timers()
  assert_eq('wxhb_l', gamepad.get_display_mode(), 'double-tap-hold shows WXHB-L')
  release('LT')
  assert_eq('wxhb_l idle', display_seq(), 'release returns to idle')
end)

test('double-tap RT engages wxhb_r', function()
  setup()
  press('RT')
  release('RT')
  press('RT')
  run_timers()
  assert_eq('wxhb_r', gamepad.get_display_mode(), 'double-tap-hold shows WXHB-R')
end)

test('re-press outside max_gap engages the plain XHB', function()
  setup()
  press('LT')
  release('LT')
  run_timers()
  press('LT')
  run_timers()
  assert_eq('xhb_l', gamepad.get_display_mode(), 'gap expired so no WXHB')
  release('LT')
  assert_eq('xhb_l idle', display_seq(), 'plain hold path only')
end)

test('double-tap second press released before min_hold engages nothing', function()
  setup()
  press('LT')
  release('LT')
  press('LT')
  release('LT')
  run_timers()
  assert_eq(nil, gamepad.get_display_mode(), 'nothing engaged')
  assert_eq('', display_seq(), 'no transitions')
end)

test('a failed short second tap re-arms the gap for a third press', function()
  setup()
  press('LT')
  release('LT')
  press('LT')
  release('LT')
  assert_eq(nil, gamepad.get_display_mode(), 'short second press engaged nothing')
  press('LT')
  run_timers()
  assert_eq('wxhb_l', gamepad.get_display_mode(),
    'third press within the re-armed gap engages WXHB')
  release('LT')
  assert_eq('wxhb_l idle', display_seq(), 'clean engage and release')
end)

test('reset drops display state and reports idle', function()
  setup()
  press('LT')
  run_timers()
  assert_eq('xhb_l', gamepad.get_display_mode(), 'engaged before reset')
  gamepad.reset()
  assert_eq(nil, gamepad.get_display_mode(), 'idle after reset')
  assert_eq('xhb_l idle', display_seq(), 'reset reports the transition')
  release('LT')
  assert_eq('xhb_l idle', display_seq(), 'stale release is ignored after reset')
  press('LT')
  run_timers()
  assert_eq('xhb_l', gamepad.get_display_mode(), 're-engages cleanly after reset')
end)

-- ---- Slot execution

test('execute_slot addresses d-pad 1-4 and faces 5-8 of the displayed half', function()
  setup()
  press('LT')
  run_timers()
  local order = { 'DPAD_UP', 'DPAD_RIGHT', 'DPAD_DOWN', 'DPAD_LEFT', 'A', 'B', 'X', 'Y' }
  for _, button in ipairs(order) do
    press(button)
    release(button)
  end
  assert_eq(8, #fired, 'one action per press')
  for slot, f in ipairs(fired) do
    assert_eq('execute_slot', f.id, 'reserved slot gesture id')
    assert_eq('xhb_l', f.params.display_mode, 'params carry the display mode')
    assert_eq(slot, f.params.slot, 'frozen positional order')
  end
end)

test('execute_slot reports the right half in xhb_r', function()
  setup()
  press('RT')
  run_timers()
  press('X')
  assert_eq(1, #fired, 'one action')
  assert_eq('execute_slot', fired[1].id, 'slot gesture')
  assert_eq('xhb_r', fired[1].params.display_mode, 'right half mode')
  assert_eq(7, fired[1].params.slot, 'X is slot 7')
end)

test('execute_slot reports expanded and wxhb modes', function()
  setup()
  press('LT')
  run_timers()
  press('RT')
  run_timers()
  press('B')
  assert_eq('expand_lt_rt', fired[1].params.display_mode, 'expanded mode in params')
  assert_eq(6, fired[1].params.slot, 'B is slot 6')
  release('B')
  release('RT')
  release('LT')
  setup()
  press('LT')
  release('LT')
  press('LT')
  run_timers()
  press('DPAD_UP')
  assert_eq('wxhb_l', fired[1].params.display_mode, 'wxhb mode in params')
  assert_eq(1, fired[1].params.slot, 'DPAD_UP is slot 1')
end)

test('a face press before the display engages does nothing', function()
  setup()
  press('LT')
  press('A')
  assert_eq('', fired_seq(), 'no display half to address yet')
  release('A')
  release('LT')
  run_timers()
  assert_eq('', fired_seq(), 'nothing fires later either')
end)

test('duplicate press events do not double-fire a slot', function()
  setup()
  press('LT')
  run_timers()
  press('A')
  press('A')
  assert_eq(1, #fired, 'second press without release is ignored')
  release('A')
  press('A')
  assert_eq(2, #fired, 'press after release fires again')
end)

test('a bare d-pad press is ignored without crashing', function()
  setup()
  press('DPAD_UP')
  release('DPAD_UP')
  assert_eq('', fired_seq(), 'no gesture')
  assert_eq('', display_seq(), 'no display change')
end)

-- ---- Target switching precedence (Resolved Decision 4)

test('LB while a trigger is held is target_previous, never auto_run', function()
  setup()
  press('LT')
  run_timers()
  press('LB')
  assert_eq('target_previous', fired_seq(), 'target switch fires on press')
  release('LB')
  assert_eq('target_previous', fired_seq(), 'no auto_run on release')
end)

test('RB while a trigger is held is target_next, never cycle or direct switch', function()
  setup()
  press('RT')
  run_timers()
  press('RB')
  assert_eq('target_next', fired_seq(), 'target switch fires on press')
  press('A')
  assert_eq('target_next execute_slot', fired_seq(),
    'face under trigger+RB still executes the slot, not a direct switch')
  release('A')
  release('RB')
  assert_eq('target_next execute_slot', fired_seq(), 'no cycle_set on RB release')
end)

test('target switching works in wxhb (any trigger held, full stop)', function()
  setup()
  press('LT')
  release('LT')
  press('LT')
  run_timers()
  assert_eq('wxhb_l', gamepad.get_display_mode(), 'wxhb engaged')
  press('RB')
  assert_eq('target_next', fired_seq(), 'trigger held so RB is target_next')
end)

test('trigger plus LB before the anchor threshold drops silently', function()
  setup()
  press('LT')
  press('LB')
  assert_eq('', fired_seq(), 'anchor not held long enough')
  release('LB')
  release('LT')
  run_timers()
  assert_eq('', fired_seq(), 'never falls through to auto_run')
end)

-- ---- Trigger XHB engagement is orthogonal to held LB/RB

test('a trigger pulled under a held LB still engages its XHB', function()
  setup()
  press('LB')
  run_timers()
  press('LT')
  run_timers()
  assert_eq('xhb_l', gamepad.get_display_mode(), 'hold LT is unconditional')
  press('RB')
  assert_eq('target_next', fired_seq(), 'trigger held so RB targets, never mode_switch')
  release('RB')
  release('LT')
  release('LB')
  assert_eq('target_next', fired_seq(), 'no auto_run leaks from the LB hold')
  assert_eq('xhb_l idle', display_seq(), 'clean display path')
end)

test('a trigger pulled under a held RB still engages its XHB', function()
  setup()
  press('RB')
  press('LT')
  run_timers()
  assert_eq('xhb_l', gamepad.get_display_mode(), 'hold LT is unconditional')
  press('DPAD_UP')
  assert_eq(1, #fired, 'exactly one action')
  assert_eq('execute_slot', fired[1].id, 'trigger precedence routes the d-pad to the slot')
  assert_eq('xhb_l', fired[1].params.display_mode, 'slot addressed in the engaged XHB')
  assert_eq(1, fired[1].params.slot, 'DPAD_UP is slot 1')
  release('DPAD_UP')
  release('LT')
  release('RB')
  assert_eq('execute_slot', fired_seq(), 'no direct_switch and no cycle_set')
end)

test('a right trigger pulled under a held LB engages xhb_r', function()
  setup()
  press('LB')
  press('RT')
  run_timers()
  assert_eq('xhb_r', gamepad.get_display_mode(), 'hold RT is unconditional')
  release('RT')
  release('LB')
  assert_eq('xhb_r idle', display_seq(), 'clean display path')
  assert_eq('', fired_seq(), 'no auto_run leaks from the LB hold')
end)

-- ---- Taps

test('a bare LB tap fires auto_run', function()
  setup()
  press('LB')
  release('LB')
  assert_eq('auto_run', fired_seq(), 'tap fires on quick release')
  assert_eq('table', type(fired[1].params), 'params always a table')
end)

test('a bare RB tap fires cycle_set', function()
  setup()
  press('RB')
  release('RB')
  assert_eq('cycle_set', fired_seq(), 'tap fires on quick release')
end)

test('a tap exceeding max_hold is not a tap', function()
  setup()
  press('LB')
  run_timers()
  release('LB')
  assert_eq('', fired_seq(), 'expired tap does not fire')
end)

test('a chorded modifier suppresses its own tap on release', function()
  setup()
  press('RB')
  press('DPAD_UP')
  release('DPAD_UP')
  release('RB')
  assert_eq('direct_switch_1', fired_seq(),
    'direct switch fires but the quick RB release does not also cycle')
end)

test('any press under a held modifier suppresses its tap, even an inert one', function()
  setup()
  press('RB')
  press('L5')
  release('L5')
  release('RB')
  assert_eq('', fired_seq(),
    'no cycle_set: pressing anything under RB expresses modifier intent')
end)

-- ---- Direct switch

test('direct switch maps all eight positions in the frozen order', function()
  setup()
  press('RB')
  local order = { 'DPAD_UP', 'DPAD_RIGHT', 'DPAD_DOWN', 'DPAD_LEFT', 'A', 'B', 'X', 'Y' }
  for _, button in ipairs(order) do
    press(button)
    release(button)
  end
  release('RB')
  assert_eq(8, #fired, 'eight direct switches, no cycle_set')
  for n, f in ipairs(fired) do
    assert_eq('direct_switch_' .. n, f.id, 'gesture id per position')
    assert_eq(n, f.params.set, 'params carry the set number')
  end
end)

-- ---- Mode switch

test('LB anchor plus RB press fires mode_switch', function()
  setup()
  press('LB')
  run_timers()
  press('RB')
  assert_eq('mode_switch', fired_seq(), 'fires on the RB press')
  release('RB')
  release('LB')
  assert_eq('mode_switch', fired_seq(), 'exactly one action for the chord')
end)

test('RB held plus LB press is intentionally unmapped', function()
  setup()
  press('RB')
  run_timers()
  press('LB')
  release('LB')
  release('RB')
  assert_eq('', fired_seq(), 'reverse anchor direction does nothing')
end)

test('a rushed mode_switch chord fires nothing at all', function()
  setup()
  press('LB')
  press('RB')
  release('RB')
  release('LB')
  run_timers()
  assert_eq('', fired_seq(), 'no mode_switch and no leaked auto_run')
end)

-- ---- Open binder

test('open_binder fires while an XHB is active', function()
  setup()
  press('LT')
  run_timers()
  press('BACK')
  assert_eq('open_binder', fired_seq(), 'BACK under a trigger opens the binder')
  release('BACK')
  release('LT')
  setup()
  press('RT')
  run_timers()
  press('BACK')
  assert_eq('open_binder', fired_seq(), 'gated on xhb_r too')
end)

test('open_binder is gated off outside XHB displays', function()
  setup()
  press('LT')
  run_timers()
  press('L4')
  run_timers()
  assert_eq('wxhb_l', gamepad.get_display_mode(), 'wxhb active')
  press('BACK')
  assert_eq('', fired_seq(), 'BACK does not open the binder in wxhb')
end)

-- ---- Bare gestures

test('bare face, START and BACK presses fire their gesture entries', function()
  setup()
  local expected = {
    { button = 'A',     id = 'bare_a' },
    { button = 'B',     id = 'bare_b' },
    { button = 'X',     id = 'bare_x' },
    { button = 'Y',     id = 'bare_y' },
    { button = 'START', id = 'bare_start' },
    { button = 'BACK',  id = 'bare_back' },
  }
  for _, step in ipairs(expected) do
    local before = #fired
    press(step.button)
    assert_eq(before + 1, #fired, step.button .. ' fires on press')
    assert_eq(step.id, fired[#fired].id, step.button .. ' gesture id')
    assert_eq('table', type(fired[#fired].params), 'params always a table')
    release(step.button)
    assert_eq(before + 1, #fired, step.button .. ' release adds nothing')
  end
end)

-- ---- Custom, data-driven gestures

test('a custom tap on a free paddle fires its entry', function()
  local gestures = gamepad.default_gestures()
  gestures[#gestures + 1] = {
    id = 'open_inventory', type = 'tap', button = 'L5', context = 'bare',
    action = 'inventory', params = { max_hold = 0.25 },
  }
  setup(gestures)
  press('L5')
  release('L5')
  assert_eq('open_inventory', fired_seq(), 'custom tap fires')
end)

test('a custom button entry on a trackpad zone fires on press', function()
  local gestures = gamepad.default_gestures()
  gestures[#gestures + 1] = {
    id = 'satchel_zone', type = 'button', button = 'TRACKPAD_3', context = 'bare',
    action = 'satchel', params = {},
  }
  setup(gestures)
  press('TRACKPAD_3')
  assert_eq('satchel_zone', fired_seq(), 'fires at the press edge')
  release('TRACKPAD_3')
  assert_eq('satchel_zone', fired_seq(), 'no repeat and nothing on release')
end)

test('a custom hold fires once on engage and stays silent until release', function()
  local gestures = gamepad.default_gestures()
  gestures[#gestures + 1] = {
    id = 'push_to_run', type = 'hold', button = 'L5', context = 'bare',
    action = 'auto_run', params = { min_hold = 0.12 },
  }
  setup(gestures)
  press('L5')
  assert_eq('', fired_seq(), 'not engaged before min_hold')
  run_timers()
  assert_eq('push_to_run', fired_seq(), 'engaged once')
  release('L5')
  assert_eq('push_to_run', fired_seq(), 'release adds nothing')
  press('L5')
  release('L5')
  run_timers()
  assert_eq('push_to_run', fired_seq(), 'below min_hold never engages')
end)

test('a custom hold_then_hold anchored on RB fires once', function()
  local gestures = gamepad.default_gestures()
  gestures[#gestures + 1] = {
    id = 'rb_combo', type = 'hold_then_hold', button = 'L5', context = 'rb_held',
    action = 'inventory', params = { min_hold_first = 0.12, min_hold_second = 0.12 },
  }
  setup(gestures)
  press('RB')
  run_timers()
  press('L5')
  run_timers()
  assert_eq('rb_combo', fired_seq(), 'engaged once')
  release('L5')
  release('RB')
  assert_eq('rb_combo', fired_seq(), 'exactly one action for the chord')
end)

test('custom switch_set actions derive the set param', function()
  local gestures = gamepad.default_gestures()
  gestures[#gestures + 1] = {
    id = 'zone_to_five', type = 'button', button = 'TRACKPAD_1', context = 'bare',
    action = 'switch_set_5', params = {},
  }
  setup(gestures)
  press('TRACKPAD_1')
  assert_eq('zone_to_five', fired[1].id, 'custom id fires')
  assert_eq(5, fired[1].params.set, 'set parsed from the action name')
end)

test('custom entries cannot override reserved slot dispatch', function()
  local gestures = gamepad.default_gestures()
  gestures[#gestures + 1] = {
    id = 'evil', type = 'button', button = 'A', context = 'trigger_held',
    action = 'jump', params = {},
  }
  setup(gestures)
  press('LT')
  run_timers()
  press('A')
  assert_eq('execute_slot', fired_seq(), 'reserved context wins')
end)

test('custom entries cannot override reserved target switching', function()
  local gestures = gamepad.default_gestures()
  gestures[#gestures + 1] = {
    id = 'evil_lb', type = 'button', button = 'LB', context = 'trigger_held',
    action = 'jump', params = {},
  }
  setup(gestures)
  press('LT')
  run_timers()
  press('LB')
  assert_eq('target_previous', fired_seq(), 'reserved context wins')
end)

-- ---- Defaults

test('default_gestures ships every frozen gesture id', function()
  local expected = {
    'xhb_l', 'xhb_r', 'wxhb_l_paddle', 'wxhb_r_paddle', 'wxhb_l_tap', 'wxhb_r_tap',
    'expand_lt_rt', 'expand_rt_lt', 'auto_run', 'cycle_set', 'mode_switch',
    'target_previous', 'target_next',
    'direct_switch_1', 'direct_switch_2', 'direct_switch_3', 'direct_switch_4',
    'direct_switch_5', 'direct_switch_6', 'direct_switch_7', 'direct_switch_8',
    'execute_slot', 'open_binder',
    'bare_a', 'bare_b', 'bare_x', 'bare_y', 'bare_start', 'bare_back',
  }
  local defaults = gamepad.default_gestures()
  assert_eq(#expected, #defaults, 'exact default entry count')
  local ids = {}
  for _, entry in ipairs(defaults) do
    ids[entry.id] = true
  end
  for _, id in ipairs(expected) do
    assert_eq(true, ids[id], 'default id present: ' .. id)
  end
end)

test('default bare gestures map to the contract actions', function()
  local actions = {}
  for _, entry in ipairs(gamepad.default_gestures()) do
    actions[entry.id] = entry.action
  end
  assert_eq('menu_confirm', actions.bare_a,     'A confirms')
  assert_eq('menu_cancel',  actions.bare_b,     'B cancels')
  assert_eq('map',          actions.bare_x,     'X opens the map')
  assert_eq('jump',         actions.bare_y,     'Y jumps')
  assert_eq('menu_open',    actions.bare_start, 'START opens the menu')
  assert_eq('menu_focus',   actions.bare_back,  'BACK focuses the window')
end)

test('default_gestures returns a fresh deep copy each call', function()
  local first = gamepad.default_gestures()
  first[1].id = 'mutated'
  first[1].params.min_hold = 99
  local second = gamepad.default_gestures()
  assert_eq('xhb_l', second[1].id, 'ids are not shared')
  assert_eq(0.12, second[1].params.min_hold, 'params tables are not shared')
end)

-- ---- API shape

test('on_button_event never returns a value', function()
  setup()
  assert_eq(nil, gamepad.on_button_event('LT', true), 'press returns nil')
  assert_eq(nil, gamepad.on_button_event('LT', true), 'duplicate press returns nil')
  assert_eq(nil, gamepad.on_button_event('LT', false), 'release returns nil')
  assert_eq(nil, gamepad.on_button_event('LT', false), 'stale release returns nil')
end)

-- ----

package.loaded['log'] = nil

io.write(string.format('test_gamepad: %d passed, %d failed\n', pass, fail))
if fail > 0 then
  error(fail .. ' test(s) failed in test_gamepad.lua')
end
