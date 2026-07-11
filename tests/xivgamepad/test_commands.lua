-- Command-dispatch and dispatch-suspend tests for the xivgamepad main entry
-- point. Every command and alias is exercised through xivgamepad.dispatch;
-- gesture routing and the suspend policy are driven through the module's
-- dispatch_gesture entry point directly (never by simulating GUI events).
--
-- The parallel-task frontend modules and crossbar adapters are preloaded as
-- recording stubs BEFORE the main module is loaded, and cleared again at the
-- end of this file.

-- Frontend/adapter/logger recording stubs (frozen contract surfaces only)

local tick_order      = {}
local hud_stub        = {}
local config_ui_stub  = {}
local tester_stub     = {}
local wizard_stub     = {}
local binder_stub     = {}
local gamedata_stub   = {}
local icons_stub      = {}
local mounts_stub     = {}
local skillchain_stub = {}
local log_stub        = {}

hud_stub.init          = function(opts)
  hud_stub._init_opts  = opts
  hud_stub._init_count = hud_stub._init_count + 1
end
hud_stub.show          = function() hud_stub._visible = true end
hud_stub.hide          = function() hud_stub._visible = false end
hud_stub.set_display   = function(mode) hud_stub._display = mode end
hud_stub.refresh       = function(view)
  hud_stub._last_view     = view
  hud_stub._refresh_count = hud_stub._refresh_count + 1
end
hud_stub.tick          = function()
  hud_stub._ticks = hud_stub._ticks + 1
  table.insert(tick_order, 'hud.tick')
end
hud_stub.set_draggable = function(v) hud_stub._draggable = v end
hud_stub.destroy       = function() hud_stub._destroyed = true end
hud_stub.on_mouse      = function(mtype, x, y, delta)
  table.insert(hud_stub._mouse_calls, { mtype = mtype, x = x, y = y, delta = delta })
  return hud_stub._mouse_result
end

config_ui_stub.init       = function(opts) config_ui_stub._init_opts = opts end
config_ui_stub.open       = function(staged)
  config_ui_stub._open        = true
  config_ui_stub._open_count  = config_ui_stub._open_count + 1
  config_ui_stub._last_staged = staged
end
config_ui_stub.close      = function() config_ui_stub._open = false end
config_ui_stub.is_open    = function() return config_ui_stub._open end
config_ui_stub.build_tabs = function() return {} end
config_ui_stub.on_mouse   = function(mtype, x, y, delta)
  table.insert(config_ui_stub._mouse_calls, { mtype = mtype, x = x, y = y, delta = delta })
  return config_ui_stub._mouse_result
end
config_ui_stub.destroy    = function()
  config_ui_stub._open      = false
  config_ui_stub._destroyed = true
end

tester_stub.init            = function(opts) tester_stub._init_opts = opts end
tester_stub.open            = function() tester_stub._open = true end
tester_stub.close           = function() tester_stub._open = false end
tester_stub.destroy         = function()
  tester_stub._open      = false
  tester_stub._destroyed = true
end
tester_stub.is_open         = function() return tester_stub._open end
tester_stub.on_button_event = function(name, pressed)
  table.insert(tester_stub._buttons, { name = name, pressed = pressed })
end
tester_stub.on_gesture      = function(id, params)
  table.insert(tester_stub._gestures, { id = id, params = params })
end

wizard_stub.start      = function(opts)
  wizard_stub._active      = true
  wizard_stub._opts        = opts
  wizard_stub._start_count = wizard_stub._start_count + 1
end
wizard_stub.on_raw_key = function(dik, ctrl_down)
  table.insert(wizard_stub._raw_keys, { dik = dik, ctrl = ctrl_down })
end
wizard_stub.skip       = function() wizard_stub._skip_count = wizard_stub._skip_count + 1 end
wizard_stub.back       = function() wizard_stub._back_count = wizard_stub._back_count + 1 end
wizard_stub.cancel     = function()
  wizard_stub._cancel_count = wizard_stub._cancel_count + 1
  if not wizard_stub._active then return end
  wizard_stub._active = false
  if wizard_stub._opts and wizard_stub._opts.on_cancel then
    wizard_stub._opts.on_cancel()
  end
end
wizard_stub.is_active  = function() return wizard_stub._active end
wizard_stub.finish     = function(new_mapping)
  wizard_stub._active = false
  if wizard_stub._opts and wizard_stub._opts.on_finish then
    wizard_stub._opts.on_finish(new_mapping)
  end
end

binder_stub.init      = function(opts) binder_stub._init_opts = opts end
binder_stub.toggle    = function(ctx)
  binder_stub._open         = not binder_stub._open
  binder_stub._last_ctx     = ctx
  binder_stub._toggle_count = binder_stub._toggle_count + 1
end
binder_stub.close     = function() binder_stub._open = false end
binder_stub.is_open   = function() return binder_stub._open end
binder_stub.on_button = function(name, pressed)
  table.insert(binder_stub._buttons, { name = name, pressed = pressed })
end

gamedata_stub.init         = function(path)
  gamedata_stub._init_count = gamedata_stub._init_count + 1
  gamedata_stub._init_path  = path
end
gamedata_stub.ensure_fresh = function()
  gamedata_stub._ensure_count = gamedata_stub._ensure_count + 1
end
gamedata_stub.recast_key   = function(binding)
  local entry = gamedata_stub.entry_for(binding)
  if entry then return entry.recast_id or entry.id, entry.res_key end
  return nil
end
gamedata_stub.spell        = function() return nil end
gamedata_stub.ability      = function() return nil end
gamedata_stub.entry_for    = function(binding)
  return gamedata_stub._entries[binding and binding.action or '']
end
gamedata_stub.icon_for     = function() return nil end
gamedata_stub.categories   = function() return {} end
gamedata_stub.list         = function() return {} end

icons_stub.init      = function(path)
  icons_stub._init_count = icons_stub._init_count + 1
  icons_stub._init_path  = path
end
icons_stub.item_icon = function(item)
  table.insert(icons_stub._item_calls, item)
  return icons_stub._item_icon
end
icons_stub.close     = function() icons_stub._close_count = icons_stub._close_count + 1 end

mounts_stub.refresh     = function()
  mounts_stub._refresh_count = mounts_stub._refresh_count + 1
end
mounts_stub.list        = function() return mounts_stub._list end
mounts_stub.ride_random = function() mounts_stub._ride_count = mounts_stub._ride_count + 1 end
mounts_stub.has_mounts  = function() return #mounts_stub._list > 0 end

skillchain_stub.init              = function(opts)
  skillchain_stub._init_count = skillchain_stub._init_count + 1
  skillchain_stub._init_opts  = opts
end
skillchain_stub.on_login          = function()
  skillchain_stub._login_count = skillchain_stub._login_count + 1
end
skillchain_stub.on_logout         = function()
  skillchain_stub._logout_count = skillchain_stub._logout_count + 1
end
skillchain_stub.on_action         = function(act)
  table.insert(skillchain_stub._actions, act)
end
skillchain_stub.on_incoming_chunk = function(id, data)
  table.insert(skillchain_stub._chunks, { id = id, data = data })
end
skillchain_stub.on_job_change     = function(job)
  table.insert(skillchain_stub._jobs, job)
end
skillchain_stub.on_zone_change    = function()
  skillchain_stub._zone_count = skillchain_stub._zone_count + 1
end
skillchain_stub.tick              = function()
  skillchain_stub._tick_count = skillchain_stub._tick_count + 1
  table.insert(tick_order, 'skillchain.tick')
end
skillchain_stub.prop_for          = function(id, res_key)
  table.insert(skillchain_stub._prop_calls, { id = id, res_key = res_key })
  return skillchain_stub._prop
end
skillchain_stub.window            = function()
  return skillchain_stub._window[1], skillchain_stub._window[2]
end

log_stub.init      = function(path) log_stub._init_path = path end
log_stub.debug     = function() end
log_stub.info      = function(fmt, ...)
  local ok, msg = pcall(string.format, tostring(fmt), ...)
  table.insert(log_stub._infos, ok and msg or tostring(fmt))
end
log_stub.error     = function(fmt, ...)
  local ok, msg = pcall(string.format, tostring(fmt), ...)
  table.insert(log_stub._errors, ok and msg or tostring(fmt))
end
log_stub.set_debug = function(v)
  log_stub._debug = not not v
  table.insert(log_stub._set_calls, not not v)
end
log_stub.toggle    = function()
  log_stub._debug = not log_stub._debug
  return log_stub._debug
end
log_stub.is_debug  = function() return log_stub._debug end

local function reset_stubs()
  hud_stub._init_opts     = nil
  hud_stub._init_count    = 0
  hud_stub._visible       = false
  hud_stub._display       = nil
  hud_stub._last_view     = nil
  hud_stub._refresh_count = 0
  hud_stub._ticks         = 0
  hud_stub._draggable     = nil
  hud_stub._destroyed     = false
  hud_stub._mouse_calls   = {}
  hud_stub._mouse_result  = false

  config_ui_stub._init_opts    = nil
  config_ui_stub._open         = false
  config_ui_stub._open_count   = 0
  config_ui_stub._last_staged  = nil
  config_ui_stub._mouse_calls  = {}
  config_ui_stub._mouse_result = false
  config_ui_stub._destroyed    = false

  tester_stub._init_opts = nil
  tester_stub._open      = false
  tester_stub._buttons   = {}
  tester_stub._gestures  = {}
  tester_stub._destroyed = false

  wizard_stub._active       = false
  wizard_stub._opts         = nil
  wizard_stub._start_count  = 0
  wizard_stub._skip_count   = 0
  wizard_stub._back_count   = 0
  wizard_stub._cancel_count = 0
  wizard_stub._raw_keys     = {}

  binder_stub._init_opts    = nil
  binder_stub._open         = false
  binder_stub._last_ctx     = nil
  binder_stub._toggle_count = 0
  binder_stub._buttons      = {}

  tick_order = {}

  gamedata_stub._init_count   = 0
  gamedata_stub._init_path    = nil
  gamedata_stub._ensure_count = 0
  gamedata_stub._entries      = {}

  icons_stub._init_count  = 0
  icons_stub._init_path   = nil
  icons_stub._close_count = 0
  icons_stub._item_calls  = {}
  icons_stub._item_icon   = nil

  mounts_stub._refresh_count = 0
  mounts_stub._ride_count    = 0
  mounts_stub._list          = {}

  skillchain_stub._init_count   = 0
  skillchain_stub._init_opts    = nil
  skillchain_stub._login_count  = 0
  skillchain_stub._logout_count = 0
  skillchain_stub._zone_count   = 0
  skillchain_stub._tick_count   = 0
  skillchain_stub._actions      = {}
  skillchain_stub._chunks       = {}
  skillchain_stub._jobs         = {}
  skillchain_stub._prop_calls   = {}
  skillchain_stub._prop         = nil
  skillchain_stub._window       = { 0, 0 }

  log_stub._init_path = nil
  log_stub._debug     = false
  log_stub._infos     = {}
  log_stub._errors    = {}
  log_stub._set_calls = {}
end

package.loaded['log']        = log_stub
package.loaded['hud']        = hud_stub
package.loaded['config_ui']  = config_ui_stub
package.loaded['tester']     = tester_stub
package.loaded['wizard']     = wizard_stub
package.loaded['binder']     = binder_stub
package.loaded['gamedata']   = gamedata_stub
package.loaded['icons']      = icons_stub
package.loaded['mounts']     = mounts_stub
package.loaded['skillchain'] = skillchain_stub

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

local function contains(haystack, needle)
  return haystack:find(needle, 1, true) ~= nil
end

local function commands_text()
  return table.concat(windower._commands, '\n')
end

-- In-memory filesystem for lib/settings in this test file
local vfs = {}
settings._set_io_provider({
  read_file  = function(path) return vfs[path] end,
  write_file = function(path, content) vfs[path] = content end,
})

local addon_path = 'C:\\Program Files (x86)\\Windower4\\addons\\xivgamepad\\'
local char_path  = addon_path .. 'data/TestChar/settings.json'

-- Hotbar content seeded through the mock files API (relative, addon-anchored
-- Windows-separator paths, matching what storage constructs).
local JOB_CONTENT =
  '{"WAR": {' ..
  '"1": {"slots": {"1": {"type": "ja", "action": "Provoke", "target": "t"},' ..
  '               "9": {"type": "ws", "action": "Fast Blade", "target": "t"}}},' ..
  '"2": {"slots": {"2": {"type": "ma", "action": "Cure", "target": "me"}}},' ..
  '"3": {"slots": {"1": {"type": "ct", "action": "input /wave"}}}}}'
local SHARED_CONTENT =
  '{"2": {"slots": {"3": {"type": "item", "action": "Hi-Potion", "target": "me"}}},' ..
  '"6": {"slots": {"1": {"type": "ct", "action": "input /heal"}}}}'

local function load_addon()
  settings.discard()
  windower.addon_path   = addon_path
  windower.ffxi._player = { name = 'TestChar', main_job = 'WAR', sub_job = 'NIN',
                            buffs = {}, status = 0 }
  windower.ffxi._info   = { menu_open = false, chat_open = false, zone = 100 }
  windower._chat        = {}
  windower._commands    = {}
  windower._scheduled   = {}
  windower._fs          = {}
  reset_stubs()
  return dofile('xivgamepad/xivgamepad.lua')
end

-- Fresh initialized addon. key_mapping_complete is pre-seeded true so the
-- first-run wizard offer stays out of command tests (opts.offer_wizard opts in).
local function fresh(opts)
  opts = opts or {}
  vfs = {}
  if not opts.offer_wizard then
    vfs[char_path] = '{"key_mapping_complete":true}'
  end
  local a = load_addon()
  if opts.content then
    windower._fs['data\\TestChar\\job.json']    = JOB_CONTENT
    windower._fs['data\\TestChar\\shared.json'] = SHARED_CONTENT
  end
  a.init()
  windower._commands = {}
  log_stub._infos    = {}
  return a
end

-- ---- command routing

test('config opens a staging session and the config window', function()
  local a = fresh()
  a.dispatch('config')
  assert(a._get_staged() ~= nil,                'staging session opened')
  assert_eq(true, config_ui_stub._open,         'config window open')
  assert_eq(true, hud_stub._draggable,          'HUD draggable during config')
  assert(config_ui_stub._last_staged == a._get_staged(), 'window received the staged table')
  assert(a._get_staged() ~= a._get_live(),      'staged is a copy, not live')
end)

test('c is an alias for config', function()
  local a = fresh()
  a.dispatch('c')
  assert(a._get_staged() ~= nil,        'staging session opened via alias')
  assert_eq(true, config_ui_stub._open, 'config window open via alias')
  a.dispatch('discard')
end)

test('config while the window is open is a no-op', function()
  local a = fresh()
  a.dispatch('config')
  local staged = a._get_staged()
  a.dispatch('config')
  assert_eq(1, config_ui_stub._open_count, 'window opened exactly once')
  assert(a._get_staged() == staged,        'staging session unchanged')
  a.dispatch('discard')
end)

test('config before init is safe and does nothing', function()
  vfs = {}
  local a = load_addon()
  local ok = pcall(function() a.dispatch('config') end)
  assert_eq(true,  ok,                   'config before init must not error')
  assert_eq(false, config_ui_stub._open, 'window not opened before init')
  assert_eq(nil,   a._get_staged(),      'no staging session before init')
end)

test('save commits staged settings, closes the window and writes the file', function()
  local a = fresh()
  a.dispatch('config')
  settings.stage_set(a._get_staged(), 'active_set', 5)
  a.dispatch('save')
  assert_eq(5,     a._get_live().active_set, 'staged value committed to live')
  assert_eq(nil,   a._get_staged(),          'staged cleared after save')
  assert_eq(false, config_ui_stub._open,     'config window closed')
  assert_eq(false, hud_stub._draggable,      'HUD dragging disabled')
  assert_eq(false, settings.in_setup(),      'setup session closed')
  assert(vfs[char_path] ~= nil and contains(vfs[char_path], '"active_set":5'),
    'settings file written with the committed value')
end)

test('s is an alias for save', function()
  local a = fresh()
  a.dispatch('config')
  settings.stage_set(a._get_staged(), 'active_set', 7)
  a.dispatch('s')
  assert_eq(7, a._get_live().active_set, 'alias committed the staged value')
end)

test('save reconfigures the keyboard from the committed key_mapping', function()
  local a = fresh()
  a.dispatch('config')
  settings.stage_set(a._get_staged(), 'key_mapping', { A = { code = 30 } })
  a.dispatch('save')
  a.dispatch('test')
  windower._events['keyboard'](30, true)
  assert_eq(1,   #tester_stub._buttons,        'new code resolves to a button')
  assert_eq('A', tester_stub._buttons[1].name, 'dik 30 maps to A after save')
  windower._events['keyboard'](2, true)
  assert_eq(1, #tester_stub._buttons, 'old default code no longer mapped')
end)

test('save reconfigures gestures and reindexes gesture dispatch', function()
  local a = fresh()
  a.dispatch('config')
  settings.stage_set(a._get_staged(), 'gestures', {
    { id = 'custom_wave', type = 'button', button = 'L5', context = 'bare',
      action = 'input /wave', params = {} },
  })
  a.dispatch('save')
  windower._commands = {}
  a.dispatch_gesture('custom_wave', {})
  assert(contains(commands_text(), 'input /wave'),
    'saved raw-command gesture fires via the escape hatch')
  windower._commands = {}
  a.dispatch_gesture('bare_x', {})
  assert_eq(0, #windower._commands, 'removed default gesture no longer dispatches')
end)

test('save without an open session is a safe no-op', function()
  local a = fresh()
  local before = vfs[char_path]
  local ok = pcall(function() a.dispatch('save') end)
  assert_eq(true,   ok,             'save with nothing staged must not error')
  assert_eq(before, vfs[char_path], 'settings file untouched')
end)

test('discard drops staged changes without writing', function()
  local a = fresh()
  local before = vfs[char_path]
  a.dispatch('config')
  settings.stage_set(a._get_staged(), 'active_set', 7)
  a.dispatch('discard')
  assert_eq(1,      a._get_live().active_set, 'live unchanged after discard')
  assert_eq(nil,    a._get_staged(),          'staged cleared after discard')
  assert_eq(false,  config_ui_stub._open,     'config window closed')
  assert_eq(false,  hud_stub._draggable,      'HUD dragging disabled')
  assert_eq(false,  settings.in_setup(),      'setup session closed')
  assert_eq(before, vfs[char_path],           'settings file untouched by discard')
end)

test('the footer Save button behaves exactly like the save command', function()
  local a = fresh()
  a.dispatch('config')
  settings.stage_set(a._get_staged(), 'active_set', 5)
  config_ui_stub._init_opts.on_save()
  assert_eq(5,     a._get_live().active_set, 'footer save committed the staged value')
  assert_eq(nil,   a._get_staged(),          'staged cleared')
  assert_eq(false, config_ui_stub._open,     'window closed')
  assert_eq(false, hud_stub._draggable,      'HUD dragging disabled')
  assert_eq(false, settings.in_setup(),      'setup session closed')
  assert(vfs[char_path] ~= nil and contains(vfs[char_path], '"active_set":5'),
    'settings file written by the footer save')
end)

test('the footer Discard button behaves exactly like the discard command', function()
  local a = fresh()
  local before = vfs[char_path]
  a.dispatch('config')
  settings.stage_set(a._get_staged(), 'active_set', 5)
  config_ui_stub._init_opts.on_discard()
  assert_eq(1,      a._get_live().active_set, 'footer discard left live unchanged')
  assert_eq(nil,    a._get_staged(),          'staged cleared')
  assert_eq(false,  config_ui_stub._open,     'window closed')
  assert_eq(false,  hud_stub._draggable,      'HUD dragging disabled')
  assert_eq(false,  settings.in_setup(),      'setup session closed')
  assert_eq(before, vfs[char_path],           'settings file untouched')
end)

test('d is an alias for discard', function()
  local a = fresh()
  a.dispatch('config')
  settings.stage_set(a._get_staged(), 'active_set', 7)
  a.dispatch('d')
  assert_eq(1,   a._get_live().active_set, 'alias left live unchanged')
  assert_eq(nil, a._get_staged(),          'alias cleared staged')
end)

test('hud element drags stage into hud_positions and commit on save', function()
  local a = fresh()
  hud_stub._init_opts.on_element_move('bar_left', 120, 300)
  assert_eq(nil, next(a._get_live().hud_positions), 'drag outside config is not staged')
  a.dispatch('config')
  hud_stub._init_opts.on_element_move('bar_left', 120, 300)
  local staged = a._get_staged().hud_positions.bar_left
  assert(staged ~= nil,   'element position staged during config')
  assert_eq(120, staged.x, 'staged x')
  assert_eq(300, staged.y, 'staged y')
  a.dispatch('save')
  assert_eq(300, a._get_live().hud_positions.bar_left.y, 'position committed on save')
end)

test('help prints a line for every command', function()
  local a = fresh()
  a.dispatch('help')
  local output = table.concat(log_stub._infos, '\n')
  assert(contains(output, '//xg config'),    'help lists config')
  assert(contains(output, '//xg save'),      'help lists save')
  assert(contains(output, '//xg discard'),   'help lists discard')
  assert(contains(output, '//xg test'),      'help lists test')
  assert(contains(output, '//xg learn'),     'help lists learn')
  assert(contains(output, '//xg debugmode'), 'help lists debugmode')
  assert(contains(output, '//xg help'),      'help lists help')
end)

test('unknown command falls through to help', function()
  local a = fresh()
  a.dispatch('bogus')
  assert(contains(table.concat(log_stub._infos, '\n'), '//xg help'),
    'help printed for an unknown command')
end)

test('nil command falls through to help', function()
  local a = fresh()
  a.dispatch(nil)
  assert(contains(table.concat(log_stub._infos, '\n'), '//xg help'),
    'help printed for a nil command')
end)

test('noop is silent, safe before init, and hidden from help', function()
  vfs = {}
  local a = load_addon()
  local ok = pcall(function() a.dispatch('noop') end)
  assert_eq(true, ok,                  'noop before init must not error')
  assert_eq(0,    #log_stub._infos,    'noop prints no info before init')
  assert_eq(0,    #log_stub._errors,   'noop raises no error before init')
  assert_eq(0,    #windower._chat,     'noop emits no chat before init')
  assert_eq(0,    #windower._commands, 'noop sends no commands before init')
  vfs[char_path] = '{"key_mapping_complete":true}'
  a.init()
  log_stub._infos    = {}
  windower._commands = {}
  a.dispatch('noop')
  assert_eq(0, #log_stub._infos,    'noop prints nothing after init')
  assert_eq(0, #windower._commands, 'noop sends nothing after init')
  a.dispatch('help')
  assert(not contains(table.concat(log_stub._infos, '\n'), 'noop'),
    'help output does not mention noop')
end)

test('test toggles the tester overlay and test_mode', function()
  local a = fresh()
  a.dispatch('test')
  assert_eq(true, a._get_flags().test_mode, 'test mode on')
  assert_eq(true, tester_stub._open,        'tester opened')
  a.dispatch('test')
  assert_eq(false, a._get_flags().test_mode, 'test mode off')
  assert_eq(false, tester_stub._open,        'tester closed')
end)

test('t is an alias for test', function()
  local a = fresh()
  a.dispatch('t')
  assert_eq(true, a._get_flags().test_mode, 'alias toggles test mode on')
  a.dispatch('t')
  assert_eq(false, a._get_flags().test_mode, 'alias toggles test mode off')
end)

test('learn starts the wizard with the current mapping and enters learn mode', function()
  local a = fresh()
  a.dispatch('learn')
  assert_eq(true, wizard_stub._active,       'wizard started')
  assert_eq(true, a._get_flags().learn_mode, 'learn mode on')
  assert(wizard_stub._opts.current_mapping == a._get_live().key_mapping,
    'wizard pre-loaded with the live mapping')
end)

test('l is an alias for learn; learn while active is a no-op', function()
  local a = fresh()
  a.dispatch('l')
  assert_eq(1, wizard_stub._start_count, 'wizard started via alias')
  a.dispatch('learn')
  assert_eq(1, wizard_stub._start_count, 'second learn does not restart the wizard')
end)

test('learn sub-commands route to wizard skip/back/cancel', function()
  local a = fresh()
  a.dispatch('learn')
  a.dispatch('learn', 'skip')
  a.dispatch('l', 'back')
  a.dispatch('learn', 'cancel')
  assert_eq(1, wizard_stub._skip_count,   'skip routed')
  assert_eq(1, wizard_stub._back_count,   'back routed')
  assert_eq(1, wizard_stub._cancel_count, 'cancel routed')
  assert_eq(false, a._get_flags().learn_mode, 'cancel exits learn mode')
end)

test('cancelling the first-run offer sets the no-nag flag, mapping untouched', function()
  local a = fresh({ offer_wizard = true })
  assert_eq(true, a._get_flags().learn_mode, 'first-run offer active')
  local lt_code = a._get_live().key_mapping.LT.code
  a.dispatch('learn', 'cancel')
  assert_eq(true, a._get_live().key_mapping_complete, 'no-nag flag set on dismissal')
  assert_eq(lt_code, a._get_live().key_mapping.LT.code, 'mapping untouched')
  assert(vfs[char_path] ~= nil and contains(vfs[char_path], '"key_mapping_complete":true'),
    'flag persisted to disk')
  assert_eq(false, a._get_flags().learn_mode, 'learn mode exited')
end)

test('wizard finish from a learn command persists and exits learn mode', function()
  local a = fresh()
  a.dispatch('learn')
  wizard_stub.finish({ B = { code = 48 } })
  assert_eq(48,    a._get_live().key_mapping.B.code,   'new mapping committed')
  assert_eq(true,  a._get_live().key_mapping_complete, 'flag stays set')
  assert_eq(false, a._get_flags().learn_mode,          'learn mode exited')
end)

test('debugmode toggles the logger', function()
  local a = fresh()
  a.dispatch('debugmode')
  assert_eq(true, log_stub._debug, 'debug on after first toggle')
  assert(contains(table.concat(log_stub._infos, '\n'), 'debug mode on'), 'state echoed')
  a.dispatch('debugmode')
  assert_eq(false, log_stub._debug, 'debug off after second toggle')
end)

test('debugmode on|off set the state explicitly; dbg is an alias', function()
  local a = fresh()
  a.dispatch('debugmode', 'on')
  assert_eq(true, log_stub._debug, 'explicit on')
  a.dispatch('debugmode', 'on')
  assert_eq(true, log_stub._debug, 'on is idempotent')
  a.dispatch('dbg', 'off')
  assert_eq(false, log_stub._debug, 'explicit off via alias')
  a.dispatch('dbg')
  assert_eq(true, log_stub._debug, 'alias toggles')
  assert_eq(true,  log_stub._set_calls[1], 'set_debug(true) called')
  assert_eq(false, log_stub._set_calls[3], 'set_debug(false) called')
end)

-- ---- gesture dispatch and the suspend policy

test('a bare menu gesture synthesizes its native key', function()
  local a = fresh()
  a.dispatch_gesture('bare_a', {})
  local cmds = commands_text()
  assert(contains(cmds, 'setkey enter down'), 'menu_confirm presses enter')
  assert(contains(cmds, 'setkey enter up'),   'menu_confirm releases enter')
end)

test('in_event halts everything including menu synthesis', function()
  local a = fresh()
  a._get_player_state().in_event = true
  a.dispatch_gesture('bare_a', {})
  a.dispatch_gesture('bare_y', {})
  a.dispatch_gesture('execute_slot', { display_mode = 'xhb_l', slot = 1 })
  assert_eq(0, #windower._commands, 'no commands while in a cutscene')
end)

test('menu_open suspends slots and field commands but menu synth passes', function()
  local a = fresh({ content = true })
  windower.ffxi._info.menu_open = true
  a.dispatch_gesture('execute_slot', { display_mode = 'xhb_l', slot = 1 })
  a.dispatch_gesture('bare_x', {})
  assert_eq(0, #windower._commands, 'slot dispatch and field commands suspended')
  a.dispatch_gesture('bare_a', {})
  a.dispatch_gesture('bare_b', {})
  a.dispatch_gesture('bare_back', {})
  a.dispatch_gesture('bare_start', {})
  local cmds = commands_text()
  assert(contains(cmds, 'setkey enter down'),   'menu_confirm passes while menu_open')
  assert(contains(cmds, 'setkey escape down'),  'menu_cancel passes while menu_open')
  assert(contains(cmds, 'setkey numpad+ down'), 'menu_focus passes while menu_open')
  assert(contains(cmds, 'setkey numpad- down'), 'menu_open passes while menu_open')
end)

test('chat_open suspends slots and field commands but menu synth passes', function()
  local a = fresh({ content = true })
  windower.ffxi._info.chat_open = true
  a.dispatch_gesture('execute_slot', { display_mode = 'xhb_l', slot = 1 })
  a.dispatch_gesture('bare_y', {})
  assert_eq(0, #windower._commands, 'slot dispatch and /jump suspended')
  a.dispatch_gesture('bare_b', {})
  assert(contains(commands_text(), 'setkey escape down'),
    'menu_cancel passes while chat_open (dismiss the chat bar)')
end)

test('test_mode reroutes gestures to the tester instead of actions', function()
  local a = fresh({ content = true })
  a.dispatch('test')
  a.dispatch_gesture('bare_a', {})
  a.dispatch_gesture('execute_slot', { display_mode = 'xhb_l', slot = 1 })
  assert_eq(0, #windower._commands, 'no game effects in test mode')
  assert_eq(2, #tester_stub._gestures, 'gestures shown in the tester')
  assert_eq('bare_a',       tester_stub._gestures[1].id, 'gesture id forwarded')
  assert_eq('execute_slot', tester_stub._gestures[2].id, 'slot gesture forwarded')
  assert_eq('xhb_l', tester_stub._gestures[2].params.display_mode, 'params forwarded')
end)

test('test_mode feeds button events to both the tester and the gamepad', function()
  local a = fresh()
  a.dispatch('test')
  windower._events['keyboard'](2, true)
  assert_eq(1,    #tester_stub._buttons,          'tester saw the press')
  assert_eq('LT', tester_stub._buttons[1].name,   'default mapping resolved LT')
  assert_eq(true, tester_stub._buttons[1].pressed, 'edge direction forwarded')
  windower._events['keyboard'](2, false)
  assert_eq(2, #tester_stub._buttons, 'tester saw the release')
end)

test('open_binder toggles the binder with the display context', function()
  local a = fresh()
  a.dispatch_gesture('open_binder', {})
  assert_eq(true, a._get_flags().binder_mode, 'binder mode on')
  assert_eq(true, binder_stub._open,          'binder open')
  assert_eq(1,     binder_stub._last_ctx.active_set, 'ctx carries the active set')
  assert_eq('job', binder_stub._last_ctx.mode,       'ctx carries the mode')
  a.dispatch_gesture('open_binder', {})
  assert_eq(false, a._get_flags().binder_mode, 'binder mode off after the toggle')
  assert_eq(false, binder_stub._open,          'binder closed')
end)

test('binder_mode routes buttons to the binder and suspends other gestures', function()
  local a = fresh({ content = true })
  a.dispatch_gesture('open_binder', {})
  a.on_button('DPAD_UP', true)
  a.on_button('DPAD_UP', false)
  assert_eq(2,         #binder_stub._buttons,       'binder received both edges')
  assert_eq('DPAD_UP', binder_stub._buttons[1].name, 'button name forwarded')
  windower._commands = {}
  a.dispatch_gesture('bare_a', {})
  a.dispatch_gesture('execute_slot', { display_mode = 'xhb_l', slot = 1 })
  assert_eq(0, #windower._commands, 'gesture actions suspended while the binder is open')
  a.dispatch_gesture('open_binder', {})
  assert_eq(false, a._get_flags().binder_mode, 'binder closed by its own gesture')
end)

test('dispatch_gesture before init is a safe no-op', function()
  vfs = {}
  local a = load_addon()
  local ok = pcall(function() a.dispatch_gesture('bare_a', {}) end)
  assert_eq(true, ok,                  'no crash before init')
  assert_eq(0,    #windower._commands, 'no commands before init')
end)

-- ---- host behavior through the gesture pipeline

test('execute_slot resolves the left half of the active set', function()
  local a = fresh({ content = true })
  a.dispatch_gesture('execute_slot', { display_mode = 'xhb_l', slot = 1 })
  assert(contains(commands_text(), 'input /ja "Provoke" <t>'),
    'slot 1 of the left half fired')
end)

test('execute_slot resolves the right half of the active set', function()
  local a = fresh({ content = true })
  a.dispatch_gesture('execute_slot', { display_mode = 'xhb_r', slot = 1 })
  assert(contains(commands_text(), 'input /ws "Fast Blade" <t>'),
    'slot 1 of the right half maps to set slot 9')
end)

test('execute_slot resolves an assigned display mode set and half', function()
  local a = fresh({ content = true })
  a.dispatch_gesture('execute_slot', { display_mode = 'wxhb_l', slot = 2 })
  assert(contains(commands_text(), 'input /ma "Cure" <me>'),
    'wxhb_l resolves its assigned set 2, left half')
end)

test('execute_slot on an empty slot is a no-op', function()
  local a = fresh({ content = true })
  a.dispatch_gesture('execute_slot', { display_mode = 'xhb_l', slot = 5 })
  assert_eq(0, #windower._commands, 'empty slot fired nothing')
end)

test('cycle_set advances to the next non-empty, non-skipped set in the pool', function()
  local a = fresh({ content = true })
  a.dispatch_gesture('cycle_set', {})
  assert_eq(2, a._get_live().active_set, 'cycled from 1 to 2')
  a.dispatch_gesture('cycle_set', {})
  assert_eq(1, a._get_live().active_set,
    'cycled back to 1: set 3 has content but is skip_cycle, 4/5 are empty')
end)

test('cycle_set persists the new active set', function()
  local a = fresh({ content = true })
  a.dispatch_gesture('cycle_set', {})
  assert(vfs[char_path] ~= nil and contains(vfs[char_path], '"active_set":2'),
    'active_set written to disk')
end)

test('cycle_set during an open config session survives save', function()
  local a = fresh({ content = true })
  a.dispatch('config')
  a.dispatch_gesture('cycle_set', {})
  assert_eq(2, a._get_live().active_set,   'live reflects the cycle immediately')
  assert_eq(2, a._get_staged().active_set, 'cycle mirrored into the staged table')
  a.dispatch('save')
  assert_eq(2, a._get_live().active_set, 'save preserves the runtime cycle')
  assert(vfs[char_path] ~= nil and contains(vfs[char_path], '"active_set":2'),
    'cycled set persisted to disk by save')
end)

test('cycle_set during an open config session converges on discard', function()
  local a = fresh({ content = true })
  local before = vfs[char_path]
  a.dispatch('config')
  a.dispatch_gesture('cycle_set', {})
  assert_eq(2, a._get_live().active_set, 'live reflects the cycle during config')
  a.dispatch('discard')
  assert_eq(1,      a._get_live().active_set, 'discard reverts live to the disk state')
  assert_eq(before, vfs[char_path],           'discard wrote nothing')
  local reloaded = settings.load(addon_path, { active_set = 1 })
  assert_eq(reloaded.active_set, a._get_live().active_set, 'live and disk agree')
end)

test('mode_switch during an open config session mirrors both keys into staged', function()
  local a = fresh({ content = true })
  a.dispatch('config')
  a.dispatch_gesture('mode_switch', {})
  assert_eq('shared', a._get_staged().current_mode, 'current_mode mirrored into staged')
  assert_eq(6,        a._get_staged().active_set,   'active_set mirrored into staged')
  a.dispatch('save')
  assert_eq('shared', a._get_live().current_mode, 'save preserves the mode switch')
  assert_eq(6,        a._get_live().active_set,   'save preserves the landed set')
end)

test('direct switch jumps to the set position and keeps the mode', function()
  local a = fresh({ content = true })
  a.dispatch_gesture('direct_switch_4', { set = 4 })
  assert_eq(4,     a._get_live().active_set,   'jumped to position 4')
  assert_eq('job', a._get_live().current_mode, 'mode unchanged by a direct switch')
end)

test('mode_switch toggles the pool and lands on its first usable set', function()
  local a = fresh({ content = true })
  a.dispatch_gesture('mode_switch', {})
  assert_eq('shared', a._get_live().current_mode, 'switched to the shared pool')
  assert_eq(6, a._get_live().active_set,
    'landed on set 6: first shared, non-skip position with content')
  a.dispatch_gesture('mode_switch', {})
  assert_eq('job', a._get_live().current_mode, 'switched back to the job pool')
  assert_eq(1, a._get_live().active_set, 'landed on the first usable job set')
end)

test('mode_switch while mounted dismounts instead of toggling', function()
  local a = fresh({ content = true })
  a._get_player_state().is_mounted = true
  a.dispatch_gesture('mode_switch', {})
  assert(contains(commands_text(), 'input /dismount'), 'dismount fired')
  assert_eq('job', a._get_live().current_mode, 'mode unchanged while mounted')
end)

test('target gestures synthesize the target-cycle keys', function()
  local a = fresh()
  a.dispatch_gesture('target_next', {})
  assert(contains(commands_text(), 'setkey tab down'), 'target_next presses tab')
  windower._commands = {}
  a.dispatch_gesture('target_previous', {})
  local cmds = commands_text()
  assert(contains(cmds, 'setkey lshift down'), 'target_previous holds shift')
  assert(contains(cmds, 'setkey tab down'),    'target_previous presses tab')
end)

test('an unknown gesture id with no matching action is dropped', function()
  local a = fresh()
  a.dispatch_gesture('no_such_gesture', {})
  assert_eq(0, #windower._commands, 'unknown gesture fired nothing')
end)

test('display transitions drive the HUD and the view model', function()
  local a = fresh({ content = true })
  a.dispatch_gesture('xhb_l', {})
  assert_eq('xhb_l', hud_stub._display, 'activate gesture set the HUD display')
  assert_eq('xhb_l', hud_stub._last_view.display_mode, 'view carries the display mode')
  local view = hud_stub._last_view
  assert(view.slots[1] ~= nil and view.slots[1].action == 'Provoke',
    'view resolves slot content for the displayed set')
  assert_eq(nil, view.slots[5], 'empty slots stay nil in the view')
end)

-- ---- WXHB always-show amendment

test('always_show_wxhb false (default): idle view unaffected, byte-for-byte identical to today', function()
  local a = fresh({ content = true })
  local view = hud_stub._last_view
  assert_eq(false, a._get_live().always_show_wxhb, 'flag defaults false')
  assert_eq('Provoke',    view.slots[1].action, 'left half from active_set (position 1)')
  assert_eq('Fast Blade', view.slots[9].action, 'right half from the same active_set position')
  assert_eq(nil, view.slots[2], 'wxhb-only content (position 2) is not blended in while off')
end)

test('always_show_wxhb true: an idle half assigned to a WXHB view shows that view content', function()
  local a = fresh({ content = true })
  a.dispatch('config')
  settings.stage_set(a._get_staged(), 'always_show_wxhb', true)
  a.dispatch('save')
  local view = hud_stub._last_view
  assert_eq('Cure', view.slots[2].action,
    'left half now filled by wxhb_l assigned position 2 (default half=left)')
  assert_eq(nil, view.slots[1], 'position 2 has nothing at slot 1: left half fully replaced, not blended')
  assert_eq(nil, view.slots[9], 'right half filled by wxhb_r assigned position 2, which has nothing there')
end)

test('always_show_wxhb true: each idle half independently resolves its own assigned position', function()
  local a = fresh({ content = true })
  a.dispatch('config')
  settings.stage_set(a._get_staged(), 'active_set', 3)
  settings.stage_set(a._get_staged(), 'display', {
    wxhb_l       = { set = 1, half = 'left' },
    wxhb_r       = { set = 1, half = 'right' },
    expand_lt_rt = { set = 4, half = 'right' },
    expand_rt_lt = { set = 4, half = 'right' },
  })
  settings.stage_set(a._get_staged(), 'always_show_wxhb', true)
  a.dispatch('save')
  local view = hud_stub._last_view
  assert_eq('Provoke',    view.slots[1].action, 'left half pulled from wxhb_l set 1, not active_set 3')
  assert_eq('Fast Blade', view.slots[9].action, 'right half pulled from wxhb_r set 1 simultaneously')
  assert_eq(3, view.active_set, 'view metadata (label/active_set) still reflects active_set while idle')
end)

test('a live-engaged half always wins over always-show; the other half still gets its WXHB content', function()
  local a = fresh({ content = true })
  a.dispatch('config')
  settings.stage_set(a._get_staged(), 'active_set', 3)
  settings.stage_set(a._get_staged(), 'display', {
    wxhb_l       = { set = 1, half = 'left' },
    wxhb_r       = { set = 1, half = 'right' },
    expand_lt_rt = { set = 4, half = 'right' },
    expand_rt_lt = { set = 4, half = 'right' },
  })
  settings.stage_set(a._get_staged(), 'always_show_wxhb', true)
  a.dispatch('save')
  a.dispatch_gesture('xhb_l', {})
  local view = hud_stub._last_view
  assert_eq('input /wave', view.slots[1].action,
    'left half is live-engaged (xhb_l): shows active_set 3, not wxhb_l set 1')
  assert_eq('Fast Blade', view.slots[9].action,
    'right half is not live: always-show still fills it from wxhb_r set 1')
end)

test('the RT mirror: a live-engaged right half always wins over always-show; the left half still gets its WXHB content', function()
  local a = fresh({ content = true })
  a.dispatch('config')
  settings.stage_set(a._get_staged(), 'active_set', 3)
  settings.stage_set(a._get_staged(), 'display', {
    wxhb_l       = { set = 1, half = 'left' },
    wxhb_r       = { set = 1, half = 'right' },
    expand_lt_rt = { set = 4, half = 'right' },
    expand_rt_lt = { set = 4, half = 'right' },
  })
  settings.stage_set(a._get_staged(), 'always_show_wxhb', true)
  a.dispatch('save')
  a.dispatch_gesture('xhb_r', {})
  local view = hud_stub._last_view
  assert_eq(nil, view.slots[9],
    'right half is live-engaged (xhb_r): shows active_set 3 (empty at slot 9), not wxhb_r set 1 (Fast Blade)')
  assert_eq('Provoke', view.slots[1].action,
    'left half is not live: always-show still fills it from wxhb_l set 1')
end)

test('always_show_wxhb true: an engaged Expanded gesture fills both halves from its own set, never swapped for wxhb content', function()
  local a = fresh({ content = true })
  a.dispatch('config')
  settings.stage_set(a._get_staged(), 'active_set', 3)
  settings.stage_set(a._get_staged(), 'display', {
    wxhb_l       = { set = 2, half = 'left' },
    wxhb_r       = { set = 2, half = 'right' },
    expand_lt_rt = { set = 1, half = 'right' },
    expand_rt_lt = { set = 1, half = 'right' },
  })
  settings.stage_set(a._get_staged(), 'always_show_wxhb', true)
  a.dispatch('save')
  a.dispatch_gesture('expand_lt_rt', {})
  local view = hud_stub._last_view
  assert_eq('Provoke', view.slots[1].action,
    'left half comes from expand_lt_rt own set 1, not wxhb_l set 2 (which has nothing at slot 1)')
  assert_eq(nil, view.slots[2],
    'left half is not blended with wxhb_l set 2, which would put Cure at slot 2')
  assert_eq('Fast Blade', view.slots[9].action,
    'right half comes from the same engaged set 1 as the left half, not wxhb_r set 2')
end)

test('execute_slot dispatch is unaffected by always_show_wxhb (resolves via display_target, not the view)', function()
  local a = fresh({ content = true })
  a.dispatch('config')
  settings.stage_set(a._get_staged(), 'always_show_wxhb', true)
  settings.stage_set(a._get_staged(), 'display', {
    wxhb_l       = { set = 2, half = 'left' },
    wxhb_r       = { set = 6, half = 'right' },
    expand_lt_rt = { set = 4, half = 'right' },
    expand_rt_lt = { set = 4, half = 'right' },
  })
  a.dispatch('save')
  a.dispatch_gesture('execute_slot', { display_mode = 'wxhb_l', slot = 2 })
  assert(contains(commands_text(), 'input /ma "Cure" <me>'),
    'wxhb_l still resolves its own assigned set 2, left half, exactly as without the flag')
end)

test('always_show_wxhb true: wxhb_l wins content when both wxhb views collide on the same half (reachable by toggling each view to the same half)', function()
  local a = fresh({ content = true })
  a.dispatch('config')
  settings.stage_set(a._get_staged(), 'display', {
    wxhb_l       = { set = 1, half = 'left' },
    wxhb_r       = { set = 2, half = 'left' },
    expand_lt_rt = { set = 4, half = 'right' },
    expand_rt_lt = { set = 4, half = 'right' },
  })
  settings.stage_set(a._get_staged(), 'always_show_wxhb', true)
  a.dispatch('save')
  local view = hud_stub._last_view
  assert_eq('Provoke', view.slots[1].action,
    'left half resolves wxhb_l set 1 (precedence), not wxhb_r set 2')
  assert_eq(nil, view.slots[2],
    'wxhb_r set 2 content (Cure at slot 2) does not leak in: wxhb_l wins outright, not blended')
end)

test('always_show_wxhb true: a half with no WXHB view assigned falls back to active_set content, not blank or stale', function()
  local a = fresh({ content = true })
  a.dispatch('config')
  settings.stage_set(a._get_staged(), 'display', {
    wxhb_l       = { set = 2, half = 'left' },
    expand_lt_rt = { set = 4, half = 'right' },
    expand_rt_lt = { set = 4, half = 'right' },
  })
  settings.stage_set(a._get_staged(), 'always_show_wxhb', true)
  a.dispatch('save')
  local view = hud_stub._last_view
  assert_eq('Cure', view.slots[2].action, 'left half filled by wxhb_l set 2 (sanity: the flag is working)')
  assert_eq('Fast Blade', view.slots[9].action,
    'right half has no wxhb_l/wxhb_r view assigned to it: falls back to active_set 1 content')
end)

test('always_show_wxhb true: a wxhb_l entry with .half set but no usable .set falls through to wxhb_r for that half', function()
  local a = fresh({ content = true })
  a.dispatch('config')
  settings.stage_set(a._get_staged(), 'display', {
    wxhb_l       = { half = 'left' },
    wxhb_r       = { set = 6, half = 'left' },
    expand_lt_rt = { set = 4, half = 'right' },
    expand_rt_lt = { set = 4, half = 'right' },
  })
  settings.stage_set(a._get_staged(), 'always_show_wxhb', true)
  a.dispatch('save')
  local view = hud_stub._last_view
  assert_eq('input /heal', view.slots[1].action,
    'wxhb_l has no usable .set (corrupted/hand-edited settings): falls through to wxhb_r set 6, not nil')
end)

-- ---- crossbar adapter wiring

test('incoming chunk 0x055 refreshes mounts; other ids do not', function()
  fresh()
  assert_eq(1, mounts_stub._refresh_count, 'init derived the initial mount list')
  windower._events['incoming chunk'](0x055, 'DATA')
  assert_eq(2, mounts_stub._refresh_count, 'key-item update rederives mounts')
  windower._events['incoming chunk'](0x028, 'DATA')
  windower._events['incoming chunk'](0x0DF, 'DATA')
  assert_eq(2, mounts_stub._refresh_count, 'other chunk ids do not refresh')
end)

test('every incoming chunk is forwarded to the skillchain adapter', function()
  fresh()
  windower._events['incoming chunk'](0x055, 'AAA')
  windower._events['incoming chunk'](0x028, 'BBB')
  assert_eq(2, #skillchain_stub._chunks, 'both chunks forwarded')
  assert_eq(0x055, skillchain_stub._chunks[1].id,   'chunk id forwarded')
  assert_eq('AAA', skillchain_stub._chunks[1].data, 'payload forwarded')
  assert_eq(0x028, skillchain_stub._chunks[2].id,   'non-mount ids still forwarded')
end)

test('action events are forwarded to the skillchain adapter while logged in', function()
  fresh()
  local act = { category = 3, param = 42 }
  windower._events['action'](act)
  assert_eq(1, #skillchain_stub._actions, 'action forwarded')
  assert(skillchain_stub._actions[1] == act, 'raw action table forwarded unchanged')
end)

test('action forwarding before init is safe (adapter owns the gate)', function()
  vfs = {}
  load_addon()
  local ok = pcall(function() windower._events['action']({ param = 1 }) end)
  assert_eq(true, ok, 'no crash before init')
  assert_eq(1, #skillchain_stub._actions,
    'raw event still forwarded; the adapter owns the enabled/logged-in gate')
end)

test('prerender ticks the skillchain window before the HUD', function()
  fresh()
  windower._events['prerender']()
  assert_eq(1, skillchain_stub._tick_count, 'skillchain ticked')
  assert_eq(1, hud_stub._ticks,             'hud ticked')
  assert_eq('skillchain.tick hud.tick', table.concat(tick_order, ' '),
    'resonance window updates before the HUD consumes it')
end)

test('mount_roulette is registered and delegates to mounts.ride_random', function()
  fresh()
  local action = require('action')
  local def = action.get_action('mount_roulette')
  assert(def ~= nil, 'system action registered')
  assert_eq('Call a random owned mount (dismounts if mounted)', def.description,
    'frozen description')
  assert_eq('mount', def.icon, 'icon key')
  def.run()
  assert_eq(1, mounts_stub._ride_count, 'run delegates to mounts.ride_random')
end)

test('hud.init opts carry gamedata and the skillchain accessors', function()
  fresh()
  local opts = hud_stub._init_opts
  assert(opts.gamedata == gamedata_stub, 'gamedata module passed through')
  assert_eq('function', type(opts.get_skillchain_prop),   'get_skillchain_prop injected')
  assert_eq('function', type(opts.get_skillchain_window), 'get_skillchain_window injected')
  skillchain_stub._window = { 2.5, 4.75 }
  local delay, window = opts.get_skillchain_window()
  assert_eq(2.5,  delay,  'window delay from skillchain.window')
  assert_eq(4.75, window, 'window remainder from skillchain.window')
end)

test('hud.init opts carry get_item_icon delegating to icons.item_icon', function()
  fresh()
  local opts = hud_stub._init_opts
  assert_eq('function', type(opts.get_item_icon), 'get_item_icon injected')
  icons_stub._item_icon = 'data/icons/items/4128.bmp'
  assert_eq('data/icons/items/4128.bmp', opts.get_item_icon('Hi-Potion'),
    'extracted path forwarded from icons.item_icon')
  assert_eq('Hi-Potion', icons_stub._item_calls[1], 'item name forwarded verbatim')
  icons_stub._item_icon = nil
  assert_eq(nil, opts.get_item_icon('Bogus Tonic'), 'extraction failure surfaces as nil')
  assert_eq(2, #icons_stub._item_calls, 'each call reaches the adapter')
end)

test('get_skillchain_prop composes entry_for with prop_for for ws and ja', function()
  fresh()
  local prop = hud_stub._init_opts.get_skillchain_prop
  gamedata_stub._entries['Fast Blade'] = { id = 32, res_key = 'weapon_skills' }
  gamedata_stub._entries['Provoke']    = { id = 635, recast_id = 5, res_key = 'job_abilities' }
  skillchain_stub._prop = 'Liquefaction'
  assert_eq('Liquefaction', prop({ type = 'ws', action = 'Fast Blade' }), 'ws prop resolved')
  assert_eq(32, skillchain_stub._prop_calls[1].id, 'generated ws id forwarded')
  assert_eq('weapon_skills', skillchain_stub._prop_calls[1].res_key, 'ws res table forwarded')
  assert_eq('Liquefaction', prop({ type = 'ja', action = 'Provoke' }), 'ja prop resolved')
  assert_eq(635, skillchain_stub._prop_calls[2].id, 'ability id forwarded')
  assert_eq('job_abilities', skillchain_stub._prop_calls[2].res_key, 'ja res table forwarded')
end)

test('regression: the recast timer slot never reaches prop_for (ja and pet)', function()
  -- skills.job_abilities and the resonance tracker are keyed by ability id
  -- (513+); job_abilities entries always carry a recast_id (0-255 timer
  -- slot), so forwarding recast_key's first return would miss every time.
  fresh()
  local prop = hud_stub._init_opts.get_skillchain_prop
  gamedata_stub._entries['Sic']         = { id = 517, recast_id = 102, res_key = 'job_abilities' }
  gamedata_stub._entries['Volt Strike'] = { id = 940, recast_id = 173, res_key = 'job_abilities' }
  skillchain_stub._prop = 'Fragmentation'
  assert_eq('Fragmentation', prop({ type = 'ja', action = 'Sic' }), 'ja prop resolved')
  assert_eq(517, skillchain_stub._prop_calls[1].id, 'ja ability id, not recast slot 102')
  assert_eq('Fragmentation', prop({ type = 'pet', action = 'Volt Strike' }), 'pet prop resolved')
  assert_eq(940, skillchain_stub._prop_calls[2].id, 'pet ability id, not recast slot 173')
  assert_eq('job_abilities', skillchain_stub._prop_calls[2].res_key, 'pet res table forwarded')
end)

test('get_skillchain_prop is nil for non-chainable or unknown bindings', function()
  fresh()
  local prop = hud_stub._init_opts.get_skillchain_prop
  gamedata_stub._entries['Cure'] = { id = 1, res_key = 'spells' }
  skillchain_stub._prop = 'Scission'
  assert_eq(nil, prop({ type = 'ma', action = 'Cure' }),      'spells cannot close a chain')
  assert_eq(nil, prop({ type = 'ws', action = 'Unknown WS' }), 'no generated entry -> nil')
  assert_eq(nil, prop(nil),                                    'nil binding -> nil')
  assert_eq(0, #skillchain_stub._prop_calls, 'prop_for never consulted')
end)

test('committing skillchain_display false->true re-seeds the skillchain lib', function()
  local a = fresh()
  assert_eq(1, skillchain_stub._login_count, 'init seeded once')
  a.dispatch('config')
  settings.stage_set(a._get_staged(), 'skillchain_display', false)
  a.dispatch('save')
  assert_eq(1, skillchain_stub._login_count, 'true -> false does not re-seed')
  a.dispatch('config')
  a.dispatch('save')
  assert_eq(1, skillchain_stub._login_count, 'unchanged commit does not re-seed')
  a.dispatch('config')
  settings.stage_set(a._get_staged(), 'skillchain_display', true)
  a.dispatch('save')
  assert_eq(2, skillchain_stub._login_count, 'false -> true re-seeds via on_login')
end)

test('binder.init opts carry get_mounts and gamedata', function()
  fresh()
  local opts = binder_stub._init_opts
  assert(opts.gamedata == gamedata_stub, 'gamedata module passed through')
  assert_eq('function', type(opts.get_mounts), 'get_mounts injected')
  mounts_stub._list = { 'Crab', 'Raptor' }
  local list = opts.get_mounts()
  assert_eq('Crab',   list[1], 'owned mounts come from mounts.list')
  assert_eq('Raptor', list[2], 'owned mounts come from mounts.list')
end)

-- ----

package.loaded['log']        = nil
package.loaded['hud']        = nil
package.loaded['config_ui']  = nil
package.loaded['tester']     = nil
package.loaded['wizard']     = nil
package.loaded['binder']     = nil
package.loaded['gamedata']   = nil
package.loaded['icons']      = nil
package.loaded['mounts']     = nil
package.loaded['skillchain'] = nil
settings.discard()
windower._reset()

io.write(string.format('test_commands: %d passed, %d failed\n', pass, fail))
if fail > 0 then
  error(fail .. ' test(s) failed in test_commands.lua')
end
