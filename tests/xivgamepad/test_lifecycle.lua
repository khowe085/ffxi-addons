-- Lifecycle tests for the xivgamepad main entry point.
--
-- The frontend modules (hud/config_ui/tester/wizard/binder) are built in
-- parallel tasks and DO NOT exist in this worktree: complete recording stubs
-- for all five (plus the logger) are preloaded into package.loaded BEFORE the
-- main module is loaded, exactly as the contracts require. They are cleared
-- again at the end of this file so later manifest files load the real modules.

-- Frontend/logger recording stubs (frozen contract surfaces only)

local hud_stub       = {}
local config_ui_stub = {}
local tester_stub    = {}
local wizard_stub    = {}
local binder_stub    = {}
local log_stub       = {}

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
hud_stub.tick          = function() hud_stub._ticks = hud_stub._ticks + 1 end
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
-- Test driver: simulate the user completing the capture flow.
wizard_stub.finish     = function(new_mapping)
  wizard_stub._active = false
  if wizard_stub._opts and wizard_stub._opts.on_finish then
    wizard_stub._opts.on_finish(new_mapping)
  end
end

binder_stub.init      = function(opts) binder_stub._init_opts = opts end
binder_stub.toggle    = function(ctx)
  binder_stub._open     = not binder_stub._open
  binder_stub._last_ctx = ctx
end
binder_stub.close     = function() binder_stub._open = false end
binder_stub.is_open   = function() return binder_stub._open end
binder_stub.on_button = function(name, pressed)
  table.insert(binder_stub._buttons, { name = name, pressed = pressed })
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

  binder_stub._init_opts = nil
  binder_stub._open      = false
  binder_stub._last_ctx  = nil
  binder_stub._buttons   = {}

  log_stub._init_path = nil
  log_stub._debug     = false
  log_stub._infos     = {}
  log_stub._errors    = {}
  log_stub._set_calls = {}
end

package.loaded['log']       = log_stub
package.loaded['hud']       = hud_stub
package.loaded['config_ui'] = config_ui_stub
package.loaded['tester']    = tester_stub
package.loaded['wizard']    = wizard_stub
package.loaded['binder']    = binder_stub

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

-- In-memory filesystem for lib/settings in this test file
local vfs = {}
settings._set_io_provider({
  read_file  = function(path) return vfs[path] end,
  write_file = function(path, content) vfs[path] = content end,
})

local addon_path = 'C:\\Program Files (x86)\\Windower4\\addons\\xivgamepad\\'

local function settings_path(name)
  return addon_path .. 'data/' .. name .. '/settings.json'
end

local function make_player(overrides)
  local player = { name = 'TestChar', main_job = 'WAR', sub_job = 'NIN', buffs = {}, status = 0 }
  for k, v in pairs(overrides or {}) do
    player[k] = v
  end
  return player
end

-- These tests manipulate login state, so the addon must NOT auto-init.
local function load_addon()
  settings.discard()
  windower.addon_path = addon_path
  windower.ffxi._info = { menu_open = false, chat_open = false, zone = 100 }
  windower._chat      = {}
  windower._commands  = {}
  windower._scheduled = {}
  windower._fs        = {}
  reset_stubs()
  return dofile('xivgamepad/xivgamepad.lua')
end

-- ----

test('on_load defers init when not logged in (no crash, no settings)', function()
  windower.ffxi._player = nil
  vfs = {}
  local a = load_addon()
  a.on_load()
  assert_eq(nil,   a._get_live(),               'no settings loaded pre-login')
  assert_eq(false, a._get_flags().initialized,  'not initialized pre-login')
  assert_eq(false, hud_stub._visible,           'HUD not shown pre-login')
end)

test('on_load emits the bind-noop commands for every game-active key', function()
  windower.ffxi._player = nil
  vfs = {}
  local a = load_addon()
  a.on_load()
  assert_eq(16, #windower._commands, 'exactly 16 bind commands on load')
  local cmds = table.concat(windower._commands, '\n')
  for _, key in ipairs({ '^`', '^1', '^2', '^3', '^4', '^5', '^6', '^7', '^8',
                         '^9', '^0', '^=', 'f9', 'f10', 'f11', 'f12' }) do
    assert(contains(cmds, 'bind ' .. key .. ' xivgamepad noop'),
      'bind-noop emitted for ' .. key)
  end
end)

test('on_load initializes when already logged in', function()
  windower.ffxi._player = make_player()
  vfs = {}
  vfs[settings_path('TestChar')] = '{"key_mapping_complete":true,"active_set":3}'
  local a = load_addon()
  a.on_load()
  assert_eq(true, a._get_flags().initialized, 'initialized when loaded logged in')
  assert_eq(3,    a._get_live().active_set,   'saved settings loaded via on_load')
  assert_eq(true, hud_stub._visible,          'HUD shown')
end)

test('login initializes settings and shows the HUD', function()
  windower.ffxi._player = make_player()
  vfs = {}
  vfs[settings_path('TestChar')] = '{"key_mapping_complete":true,"active_set":3}'
  local a = load_addon()
  windower._events['login']()
  assert_eq(true,  a._get_flags().initialized, 'initialized on login')
  assert_eq(3,     a._get_live().active_set,   'per-character settings loaded')
  assert_eq('job', a._get_live().current_mode, 'defaults fill missing keys')
  assert_eq(true,  hud_stub._visible,          'HUD shown on login')
  assert(hud_stub._last_view ~= nil,           'HUD refreshed with a view model')
  assert_eq(3,       hud_stub._last_view.active_set, 'view shows the active set')
  assert_eq('Set 3', hud_stub._last_view.set_name,   'view carries the set name')
  assert_eq('job',   hud_stub._last_view.mode,       'view carries the mode')
end)

test('init passes the contract opts to hud.init', function()
  windower.ffxi._player = make_player()
  vfs = {}
  vfs[settings_path('TestChar')] = '{"key_mapping_complete":true}'
  local a = load_addon()
  a.init()
  local opts = hud_stub._init_opts
  assert(opts ~= nil,                              'hud.init called')
  assert(opts.settings == a._get_live(),           'settings passed by reference')
  assert_eq(addon_path, opts.addon_path,           'addon_path passed')
  assert(type(opts.resolve_binding) == 'function', 'resolve_binding passed')
  assert(type(opts.get_player_state) == 'function', 'get_player_state passed')
  assert(opts.get_player_state() == a._get_player_state(), 'player_state accessor works')
  assert(type(opts.on_element_move) == 'function', 'on_element_move passed')
  assert(opts.texts ~= nil and opts.images ~= nil, 'ui libraries passed')
end)

test('init is idempotent: one poll chain, stale config session cleared', function()
  windower.ffxi._player = make_player()
  vfs = {}
  vfs[settings_path('TestChar')] = '{"key_mapping_complete":true}'
  local a = load_addon()
  a.init()
  assert_eq(1, #windower._scheduled, 'one poll tick scheduled after init')
  a.dispatch('config')
  assert_eq(true, settings.in_setup(), 'in setup after config')
  a.init()
  assert_eq(false, settings.in_setup(),        're-init clears stale staging')
  assert_eq(nil,   a._get_staged(),            're-init clears staged table')
  assert_eq(false, config_ui_stub._open,       're-init closes the config window')
  assert_eq(1,     #windower._scheduled,       're-init does not stack poll chains')
  assert_eq(true,  a._get_flags().initialized, 'still initialized after re-init')
end)

test('character switch reloads settings and does not clobber the other file', function()
  vfs = {}
  vfs[settings_path('Beta')] = '{"key_mapping_complete":true,"active_set":5}'
  windower.ffxi._player = make_player({ name = 'Alpha' })
  local a = load_addon()
  vfs[settings_path('Alpha')] = '{"key_mapping_complete":true}'
  a.init()
  a.dispatch('config')
  settings.stage_set(a._get_staged(), 'active_set', 2)
  a.dispatch('save')
  assert_eq(2, a._get_live().active_set, 'Alpha staged change committed')
  windower.ffxi._player = make_player({ name = 'Beta' })
  a.init()
  assert_eq(5, a._get_live().active_set, 'Beta settings loaded, not Alpha')
  windower.ffxi._player = make_player({ name = 'Alpha' })
  local alpha = settings.load(addon_path, {})
  assert_eq(2, alpha.active_set, 'Alpha file intact after the switch')
end)

test('logout hides the HUD and abandons an open config session', function()
  windower.ffxi._player = make_player()
  vfs = {}
  vfs[settings_path('TestChar')] = '{"key_mapping_complete":true}'
  local a = load_addon()
  a.init()
  a.dispatch('config')
  assert_eq(true, config_ui_stub._open, 'config open before logout')
  windower._events['logout']()
  assert_eq(false, hud_stub._visible,          'HUD hidden on logout')
  assert_eq(false, config_ui_stub._open,       'config window closed on logout')
  assert_eq(false, settings.in_setup(),        'setup session abandoned')
  assert_eq(nil,   a._get_staged(),            'staged cleared')
  assert_eq(false, hud_stub._draggable,        'HUD dragging disabled')
  assert_eq(false, a._get_flags().initialized, 'no longer initialized')
end)

test('logout closes tester, binder and wizard and clears the mode flags', function()
  windower.ffxi._player = make_player()
  vfs = {}
  local a = load_addon()
  a.init()
  assert_eq(true, a._get_flags().learn_mode, 'wizard offer put us in learn mode')
  wizard_stub.finish(a._get_live().key_mapping)
  a.dispatch_gesture('open_binder', {})
  assert_eq(true, a._get_flags().binder_mode, 'binder open')
  a.dispatch('test')
  assert_eq(true, a._get_flags().test_mode, 'tester open')
  a.on_logout()
  local flags = a._get_flags()
  assert_eq(false, flags.test_mode,   'test mode cleared')
  assert_eq(false, flags.binder_mode, 'binder mode cleared')
  assert_eq(false, flags.learn_mode,  'learn mode cleared')
  assert_eq(false, tester_stub._open, 'tester closed')
  assert_eq(false, binder_stub._open, 'binder closed')
  assert_eq(false, wizard_stub._active, 'wizard closed')
end)

test('logout before init is safe', function()
  windower.ffxi._player = make_player()
  vfs = {}
  local a = load_addon()
  local ok = pcall(function() a.on_logout() end)
  assert_eq(true,  ok,                  'logout before init must not error')
  assert_eq(false, settings.in_setup(), 'no setup session opened')
  assert_eq(false, a._get_flags().initialized, 'still uninitialized')
end)

test('unload restores the binds and destroys the HUD', function()
  windower.ffxi._player = make_player()
  vfs = {}
  vfs[settings_path('TestChar')] = '{"key_mapping_complete":true}'
  local a = load_addon()
  a.init()
  windower._commands = {}
  windower._events['unload']()
  assert_eq(16, #windower._commands, 'exactly 16 unbind commands on unload')
  local cmds = table.concat(windower._commands, '\n')
  for _, key in ipairs({ '^`', '^1', '^2', '^3', '^4', '^5', '^6', '^7', '^8',
                         '^9', '^0', '^=', 'f9', 'f10', 'f11', 'f12' }) do
    assert(contains(cmds, 'unbind ' .. key), 'unbind emitted for ' .. key)
  end
  assert_eq(true, hud_stub._destroyed,       'HUD destroyed on unload')
  assert_eq(true, config_ui_stub._destroyed, 'config window destroyed on unload')
  assert_eq(true, tester_stub._destroyed,    'tester destroyed on unload')
end)

test('unload before init is safe and still restores the binds', function()
  windower.ffxi._player = nil
  vfs = {}
  local a = load_addon()
  windower._commands = {}
  local ok = pcall(function() windower._events['unload']() end)
  assert_eq(true,  ok,                  'unload before init must not error')
  assert_eq(16,    #windower._commands, 'unbinds still emitted')
  assert_eq(false, hud_stub._destroyed, 'no HUD to destroy before init')
end)

test('login offers the wizard when key_mapping_complete is false', function()
  windower.ffxi._player = make_player()
  vfs = {}
  local a = load_addon()
  a.init()
  assert_eq(true, wizard_stub._active,       'wizard opened on first login')
  assert_eq(1,    wizard_stub._start_count,  'wizard started once')
  assert_eq(true, a._get_flags().learn_mode, 'learn mode active')
  assert(wizard_stub._opts.current_mapping == a._get_live().key_mapping,
    'wizard pre-loaded with the current mapping')
  assert(type(wizard_stub._opts.on_finish) == 'function', 'on_finish wired')
  assert(type(wizard_stub._opts.on_cancel) == 'function', 'on_cancel wired')
  assert(#log_stub._infos > 0, 'chat prompt logged')
end)

test('login does not offer the wizard when key_mapping_complete is true', function()
  windower.ffxi._player = make_player()
  vfs = {}
  vfs[settings_path('TestChar')] = '{"key_mapping_complete":true}'
  local a = load_addon()
  a.init()
  assert_eq(0,     wizard_stub._start_count,  'wizard not started')
  assert_eq(false, a._get_flags().learn_mode, 'learn mode off')
end)

test('re-login while the wizard is open restarts it cleanly without persisting', function()
  windower.ffxi._player = make_player()
  vfs = {}
  local a = load_addon()
  a.init()
  assert_eq(1, wizard_stub._start_count, 'wizard open after first login')
  a.init()
  assert_eq(2,    wizard_stub._start_count,          'wizard restarted on re-login')
  assert_eq(true, wizard_stub._active,               'wizard active again')
  assert_eq(true, a._get_flags().learn_mode,         'learn mode active again')
  assert_eq(false, a._get_live().key_mapping_complete, 'teardown cancel never set the flag')
  assert_eq(nil,   vfs[settings_path('TestChar')],     'teardown cancel never wrote the file')
end)

test('wizard finish persists the mapping and reconfigures the keyboard', function()
  windower.ffxi._player = make_player()
  vfs = {}
  local a = load_addon()
  a.init()
  wizard_stub.finish({ A = { code = 30 } })
  assert_eq(true,  a._get_live().key_mapping_complete, 'flag set on finish')
  assert_eq(30,    a._get_live().key_mapping.A.code,   'new mapping in live settings')
  assert(vfs[settings_path('TestChar')] ~= nil,        'settings persisted to disk')
  assert_eq(false, a._get_flags().learn_mode,          'learn mode exited')
  a.dispatch('test')
  windower._events['keyboard'](30, true)
  assert_eq(1,   #tester_stub._buttons,        'reconfigured key resolves to a button')
  assert_eq('A', tester_stub._buttons[1].name, 'dik 30 now maps to A')
end)

test('raw key-down events route to the wizard while learn mode is active', function()
  windower.ffxi._player = make_player()
  vfs = {}
  local a = load_addon()
  a.init()
  assert_eq(true, a._get_flags().learn_mode, 'learn mode active')
  windower._events['keyboard'](30, true)
  windower._events['keyboard'](30, false)
  assert_eq(1,  #wizard_stub._raw_keys,       'wizard saw the key-down edge')
  assert_eq(30, wizard_stub._raw_keys[1].dik, 'raw dik forwarded')
  assert_eq(0,  #tester_stub._buttons,        'no button events dispatched in learn mode')
end)

test('prerender ticks the HUD only after init', function()
  windower.ffxi._player = nil
  vfs = {}
  local a = load_addon()
  windower._events['prerender']()
  assert_eq(0, hud_stub._ticks, 'no tick before init')
  windower.ffxi._player = make_player()
  vfs[settings_path('TestChar')] = '{"key_mapping_complete":true}'
  a.init()
  windower._events['prerender']()
  assert_eq(1, hud_stub._ticks, 'tick delegated after init')
end)

test('on_mouse delegates unconditionally: config window wins, HUD is fallback', function()
  windower.ffxi._player = make_player()
  vfs = {}
  local a = load_addon()
  config_ui_stub._mouse_result = true
  assert_eq(true, windower._events['mouse'](1, 5, 6, 0, false), 'gui-consumed event returns true')
  assert_eq(1, #config_ui_stub._mouse_calls, 'delegated before init (unconditional)')
  assert_eq(1, config_ui_stub._mouse_calls[1].mtype, 'event type forwarded')
  assert_eq(0, #hud_stub._mouse_calls, 'config consumption short-circuits the HUD')
  config_ui_stub._mouse_result = false
  assert_eq(false, a.on_mouse(2, 5, 6, 0), 'unconsumed event returns false')
  assert_eq(2, #config_ui_stub._mouse_calls, 'every event delegated')
  assert_eq(1, #hud_stub._mouse_calls, 'HUD sees the event the window passed on')
  assert_eq(2, hud_stub._mouse_calls[1].mtype, 'event type forwarded to the HUD')
  hud_stub._mouse_result = true
  assert_eq(true, a.on_mouse(1, 5, 6, 0), 'HUD-consumed event returns true')
end)

test('status 4 hides the HUD and halts input; leaving restores both', function()
  windower.ffxi._player = make_player()
  vfs = {}
  vfs[settings_path('TestChar')] = '{"key_mapping_complete":true}'
  local a = load_addon()
  a.init()
  windower._events['status change'](4)
  assert_eq(true,  a._get_player_state().in_event, 'in_event set')
  assert_eq(false, hud_stub._visible,              'HUD hidden in the event')
  windower._commands = {}
  a.dispatch_gesture('bare_a', {})
  assert_eq(0, #windower._commands, 'even menu synth halts during a cutscene')
  windower._events['status change'](0)
  assert_eq(false, a._get_player_state().in_event, 'in_event cleared')
  assert_eq(true,  hud_stub._visible,              'HUD restored after the event')
end)

test('status change tracks mount state (id 85)', function()
  windower.ffxi._player = make_player()
  vfs = {}
  vfs[settings_path('TestChar')] = '{"key_mapping_complete":true}'
  local a = load_addon()
  a.init()
  windower._events['status change'](85)
  assert_eq(true, a._get_player_state().is_mounted, 'mounted on status 85')
  windower._events['status change'](0)
  assert_eq(false, a._get_player_state().is_mounted, 'dismounted on status 0')
end)

test('buff events maintain the player_state buff set', function()
  windower.ffxi._player = make_player()
  vfs = {}
  vfs[settings_path('TestChar')] = '{"key_mapping_complete":true}'
  local a = load_addon()
  a.init()
  local before = hud_stub._refresh_count
  windower._events['gain buff'](358)
  assert_eq(true, a._get_player_state().buffs[358], 'buff gained')
  assert(hud_stub._refresh_count > before, 'HUD refreshed on gain')
  windower._events['lose buff'](358)
  assert_eq(nil, a._get_player_state().buffs[358], 'buff lost')
end)

test('job change updates player_state and reloads job sets', function()
  windower.ffxi._player = make_player()
  vfs = {}
  vfs[settings_path('TestChar')] = '{"key_mapping_complete":true}'
  local a = load_addon()
  windower._fs['data\\TestChar\\job.json'] =
    '{"SCH": {"1": {"slots": {"1": {"type": "ma", "action": "Cure", "target": "me"}}}}}'
  a.init()
  windower.ffxi._player = make_player({ main_job = 'SCH', sub_job = 'WHM' })
  windower._events['job change']()
  assert_eq('SCH', a._get_player_state().main_job, 'main job updated')
  assert_eq('WHM', a._get_player_state().sub_job,  'sub job updated')
  windower._commands = {}
  a.dispatch_gesture('execute_slot', { display_mode = 'xhb_l', slot = 1 })
  assert(contains(table.concat(windower._commands, '\n'), 'input /ma "Cure" <me>'),
    'reloaded job set content resolves for the new job')
end)

test('poll reconciliation refreshes only when the player diff is dirty', function()
  windower.ffxi._player = make_player()
  vfs = {}
  vfs[settings_path('TestChar')] = '{"key_mapping_complete":true}'
  local a = load_addon()
  a.init()
  local before = hud_stub._refresh_count
  a._reconcile()
  assert_eq(before, hud_stub._refresh_count, 'no refresh when nothing changed')
  windower.ffxi._player.buffs = { 358 }
  a._reconcile()
  assert_eq(true, a._get_player_state().buffs[358], 'poll picked up the buff')
  assert(hud_stub._refresh_count > before, 'HUD refreshed on the diff')
  local after = hud_stub._refresh_count
  a._reconcile()
  assert_eq(after, hud_stub._refresh_count, 'clean second poll does not refresh')
end)

test('poll reconciliation is robust to a nil player', function()
  windower.ffxi._player = make_player()
  vfs = {}
  vfs[settings_path('TestChar')] = '{"key_mapping_complete":true}'
  local a = load_addon()
  a.init()
  windower.ffxi._player = nil
  local ok = pcall(function() a._reconcile() end)
  assert_eq(true, ok, 'reconcile with nil player must not error')
end)

test('poll chain stops after logout and unload', function()
  windower.ffxi._player = make_player()
  vfs = {}
  vfs[settings_path('TestChar')] = '{"key_mapping_complete":true}'
  local a = load_addon()
  a.init()
  a.on_logout()
  windower._events['unload']()
  windower._run_scheduled()
  assert_eq(0, #windower._scheduled, 'poll chain died instead of rescheduling')
end)

test('zone change resets input state without error', function()
  windower.ffxi._player = make_player()
  vfs = {}
  vfs[settings_path('TestChar')] = '{"key_mapping_complete":true}'
  local a = load_addon()
  a.init()
  local ok = pcall(function() windower._events['zone change']() end)
  assert_eq(true, ok, 'zone change handler must not error')
  assert_eq(true, hud_stub._visible, 'HUD still visible after zone change')
end)

-- ----

package.loaded['log']       = nil
package.loaded['hud']       = nil
package.loaded['config_ui'] = nil
package.loaded['tester']    = nil
package.loaded['wizard']    = nil
package.loaded['binder']    = nil
settings.discard()
windower._reset()

io.write(string.format('test_lifecycle: %d passed, %d failed\n', pass, fail))
if fail > 0 then
  error(fail .. ' test(s) failed in test_lifecycle.lua')
end
