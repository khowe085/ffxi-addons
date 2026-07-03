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

local keyboard = require('input/keyboard')

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

local DIK_LCTRL = 29
local DIK_RCTRL = 157

-- Contract default key_mapping (.planning/xivgamepad-contracts.md)
local function contract_mapping()
  return {
    LT         = { code = 2 },
    RT         = { code = 3 },
    LB         = { code = 4 },
    RB         = { code = 5 },
    A          = { code = 6 },
    B          = { code = 7 },
    X          = { code = 8 },
    Y          = { code = 9 },
    DPAD_UP    = { code = 10 },
    DPAD_RIGHT = { code = 11 },
    DPAD_DOWN  = { code = 41 },
    DPAD_LEFT  = { code = 13 },
    BACK       = { code = 2,  ctrl = true },
    START      = { code = 3,  ctrl = true },
    TRACKPAD_1 = { code = 4,  ctrl = true },
    TRACKPAD_2 = { code = 5,  ctrl = true },
    TRACKPAD_3 = { code = 6,  ctrl = true },
    TRACKPAD_4 = { code = 7,  ctrl = true },
    TRACKPAD_5 = { code = 8,  ctrl = true },
    TRACKPAD_6 = { code = 9,  ctrl = true },
    TRACKPAD_7 = { code = 10, ctrl = true },
    TRACKPAD_8 = { code = 11, ctrl = true },
    L4         = { code = 67 },
    L5         = { code = 68 },
    R4         = { code = 87 },
    R5         = { code = 88 },
  }
end

local events

local function event_seq()
  local parts = {}
  for _, e in ipairs(events) do
    parts[#parts + 1] = e.button .. (e.pressed and '+' or '-')
  end
  return table.concat(parts, ' ')
end

local function setup()
  keyboard.reset()
  keyboard.set_raw_callback(nil)
  keyboard.configure(contract_mapping())
  events = {}
  keyboard.set_callback(function(button, pressed)
    events[#events + 1] = { button = button, pressed = pressed }
  end)
end

-- ----

test('bare key press and release map to the virtual button', function()
  setup()
  keyboard.on_key(2, true)
  keyboard.on_key(2, false)
  assert_eq('LT+ LT-', event_seq(), 'code 2 without ctrl is LT')
end)

test('ctrl-gated entry matches when ctrl is down at the press edge', function()
  setup()
  keyboard.on_key(DIK_LCTRL, true)
  keyboard.on_key(2, true)
  keyboard.on_key(2, false)
  keyboard.on_key(DIK_LCTRL, false)
  assert_eq('BACK+ BACK-', event_seq(), 'ctrl + code 2 is BACK')
end)

test('the same code disambiguates by ctrl state per press', function()
  setup()
  keyboard.on_key(2, true)
  keyboard.on_key(2, false)
  keyboard.on_key(DIK_LCTRL, true)
  keyboard.on_key(2, true)
  keyboard.on_key(2, false)
  keyboard.on_key(DIK_LCTRL, false)
  keyboard.on_key(2, true)
  keyboard.on_key(2, false)
  assert_eq('LT+ LT- BACK+ BACK- LT+ LT-', event_seq(),
    'code 2 alternates LT/BACK with ctrl state')
end)

test('OS auto-repeat collapses to a single press edge', function()
  setup()
  keyboard.on_key(2, true)
  keyboard.on_key(2, true)
  keyboard.on_key(2, true)
  keyboard.on_key(2, true)
  keyboard.on_key(2, false)
  assert_eq('LT+ LT-', event_seq(), 'repeats produce no extra edges')
end)

test('release resolves to the pressed button when ctrl lifts mid-hold', function()
  setup()
  keyboard.on_key(DIK_LCTRL, true)
  keyboard.on_key(2, true)
  keyboard.on_key(DIK_LCTRL, false)
  keyboard.on_key(2, false)
  assert_eq('BACK+ BACK-', event_seq(),
    'ctrl release mid-hold must not strand BACK or fire LT release')
end)

test('release resolves to the bare button when ctrl arrives mid-hold', function()
  setup()
  keyboard.on_key(2, true)
  keyboard.on_key(DIK_LCTRL, true)
  keyboard.on_key(2, false)
  keyboard.on_key(DIK_LCTRL, false)
  assert_eq('LT+ LT-', event_seq(),
    'ctrl pressed after the key-down edge must not change the release')
end)

test('right ctrl gates ctrl entries too', function()
  setup()
  keyboard.on_key(DIK_RCTRL, true)
  keyboard.on_key(3, true)
  keyboard.on_key(3, false)
  keyboard.on_key(DIK_RCTRL, false)
  assert_eq('START+ START-', event_seq(), 'RCTRL + code 3 is START')
end)

test('ctrl entries on the shared trackpad row resolve over the bare row', function()
  setup()
  keyboard.on_key(DIK_LCTRL, true)
  keyboard.on_key(4, true)
  keyboard.on_key(4, false)
  keyboard.on_key(DIK_LCTRL, false)
  keyboard.on_key(4, true)
  keyboard.on_key(4, false)
  assert_eq('TRACKPAD_1+ TRACKPAD_1- LB+ LB-', event_seq(),
    'code 4 is TRACKPAD_1 with ctrl and LB without')
end)

test('ctrl down falls back to the bare entry when no ctrl row exists', function()
  setup()
  keyboard.on_key(DIK_LCTRL, true)
  keyboard.on_key(41, true)
  keyboard.on_key(41, false)
  keyboard.on_key(DIK_LCTRL, false)
  assert_eq('DPAD_DOWN+ DPAD_DOWN-', event_seq(),
    'code 41 has no ctrl row so it stays DPAD_DOWN')
end)

test('is_ctrl_down tracks both ctrl keys', function()
  setup()
  assert_eq(false, keyboard.is_ctrl_down(), 'ctrl starts up')
  keyboard.on_key(DIK_LCTRL, true)
  assert_eq(true, keyboard.is_ctrl_down(), 'LCTRL down')
  keyboard.on_key(DIK_RCTRL, true)
  keyboard.on_key(DIK_LCTRL, false)
  assert_eq(true, keyboard.is_ctrl_down(), 'RCTRL still down')
  keyboard.on_key(DIK_RCTRL, false)
  assert_eq(false, keyboard.is_ctrl_down(), 'both released')
end)

test('ctrl never surfaces as a virtual button', function()
  setup()
  keyboard.on_key(DIK_LCTRL, true)
  keyboard.on_key(DIK_LCTRL, false)
  keyboard.on_key(DIK_RCTRL, true)
  keyboard.on_key(DIK_RCTRL, false)
  assert_eq('', event_seq(), 'no callback for ctrl edges')
end)

test('unmapped keys produce no button events', function()
  setup()
  keyboard.on_key(30, true)
  keyboard.on_key(30, false)
  assert_eq('', event_seq(), 'unmapped code is silent')
end)

test('on_key never returns true', function()
  setup()
  assert_eq(nil, keyboard.on_key(2, true),          'mapped press returns nil')
  assert_eq(nil, keyboard.on_key(2, true),          'auto-repeat returns nil')
  assert_eq(nil, keyboard.on_key(2, false),         'mapped release returns nil')
  assert_eq(nil, keyboard.on_key(30, true),         'unmapped press returns nil')
  assert_eq(nil, keyboard.on_key(30, false),        'unmapped release returns nil')
  assert_eq(nil, keyboard.on_key(DIK_LCTRL, true),  'ctrl press returns nil')
  assert_eq(nil, keyboard.on_key(DIK_LCTRL, false), 'ctrl release returns nil')
end)

test('raw callback fires on every mappable key-down edge with ctrl state', function()
  setup()
  local raw = {}
  keyboard.set_raw_callback(function(dik, ctrl)
    raw[#raw + 1] = { dik = dik, ctrl = ctrl }
  end)
  keyboard.on_key(2, true)
  keyboard.on_key(2, true)
  keyboard.on_key(2, false)
  keyboard.on_key(DIK_LCTRL, true)
  keyboard.on_key(6, true)
  keyboard.on_key(6, false)
  keyboard.on_key(DIK_LCTRL, false)
  keyboard.on_key(30, true)
  keyboard.on_key(30, false)
  assert_eq(3, #raw, 'three down edges captured (no repeats, releases, or ctrl)')
  assert_eq(2, raw[1].dik, 'first edge code')
  assert_eq(false, raw[1].ctrl, 'first edge without ctrl')
  assert_eq(6, raw[2].dik, 'second edge code')
  assert_eq(true, raw[2].ctrl, 'second edge with ctrl')
  assert_eq(30, raw[3].dik, 'unmapped code still captured for learn mode')
  assert_eq(false, raw[3].ctrl, 'third edge without ctrl')
end)

test('raw callback runs in addition to normal mapping', function()
  setup()
  local raw = {}
  keyboard.set_raw_callback(function(dik, ctrl)
    raw[#raw + 1] = { dik = dik, ctrl = ctrl }
  end)
  keyboard.on_key(2, true)
  keyboard.on_key(2, false)
  assert_eq(1, #raw, 'raw edge captured')
  assert_eq('LT+ LT-', event_seq(), 'mapped callback still fires')
end)

test('clearing the raw callback stops raw capture', function()
  setup()
  local raw = {}
  keyboard.set_raw_callback(function(dik, ctrl)
    raw[#raw + 1] = dik
  end)
  keyboard.on_key(2, true)
  keyboard.on_key(2, false)
  keyboard.set_raw_callback(nil)
  keyboard.on_key(2, true)
  keyboard.on_key(2, false)
  assert_eq(1, #raw, 'no raw capture after clearing')
end)

test('reset clears held keys so stale releases are dropped', function()
  setup()
  keyboard.on_key(2, true)
  keyboard.reset()
  keyboard.on_key(2, false)
  assert_eq('LT+', event_seq(), 'release after reset produces no event')
end)

test('reset clears ctrl state', function()
  setup()
  keyboard.on_key(DIK_LCTRL, true)
  keyboard.reset()
  assert_eq(false, keyboard.is_ctrl_down(), 'ctrl cleared by reset')
  keyboard.on_key(2, true)
  keyboard.on_key(2, false)
  assert_eq('LT+ LT-', event_seq(), 'post-reset press resolves without ctrl')
end)

test('a press before reset re-presses cleanly after reset', function()
  setup()
  keyboard.on_key(2, true)
  keyboard.reset()
  keyboard.on_key(2, true)
  keyboard.on_key(2, false)
  assert_eq('LT+ LT+ LT-', event_seq(), 'reset drops repeat suppression state')
end)

test('configure mid-hold keeps the release on the old button', function()
  setup()
  keyboard.on_key(2, true)
  local remapped = contract_mapping()
  remapped.LT = { code = 50 }
  keyboard.configure(remapped)
  keyboard.on_key(2, false)
  assert_eq('LT+ LT-', event_seq(),
    'release resolves to what the press resolved to, even after remap')
end)

test('two held buttons release independently', function()
  setup()
  keyboard.on_key(2, true)
  keyboard.on_key(3, true)
  keyboard.on_key(2, false)
  keyboard.on_key(3, false)
  assert_eq('LT+ RT+ LT- RT-', event_seq(), 'independent edge tracking per key')
end)

-- ----

package.loaded['log'] = nil

io.write(string.format('test_input: %d passed, %d failed\n', pass, fail))
if fail > 0 then
  error(fail .. ' test(s) failed in test_input.lua')
end
