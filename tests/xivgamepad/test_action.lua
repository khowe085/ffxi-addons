-- Tests for xivgamepad/action.lua: registries, dispatch, resolve_binding,
-- overlay truth tables, system actions, and the raw-command escape hatch.
--
-- The real logger (xivgamepad.log, Task 1d) may not exist yet in this
-- worktree, so a recording stub is preloaded via package.loaded before
-- requiring the module under test (contracts doc: tests own this stub, never
-- the shared mock).

local log_stub = { _debug = {}, _info = {}, _error = {} }
log_stub.debug = function(fmt, ...) table.insert(log_stub._debug, string.format(fmt, ...)) end
log_stub.info  = function(fmt, ...) table.insert(log_stub._info,  string.format(fmt, ...)) end
log_stub.error = function(fmt, ...) table.insert(log_stub._error, string.format(fmt, ...)) end
package.loaded['xivgamepad.log'] = log_stub

local action = require('xivgamepad.action')

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

local function reset()
  windower._reset()
  log_stub._debug = {}
  log_stub._info = {}
  log_stub._error = {}
end

local function last_command()
  return windower._commands[#windower._commands]
end

local function make_host()
  local calls = {}
  local h = { calls = calls }
  local names = {
    'show_display', 'hide_display', 'execute_slot', 'cycle_set',
    'switch_set', 'toggle_mode', 'open_binder', 'get_player_state',
  }
  for _, name in ipairs(names) do
    h[name] = function(...) table.insert(calls, { name, ... }) end
  end
  return h
end

-- ---- Binding type dispatch ----

test('ma binding sends input /ma with default target', function()
  reset()
  action.execute_binding({ type = 'ma', action = 'Cure' }, {})
  assert_eq('input /ma "Cure" <t>', last_command())
end)

test('ma binding honors explicit target', function()
  reset()
  action.execute_binding({ type = 'ma', action = 'Cure', target = 'me' }, {})
  assert_eq('input /ma "Cure" <me>', last_command())
end)

test('ja binding sends input /ja', function()
  reset()
  action.execute_binding({ type = 'ja', action = 'Provoke', target = 't' }, {})
  assert_eq('input /ja "Provoke" <t>', last_command())
end)

test('ws binding sends input /ws', function()
  reset()
  action.execute_binding({ type = 'ws', action = 'Red Lotus Blade' }, {})
  assert_eq('input /ws "Red Lotus Blade" <t>', last_command())
end)

test('a binding sends input /attack with target', function()
  reset()
  action.execute_binding({ type = 'a' }, {})
  assert_eq('input /attack <t>', last_command())
end)

test('ra binding sends input /ra with target', function()
  reset()
  action.execute_binding({ type = 'ra', target = 'bt' }, {})
  assert_eq('input /ra <bt>', last_command())
end)

test('pet binding sends input /pet', function()
  reset()
  action.execute_binding({ type = 'pet', action = 'Sic', target = 't' }, {})
  assert_eq('input /pet "Sic" <t>', last_command())
end)

test('item binding sends input /item', function()
  reset()
  action.execute_binding({ type = 'item', action = 'Hi-Potion', target = 'me' }, {})
  assert_eq('input /item "Hi-Potion" <me>', last_command())
end)

test('mount binding sends input /mount', function()
  reset()
  action.execute_binding({ type = 'mount', action = 'Chocobo' }, {})
  assert_eq('input /mount "Chocobo"', last_command())
end)

test('ta binding sends input /ta with target', function()
  reset()
  action.execute_binding({ type = 'ta', target = 'stnpc' }, {})
  assert_eq('input /ta <stnpc>', last_command())
end)

test('map binding sends input /map', function()
  reset()
  action.execute_binding({ type = 'map' }, {})
  assert_eq('input /map', last_command())
end)

test('ct binding sends the raw action command', function()
  reset()
  action.execute_binding({ type = 'ct', action = '/heal' }, {})
  assert_eq('/heal', last_command())
end)

test('ct binding without an action logs an error and sends nothing', function()
  reset()
  action.execute_binding({ type = 'ct' }, {})
  assert_eq(0, #windower._commands, 'no command should be sent')
  assert(#log_stub._error > 0, 'an error should be logged')
end)

test('ma binding without an action logs an error and does not raise', function()
  reset()
  local ok = pcall(action.execute_binding, { type = 'ma' }, {})
  assert(ok, 'execute_binding must not raise on a missing action field')
  assert_eq(0, #windower._commands, 'no command should be sent')
  assert(#log_stub._error > 0, 'an error should be logged')
end)

test('ex binding without an action logs an error and skips the host', function()
  reset()
  local host = make_host()
  action.set_host(host)
  local ok = pcall(action.execute_binding, { type = 'ex' }, {})
  assert(ok, 'execute_binding must not raise on a missing action field')
  assert_eq(0, #host.calls, 'host must not be called without an action')
  assert(#log_stub._error > 0, 'an error should be logged')
end)

test('ex binding switches the display via host.show_display', function()
  reset()
  local host = make_host()
  action.set_host(host)
  action.execute_binding({ type = 'ex', action = 'xhb_l' }, {})
  assert_eq('show_display', host.calls[1][1])
  assert_eq('xhb_l', host.calls[1][2])
end)

test('noop binding does nothing', function()
  reset()
  action.set_host(make_host())
  action.execute_binding({ type = 'noop' }, {})
  assert_eq(0, #windower._commands, 'noop should send no command')
end)

test('unknown binding type logs an error and does not raise', function()
  reset()
  local ok = pcall(action.execute_binding, { type = 'bogus' }, {})
  assert(ok, 'execute_binding must not raise on an unknown type')
  assert(#log_stub._error > 0, 'an error should be logged for an unknown type')
end)

test('nil binding is a safe no-op', function()
  reset()
  local ok = pcall(action.execute_binding, nil, {})
  assert(ok, 'execute_binding must not raise on a nil binding')
  assert_eq(0, #windower._commands)
end)

-- ---- register_type: new types register without touching core dispatch ----

test('register_type adds a new binding type usable immediately', function()
  reset()
  local seen = nil
  action.register_type('custom', {
    execute = function(binding) seen = binding.action end,
  })
  action.execute_binding({ type = 'custom', action = 'hello' }, {})
  assert_eq('hello', seen)
end)

-- ---- Host not installed ----

test('host-dependent action with no host logs an error and does not raise', function()
  reset()
  action.set_host(nil)
  local ok = pcall(action.run_action, 'cycle_set', {}, {})
  assert(ok, 'run_action must not raise when no host is installed')
  assert_eq(0, #windower._commands, 'no command should be sent')
  assert(#log_stub._error > 0, 'an error should be logged')
end)

test('ex binding with no host logs an error and does not raise', function()
  reset()
  action.set_host(nil)
  local ok = pcall(action.execute_binding, { type = 'ex', action = 'xhb_l' }, {})
  assert(ok, 'execute_binding must not raise when no host is installed')
  assert(#log_stub._error > 0, 'an error should be logged')
end)

-- ---- describe ----

test('describe returns the alias when present, else the action name', function()
  local ma = action._get_type('ma')
  assert_eq('Cure Please', ma.describe({ type = 'ma', action = 'Cure', alias = 'Cure Please' }))
  assert_eq('Cure', ma.describe({ type = 'ma', action = 'Cure' }))
end)

test('describe falls back to fixed labels for nameless types', function()
  assert_eq('Attack',        action._get_type('a').describe({ type = 'a' }))
  assert_eq('Ranged Attack', action._get_type('ra').describe({ type = 'ra' }))
  assert_eq('Switch Target', action._get_type('ta').describe({ type = 'ta' }))
  assert_eq('View Map',      action._get_type('map').describe({ type = 'map' }))
  assert_eq('',              action._get_type('noop').describe({ type = 'noop' }))
end)

test('describe on ct/ex returns the alias or raw action', function()
  assert_eq('/heal',  action._get_type('ct').describe({ type = 'ct', action = '/heal' }))
  assert_eq('Rest',   action._get_type('ct').describe({ type = 'ct', action = '/heal', alias = 'Rest' }))
  assert_eq('xhb_l',  action._get_type('ex').describe({ type = 'ex', action = 'xhb_l' }))
end)

-- ---- System actions: display / hotbar ----

local display_actions = {
  activate_xhb_l          = 'xhb_l',
  activate_xhb_r          = 'xhb_r',
  activate_wxhb_l         = 'wxhb_l',
  activate_wxhb_r         = 'wxhb_r',
  activate_expanded_lt_rt = 'expand_lt_rt',
  activate_expanded_rt_lt = 'expand_rt_lt',
}
for name, mode in pairs(display_actions) do
  test(name .. ' calls host.show_display(' .. mode .. ')', function()
    reset()
    local host = make_host()
    action.set_host(host)
    action.run_action(name, {}, {})
    assert_eq('show_display', host.calls[1][1])
    assert_eq(mode, host.calls[1][2])
  end)
end

test('execute_slot calls host.execute_slot(display_mode, slot)', function()
  reset()
  local host = make_host()
  action.set_host(host)
  action.run_action('execute_slot', {}, { display_mode = 'xhb_l', slot = 3 })
  assert_eq('execute_slot', host.calls[1][1])
  assert_eq('xhb_l', host.calls[1][2])
  assert_eq(3, host.calls[1][3])
end)

test('cycle_set calls host.cycle_set', function()
  reset()
  local host = make_host()
  action.set_host(host)
  action.run_action('cycle_set', {}, {})
  assert_eq('cycle_set', host.calls[1][1])
end)

for n = 1, 8 do
  test('switch_set_' .. n .. ' calls host.switch_set(' .. n .. ')', function()
    reset()
    local host = make_host()
    action.set_host(host)
    action.run_action('switch_set_' .. n, {}, {})
    assert_eq('switch_set', host.calls[1][1])
    assert_eq(n, host.calls[1][2])
  end)
end

test('toggle_mode calls host.toggle_mode', function()
  reset()
  local host = make_host()
  action.set_host(host)
  action.run_action('toggle_mode', {}, {})
  assert_eq('toggle_mode', host.calls[1][1])
end)

test('open_binder calls host.open_binder', function()
  reset()
  local host = make_host()
  action.set_host(host)
  action.run_action('open_binder', {}, {})
  assert_eq('open_binder', host.calls[1][1])
end)

-- ---- mode_switch: mounted / unmounted branching ----

test('mode_switch calls host.toggle_mode when not mounted', function()
  reset()
  local host = make_host()
  action.set_host(host)
  action.run_action('mode_switch', { player_state = { is_mounted = false } }, {})
  assert_eq('toggle_mode', host.calls[1][1])
end)

test('mode_switch sends dismount when mounted, not toggle_mode', function()
  reset()
  local host = make_host()
  action.set_host(host)
  action.run_action('mode_switch', { player_state = { is_mounted = true } }, {})
  assert_eq('input /dismount', last_command())
  for _, call in ipairs(host.calls) do
    assert(call[1] ~= 'toggle_mode', 'toggle_mode must not fire while mounted')
  end
end)

test('mode_switch with no player_state defaults to toggle_mode', function()
  reset()
  local host = make_host()
  action.set_host(host)
  action.run_action('mode_switch', {}, {})
  assert_eq('toggle_mode', host.calls[1][1])
end)

-- ---- Character / game actions ----

test('auto_run sends /autorun', function()
  reset()
  action.run_action('auto_run', {}, {})
  assert_eq('input /autorun', last_command())
end)

test('dismount sends /dismount', function()
  reset()
  action.run_action('dismount', {}, {})
  assert_eq('input /dismount', last_command())
end)

test('target_previous synthesizes Shift+Tab', function()
  reset()
  action.run_action('target_previous', {}, {})
  assert_eq(4, #windower._commands)
  assert_eq('setkey lshift down', windower._commands[1])
  assert_eq('setkey tab down',    windower._commands[2])
  assert_eq('setkey tab up',      windower._commands[3])
  assert_eq('setkey lshift up',   windower._commands[4])
end)

test('target_next synthesizes Tab', function()
  reset()
  action.run_action('target_next', {}, {})
  assert_eq(2, #windower._commands)
  assert_eq('setkey tab down', windower._commands[1])
  assert_eq('setkey tab up',   windower._commands[2])
end)

-- ---- setkey synthesis actions ----

local synth_actions = {
  menu_confirm = 'enter',
  menu_cancel  = 'escape',
  menu_open    = 'numpad-',
  menu_focus   = 'numpad+',
  zoom_in      = '.',
  zoom_out     = ',',
}
for name, token in pairs(synth_actions) do
  test(name .. ' emits setkey ' .. token .. ' down/up pair', function()
    reset()
    action.run_action(name, {}, {})
    assert_eq(2, #windower._commands)
    assert_eq('setkey ' .. token .. ' down', windower._commands[1])
    assert_eq('setkey ' .. token .. ' up',   windower._commands[2])
  end)
end

-- ---- Command wrapper actions ----

local wrapper_commands = {
  jump    = 'input /jump',
  map     = 'input /map',
  case    = 'input /case',
  satchel = 'input /satchel',
  sack    = 'input /sack',
  ward1   = 'input /ward1',
  ward2   = 'input /ward2',
}
for name, command in pairs(wrapper_commands) do
  test(name .. ' wrapper sends ' .. command, function()
    reset()
    action.run_action(name, {}, {})
    assert_eq(command, last_command())
  end)
end

test('jump/map/case/satchel/sack/ward1/ward2 all carry icon item', function()
  for name in pairs(wrapper_commands) do
    assert_eq('item', action.get_action(name).icon, name .. ' icon')
  end
end)

test('inventory synthesizes Ctrl+I', function()
  reset()
  action.run_action('inventory', {}, {})
  assert_eq(4, #windower._commands)
  assert_eq('setkey lctrl down', windower._commands[1])
  assert_eq('setkey i down',     windower._commands[2])
  assert_eq('setkey i up',       windower._commands[3])
  assert_eq('setkey lctrl up',   windower._commands[4])
end)

test('equipment synthesizes Ctrl+E', function()
  reset()
  action.run_action('equipment', {}, {})
  assert_eq(4, #windower._commands)
  assert_eq('setkey lctrl down', windower._commands[1])
  assert_eq('setkey e down',     windower._commands[2])
  assert_eq('setkey e up',       windower._commands[3])
  assert_eq('setkey lctrl up',   windower._commands[4])
end)

-- ---- register_action: new actions register without touching core code ----

test('register_action adds a new action usable immediately', function()
  reset()
  local ran = false
  action.register_action('custom_action', { run = function() ran = true end })
  action.run_action('custom_action', {}, {})
  assert(ran, 'custom action should have run')
end)

-- ---- Raw-command escape hatch ----

test('run_action with an unregistered string sends it as a raw command', function()
  reset()
  action.run_action('gs c precast', {}, {})
  assert_eq('gs c precast', last_command())
end)

test('run_action with a non-string name logs an error and does not raise', function()
  reset()
  local ok = pcall(action.run_action, nil, {}, {})
  assert(ok, 'run_action must not raise on a non-string name')
  assert(#log_stub._error > 0, 'an error should be logged')
end)

-- ---- get_action / list_actions ----

test('get_action returns nil for an unregistered name', function()
  assert_eq(nil, action.get_action('does_not_exist'))
end)

test('get_action returns the registered def', function()
  local def = action.get_action('jump')
  assert(def ~= nil, 'jump should be registered')
  assert_eq('Jump', def.description)
end)

test('list_actions is sorted by name and includes description/icon', function()
  local list = action.list_actions()
  assert(#list > 0, 'list_actions should be non-empty')
  for i = 2, #list do
    assert(list[i - 1].name < list[i].name, 'list_actions must be sorted')
  end
  local found = false
  for _, entry in ipairs(list) do
    if entry.name == 'jump' then
      found = true
      assert_eq('item', entry.icon)
      assert_eq('Jump', entry.description)
    end
  end
  assert(found, 'jump should be present in list_actions')
end)

-- ---- resolve_binding ----

test('resolve_binding returns nil for a nil slot', function()
  assert_eq(nil, action.resolve_binding(nil, {}))
end)

test('resolve_binding returns the base binding when there are no overlays', function()
  local slot = { type = 'ma', action = 'Cure' }
  assert_eq(slot, action.resolve_binding(slot, {}))
end)

test('resolve_binding returns the base binding when no overlay matches', function()
  local slot = {
    type = 'ma', action = 'Cure',
    overlays = { { overlay_type = 'subjob', condition = { subjob = 'RDM' }, type = 'ma', action = 'Refresh' } },
  }
  local player_state = { sub_job = 'WHM' }
  assert_eq(slot, action.resolve_binding(slot, player_state))
end)

test('resolve_binding matches a subjob overlay', function()
  local overlay = { overlay_type = 'subjob', condition = { subjob = 'WHM' }, type = 'ma', action = 'Cure IV' }
  local slot = { type = 'ma', action = 'Cure', overlays = { overlay } }
  local player_state = { sub_job = 'WHM' }
  assert_eq(overlay, action.resolve_binding(slot, player_state))
end)

test('resolve_binding first-match-wins: addendum white before light arts', function()
  local addendum = { overlay_type = 'addendum_white', condition = {}, type = 'ma', action = 'Cure V' }
  local light     = { overlay_type = 'light_arts',     condition = {}, type = 'ma', action = 'Cure IV' }
  local slot = { type = 'ma', action = 'Cure', overlays = { addendum, light } }
  local player_state = { main_job = 'SCH', buffs = { [358] = true, [401] = true } }
  assert_eq(addendum, action.resolve_binding(slot, player_state))
end)

test('resolve_binding first-match-wins: order reversed picks light arts', function()
  local addendum = { overlay_type = 'addendum_white', condition = {}, type = 'ma', action = 'Cure V' }
  local light     = { overlay_type = 'light_arts',     condition = {}, type = 'ma', action = 'Cure IV' }
  local slot = { type = 'ma', action = 'Cure', overlays = { light, addendum } }
  local player_state = { main_job = 'SCH', buffs = { [358] = true, [401] = true } }
  assert_eq(light, action.resolve_binding(slot, player_state))
end)

test('resolve_binding falls back to base when overlay buff is not active', function()
  local addendum = { overlay_type = 'addendum_white', condition = {}, type = 'ma', action = 'Cure V' }
  local slot = { type = 'ma', action = 'Cure', overlays = { addendum } }
  local player_state = { main_job = 'SCH', buffs = {} }
  assert_eq(slot, action.resolve_binding(slot, player_state))
end)

test('resolve_binding skips an unknown overlay type and matches the next', function()
  local unknown = { overlay_type = 'not_a_real_type', condition = {}, type = 'ma', action = 'Bogus' }
  local light   = { overlay_type = 'light_arts',      condition = {}, type = 'ma', action = 'Cure IV' }
  local slot = { type = 'ma', action = 'Cure', overlays = { unknown, light } }
  local player_state = { main_job = 'SCH', buffs = { [358] = true } }
  local ok, resolved = pcall(action.resolve_binding, slot, player_state)
  assert(ok, 'resolve_binding must not raise on an unknown overlay type')
  assert_eq(light, resolved)
end)

test('resolve_binding with overlays as a number returns the base without raising', function()
  local slot = { type = 'ma', action = 'Cure', overlays = 5 }
  local ok, resolved = pcall(action.resolve_binding, slot, {})
  assert(ok, 'resolve_binding must not raise on a numeric overlays field')
  assert_eq(slot, resolved)
end)

test('resolve_binding with overlays as a string returns the base without raising', function()
  local slot = { type = 'ma', action = 'Cure', overlays = 'corrupt' }
  local ok, resolved = pcall(action.resolve_binding, slot, {})
  assert(ok, 'resolve_binding must not raise on a string overlays field')
  assert_eq(slot, resolved)
end)

test('resolve_binding skips a scalar overlay entry and matches the next', function()
  local light = { overlay_type = 'light_arts', condition = {}, type = 'ma', action = 'Cure IV' }
  local slot = { type = 'ma', action = 'Cure', overlays = { 'junk', light } }
  local player_state = { main_job = 'SCH', buffs = { [358] = true } }
  local ok, resolved = pcall(action.resolve_binding, slot, player_state)
  assert(ok, 'resolve_binding must not raise on a scalar overlay entry')
  assert_eq(light, resolved)
end)

-- ---- Overlay type truth tables ----

test('subjob overlay check matches only the configured subjob', function()
  local def = action._get_overlay_type('subjob')
  assert_eq(true,  def.check({ subjob = 'WHM' }, { sub_job = 'WHM' }))
  assert_eq(false, def.check({ subjob = 'WHM' }, { sub_job = 'BLM' }))
  assert_eq(false, def.check({ subjob = 'WHM' }, { sub_job = nil }))
end)

test('subjob overlay is_available reflects whether a subjob is set', function()
  local def = action._get_overlay_type('subjob')
  assert_eq(true,  def.is_available({ sub_job = 'WHM' }))
  assert_eq(false, def.is_available({ sub_job = nil }))
end)

local buff_overlay_types = {
  light_arts     = 358,
  dark_arts      = 359,
  addendum_white = 401,
  addendum_black = 402,
}
for name, buff_id in pairs(buff_overlay_types) do
  test(name .. ' overlay check reflects the buff-' .. buff_id .. ' flag', function()
    local def = action._get_overlay_type(name)
    assert_eq(true,  def.check({}, { buffs = { [buff_id] = true } }))
    assert_eq(false, def.check({}, { buffs = {} }))
    assert_eq(false, def.check({}, { buffs = nil }))
  end)

  test(name .. ' overlay is_available true only for SCH main or sub', function()
    local def = action._get_overlay_type(name)
    assert_eq(true,  def.is_available({ main_job = 'SCH' }))
    assert_eq(true,  def.is_available({ sub_job = 'SCH' }))
    assert_eq(false, def.is_available({ main_job = 'WHM', sub_job = 'BLM' }))
    assert_eq(false, def.is_available({}))
  end)
end

-- ---- Overlay-type enumeration (public API; binder consumes these) ----

test('list_overlay_types returns the frozen overlay types sorted', function()
  local names = action.list_overlay_types()
  assert_eq('addendum_black,addendum_white,dark_arts,light_arts,subjob',
    table.concat(names, ','))
end)

test('get_overlay_type returns defs with callable check and is_available', function()
  local frozen = { 'subjob', 'light_arts', 'addendum_white', 'dark_arts', 'addendum_black' }
  for _, name in ipairs(frozen) do
    local def = action.get_overlay_type(name)
    assert_eq('function', type(def.check), name .. ' check must be callable')
    assert_eq('function', type(def.is_available), name .. ' is_available must be callable')
  end
end)

test('get_overlay_type returns nil for an unknown name', function()
  assert_eq(nil, action.get_overlay_type('not_a_real_type'))
end)

test('_get_overlay_type delegates to the public getter', function()
  assert_eq(action.get_overlay_type('subjob'), action._get_overlay_type('subjob'))
end)

-- ---- register_overlay_type: new overlay types register without touching core ----

test('register_overlay_type adds a usable overlay type', function()
  action.register_overlay_type('custom_overlay', {
    check = function(condition, player_state) return player_state.custom == true end,
    is_available = function() return true end,
  })
  local slot = {
    type = 'ma', action = 'Cure',
    overlays = { { overlay_type = 'custom_overlay', condition = {}, type = 'ct', action = '/echo hi' } },
  }
  local matched = action.resolve_binding(slot, { custom = true })
  assert_eq('custom_overlay', matched.overlay_type)
end)

test('list_overlay_types reflects a newly registered type, still sorted', function()
  local names = action.list_overlay_types()
  assert_eq('addendum_black,addendum_white,custom_overlay,dark_arts,light_arts,subjob',
    table.concat(names, ','))
end)

-- ----

io.write(string.format('test_action: %d passed, %d failed\n', pass, fail))
if fail > 0 then
  error(fail .. ' test(s) failed in test_action.lua')
end
