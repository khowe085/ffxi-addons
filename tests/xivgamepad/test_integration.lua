-- No-stub end-to-end integration tests for xivgamepad: the REAL main entry
-- point wired to the REAL modules (log, keyboard, gamepad, action, storage,
-- hud, config_ui, tester, wizard, binder) over the shared mock_windower
-- harness. Unit suites stub the cross-module seams, so only this file proves
-- the init-opts contracts actually line up.
--
-- Everything is driven through public surfaces only: the registered
-- windower._events handlers, dispatched addon commands, and keyboard events
-- with the default DIK codes (LT=2, RT=3, A=6, DPAD_RIGHT=11, Ctrl=29,
-- BACK=Ctrl+2).

-- Drop any xivgamepad.* module (stub or stale real instance) left in
-- package.loaded by earlier suite files so this file loads fresh REAL ones.
local function clear_xivgamepad_modules()
  local names = {}
  for name in pairs(package.loaded) do
    if name == 'xivgamepad' or name:find('^xivgamepad%.') then
      names[#names + 1] = name
    end
  end
  for _, name in ipairs(names) do
    package.loaded[name] = nil
  end
end

clear_xivgamepad_modules()

local settings = require('lib.settings.settings')

-- Settings I/O routed into the shared in-memory windower._fs (read at call
-- time, so windower._reset never strands a stale table reference).
settings._set_io_provider({
  read_file  = function(path) return windower._fs[path] end,
  write_file = function(path, content) windower._fs[path] = content end,
})

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

local function contains(haystack, needle)
  return haystack:find(needle, 1, true) ~= nil
end

local function commands_text()
  return table.concat(windower._commands, '\n')
end

local addon_path    = 'C:\\Program Files (x86)\\Windower4\\addons\\xivgamepad\\'
local settings_file = addon_path .. 'data/TestChar/settings.json'

-- DIK codes from the frozen default key mapping.
local KEY_LT    = 2
local KEY_RT    = 3
local KEY_A     = 6
local KEY_DPADR = 11
local KEY_CTRL  = 29

local JOB_CONTENT =
  '{"WAR": {"1": {"slots": {"5": {"type": "ma", "action": "Cure", "target": "t"}}}}}'

local function make_player()
  return { name = 'TestChar', main_job = 'WAR', sub_job = 'NIN', buffs = {}, status = 0 }
end

local function key(dik, pressed)
  windower._events['keyboard'](dik, pressed)
end

local function load_addon()
  settings.discard()
  windower.addon_path   = addon_path
  windower.ffxi._player = make_player()
  windower.ffxi._info   = { menu_open = false, chat_open = false, zone = 100 }
  windower._chat        = {}
  windower._commands    = {}
  windower._scheduled   = {}
  windower._fs          = {}
  return dofile('xivgamepad/xivgamepad.lua')
end

-- Fresh logged-in addon. Drops the poll chain from _scheduled after login so
-- _run_scheduled only drains the one-shot gesture timers.
local function fresh(opts)
  opts = opts or {}
  local a = load_addon()
  windower._fs[settings_file] = '{"key_mapping_complete":true}'
  if opts.content then
    windower._fs['data\\TestChar\\job.json'] = JOB_CONTENT
  end
  windower._events['login']()
  windower._scheduled = {}
  windower._commands  = {}
  windower._chat      = {}
  return a
end

-- ---- (a) lifecycle: deferred load, login, first-run wizard offer

test('load before login defers; login shows the HUD and offers the wizard', function()
  local a = load_addon()
  windower.ffxi._player = nil
  windower._events['load']()
  assert_eq(false, a._get_flags().initialized, 'deferred before login')
  assert_eq(16, #windower._commands, 'bind-noops still applied on load')
  assert_eq(false, windower._events['mouse'](0, 5, 5, 0, false),
    'mouse event safe and unconsumed before init')

  windower.ffxi._player = make_player()
  windower._commands = {}
  windower._events['login']()
  windower._scheduled = {}
  local hud    = require('xivgamepad.hud')
  local wizard = require('xivgamepad.wizard')
  assert_eq(true, a._get_flags().initialized,       'initialized on login')
  assert_eq(true, hud._label_for_test():visible(),  'HUD shown on login')
  assert_eq(true, wizard.is_active(),               'wizard offered: key_mapping_complete=false')
  assert_eq(true, a._get_flags().learn_mode,        'learn mode active during the offer')

  windower._events['addon command']('learn', 'cancel')
  assert_eq(false, wizard.is_active(),                 'wizard dismissed')
  assert_eq(false, a._get_flags().learn_mode,          'learn mode exited')
  assert_eq(true,  a._get_live().key_mapping_complete, 'dismissal set the no-nag flag')
  assert(windower._fs[settings_file] ~= nil
    and contains(windower._fs[settings_file], '"key_mapping_complete":true'),
    'flag persisted into the settings file in _fs')
end)

-- ---- (b) slot execution end-to-end through the real keyboard/gamepad/action

test('LT hold engages XHB-L and A fires the bound slot through the real stack', function()
  local a = fresh({ content = true })
  local gamepad = require('xivgamepad.gamepad')
  key(KEY_LT, true)
  windower._run_scheduled()
  assert_eq('xhb_l', gamepad.get_display_mode(), 'hold engaged XHB-L')
  key(KEY_A, true)
  assert_eq(1, #windower._commands, 'exactly one command from the slot press')
  assert_eq('input /ma "Cure" <t>', windower._commands[1], 'slot 5 (A) of the left half fired')
  assert(not contains(commands_text(), 'setkey'), 'no bare-face chat leak while a trigger is held')
  key(KEY_A, false)
  key(KEY_LT, false)
  windower._run_scheduled()
  assert_eq(nil, gamepad.get_display_mode(), 'display released with the trigger')
end)

-- ---- (c) bare A menu synthesis

test('bare A with no trigger synthesizes the setkey enter pair', function()
  fresh()
  key(KEY_A, true)
  key(KEY_A, false)
  assert_eq(2, #windower._commands,                  'exactly the down/up pair')
  assert_eq('setkey enter down', windower._commands[1], 'enter pressed')
  assert_eq('setkey enter up',   windower._commands[2], 'enter released')
  windower._run_scheduled()
end)

-- ---- (d) config window: real config_gui, row click stages, save persists

test('config opens the real window; a Sets row click stages; save persists to _fs', function()
  local a = fresh()
  local config_ui = require('xivgamepad.config_ui')
  windower._events['addon command']('config')
  assert_eq(true, config_ui.is_open(), 'config window open')
  assert(a._get_staged() ~= nil,       'staging session open')
  assert_eq(false, a._get_staged().sets[1].skip_cycle, 'set 1 cycles by default')

  -- Window anchor (100,100); 4 tabs -> body top = 100 + 2*18 = 136. Row 2 of
  -- the Sets tab (set 1) spans y 154..171; x 400 is right of the click split,
  -- so the click toggles skip_cycle.
  assert_eq(true, windower._events['mouse'](1, 400, 158, 0, false), 'row click consumed')
  assert_eq(true, windower._events['mouse'](2, 400, 158, 0, false), 'paired up consumed')
  assert_eq(true, a._get_staged().sets[1].skip_cycle, 'row click staged the toggle')
  assert_eq(false, a._get_live().sets[1].skip_cycle,  'live untouched before save')

  windower._events['addon command']('save')
  assert_eq(false, config_ui.is_open(),              'save closed the window')
  assert_eq(nil,   a._get_staged(),                  'staging session closed')
  assert_eq(true,  a._get_live().sets[1].skip_cycle, 'staged value committed to live')
  local reloaded = settings.load(addon_path, {})
  assert_eq(true, reloaded.sets[1].skip_cycle, 'value persisted into the settings file in _fs')

  -- Footer Save chip: down runs on_save (commit + close); the paired up is
  -- swallowed exactly once so nothing leaks to the game.
  windower._events['addon command']('config')
  assert_eq(true,  windower._events['mouse'](1, 400, 550, 0, false), 'Save chip down consumed')
  assert_eq(false, config_ui.is_open(), 'footer Save closed the window on the down')
  assert_eq(nil,   a._get_staged(),     'footer Save committed and closed the session')
  assert_eq(true,  windower._events['mouse'](2, 400, 550, 0, false), 'orphaned up swallowed')
  assert_eq(false, windower._events['mouse'](2, 400, 550, 0, false), 'swallow is single-shot')
end)

-- ---- (e) binder round-trip over the real binder seam

test('BACK with a trigger held opens the binder; BACK again closes it cleanly', function()
  local a = fresh({ content = true })
  local binder  = require('xivgamepad.binder')
  local gamepad = require('xivgamepad.gamepad')

  key(KEY_RT, true)
  windower._run_scheduled()
  assert_eq('xhb_r', gamepad.get_display_mode(), 'XHB-R engaged')

  key(KEY_CTRL, true)
  key(KEY_LT, true)  -- Ctrl+'1' resolves to BACK
  assert_eq(true, binder.is_open(),          'binder open after BACK with a trigger held')
  assert_eq(true, a._get_flags().binder_mode, 'binder_mode set')
  key(KEY_LT, false)
  key(KEY_CTRL, false)

  windower._commands = {}
  key(KEY_DPADR, true)
  key(KEY_DPADR, false)
  key(KEY_A, true)
  key(KEY_A, false)
  assert_eq('types', binder._state().menu, 'd-pad step + A confirmed into the type menu')
  assert_eq(0, #windower._commands, 'binder consumed navigation; no slot dispatch leaked')

  key(KEY_CTRL, true)
  key(KEY_LT, true)  -- BACK again
  assert_eq(false, binder.is_open(),           'second BACK toggled the binder closed')
  assert_eq(false, a._get_flags().binder_mode, 'binder_mode cleared on close')
  key(KEY_LT, false)
  key(KEY_CTRL, false)
  key(KEY_RT, false)
  windower._run_scheduled()

  windower._commands = {}
  key(KEY_LT, true)
  windower._run_scheduled()
  key(KEY_A, true)
  assert(contains(commands_text(), 'input /ma "Cure" <t>'),
    'slot execution works again after the binder round-trip')
  key(KEY_A, false)
  key(KEY_LT, false)
  windower._run_scheduled()
end)

-- ---- (f) tester rerouting

test('test mode reroutes slot gestures to the real tester and back', function()
  local a = fresh({ content = true })
  local tester = require('xivgamepad.tester')
  windower._events['addon command']('test')
  assert_eq(true, a._get_flags().test_mode, 'test mode on')
  assert_eq(true, tester.is_open(),         'tester overlay open')

  local before = #(tester._log_lines_for_test() or {})
  key(KEY_LT, true)
  windower._run_scheduled()
  key(KEY_A, true)
  assert_eq(0, #windower._commands, 'no send_command from a slot press in test mode')
  local lines = tester._log_lines_for_test()
  assert(#lines > before,                       'tester gesture log grew')
  assert(contains(lines[#lines], 'execute_slot'), 'slot gesture logged in the tester')
  key(KEY_A, false)
  key(KEY_LT, false)
  windower._run_scheduled()

  windower._events['addon command']('test')
  assert_eq(false, a._get_flags().test_mode, 'test mode off')
  assert_eq(false, tester.is_open(),         'tester overlay closed')
  windower._commands = {}
  key(KEY_LT, true)
  windower._run_scheduled()
  key(KEY_A, true)
  assert(contains(commands_text(), 'input /ma "Cure" <t>'), 'slot dispatch restored')
  key(KEY_A, false)
  key(KEY_LT, false)
  windower._run_scheduled()
end)

-- ---- (g) cutscene suspend

test('status 4 hides the HUD and halts bare synthesis; status 0 restores both', function()
  local a = fresh()
  local hud = require('xivgamepad.hud')
  assert_eq(true, hud._label_for_test():visible(), 'HUD visible after login')

  windower._events['status change'](4)
  assert_eq(true,  a._get_player_state().in_event, 'in_event set')
  assert_eq(false, hud._label_for_test():visible(), 'HUD hidden during the event')
  windower._commands = {}
  key(KEY_A, true)
  key(KEY_A, false)
  assert_eq(0, #windower._commands, 'bare A produces NO setkey during a cutscene')

  windower._events['status change'](0)
  assert_eq(false, a._get_player_state().in_event, 'in_event cleared')
  assert_eq(true,  hud._label_for_test():visible(), 'HUD restored after the event')
  windower._commands = {}
  key(KEY_A, true)
  key(KEY_A, false)
  assert(contains(commands_text(), 'setkey enter down'), 'bare A synthesis restored')
end)

-- ---- (h) unload teardown

test('unload restores the binds and destroys every UI element without error', function()
  fresh()
  local hud       = require('xivgamepad.hud')
  local tester    = require('xivgamepad.tester')
  local config_ui = require('xivgamepad.config_ui')
  windower._commands = {}
  local ok, err = pcall(function() windower._events['unload']() end)
  assert(ok, 'unload must not error: ' .. tostring(err))
  assert_eq(16, #windower._commands, 'exactly 16 unbind commands on unload')
  local cmds = commands_text()
  assert(contains(cmds, 'unbind ^1'),  'macro-palette bind restored')
  assert(contains(cmds, 'unbind f12'), 'paddle bind restored')
  assert_eq(nil, hud._label_for_test(),        'HUD destroyed')
  assert_eq(nil, tester._grid_text_for_test(), 'tester destroyed')
  assert_eq(nil, config_ui._gui_for_test(),    'config window destroyed')
end)

-- ---- suite hygiene: leave no real instances behind for later files

clear_xivgamepad_modules()
settings.discard()
windower._reset()

io.write(string.format('test_integration: %d passed, %d failed\n', pass, fail))
if fail > 0 then
  error(fail .. ' test(s) failed in test_integration.lua')
end
