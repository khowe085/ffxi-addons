-- No-stub end-to-end integration tests for xivgamepad: the REAL main entry
-- point wired to the REAL modules (log, keyboard, gamepad, action, storage,
-- hud, config_ui, tester, wizard, binder, plus the crossbar-port adapters
-- gamedata/icons/mounts/skillchain over the real ported crossbar/ libs) on
-- the shared mock_windower harness. Unit suites stub the cross-module seams,
-- so only this file proves the init-opts contracts actually line up.
--
-- Everything is driven through public surfaces only: the registered
-- windower._events handlers, dispatched addon commands, and keyboard events
-- with the default DIK codes (LT=2, RT=3, A=6, DPAD_RIGHT=11, Ctrl=29,
-- BACK=Ctrl+2).

-- Drop any addon module (stub or stale real instance) left in package.loaded
-- by earlier suite files so this file loads fresh REAL ones. Names match the
-- Windower {AddonPath}-relative require keys (flat for addon-root files,
-- slash-relative for subdirectories). The crossbar-port adapters and ported
-- crossbar/ libs are listed too: several are stateful or real-io bound
-- (icon_extractor captures io at require time, mountroulette derives its
-- mount list from res at require time), so no such module may survive this
-- file's boundary in either direction.
local addon_module_names = {
  'xivgamepad', 'log', 'gamepad', 'action', 'storage', 'hud',
  'config_ui', 'tester', 'wizard', 'binder', 'input/keyboard',
  'gamedata', 'icons', 'mounts', 'skillchain',
  'crossbar/resource_generator', 'crossbar/kebab_casify',
  'crossbar/ordered_pairs', 'crossbar/md5', 'crossbar/icon_extractor',
  'crossbar/mountroulette', 'crossbar/skillchain/skillchains',
  'crossbar/skillchain/skills',
}

local function clear_xivgamepad_modules()
  for _, name in ipairs(addon_module_names) do
    package.loaded[name] = nil
  end
end

clear_xivgamepad_modules()

-- Deterministic time for the skillchain scenarios (established technique from
-- test_skillchain): installed before any crossbar module loads so the ported
-- lib's require-time os.clock() capture sees it too. Restored in the hygiene
-- block at the bottom.
local fake_now   = 0
local real_clock = os.clock
os.clock = function() return fake_now end

-- Earlier manifest files add res entries without every optional field the
-- ported generator and skillchain lib dereference (element/skill/type for
-- generation, the .name alias the resonance display pass reads). Fill
-- defensively and additively -- never overwriting -- so this file passes
-- regardless of manifest order or a second in-process suite pass.
local function fill_missing(entry, field, value)
  if entry[field] == nil then entry[field] = value end
end

for id, spell in pairs(res.spells) do
  fill_missing(spell, 'type', 'WhiteMagic')
  fill_missing(spell, 'skill', 33)
  fill_missing(spell, 'recast_id', id)
  fill_missing(spell, 'mp_cost', 0)
  fill_missing(spell, 'element', 15)
  fill_missing(spell, 'name', spell.en)
  if res.skills[spell.skill] == nil then
    res.skills[spell.skill] = { id = spell.skill, en = 'Skill ' .. spell.skill }
  end
  if res.elements[spell.element] == nil then
    res.elements[spell.element] = { id = spell.element, en = 'None' }
  end
end

for id, ability in pairs(res.job_abilities) do
  fill_missing(ability, 'type', 'JobAbility')
  fill_missing(ability, 'recast_id', id)
  fill_missing(ability, 'tp_cost', 0)
  fill_missing(ability, 'element', 15)
  fill_missing(ability, 'name', ability.en)
  if res.elements[ability.element] == nil then
    res.elements[ability.element] = { id = ability.element, en = 'None' }
  end
end

for _, ws in pairs(res.weapon_skills) do
  if ws.skill ~= nil then
    fill_missing(ws, 'element', 15)
    fill_missing(ws, 'name', ws.en)
    if res.skills[ws.skill] == nil then
      res.skills[ws.skill] = { id = ws.skill, en = 'Skill ' .. ws.skill }
    end
    if res.elements[ws.element] == nil then
      res.elements[ws.element] = { id = ws.element, en = 'None' }
    end
  end
end

for _, mount in pairs(res.mounts or {}) do
  fill_missing(mount, 'name', mount.en)
end

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

local function assert_contains(list, value, msg)
  for _, v in ipairs(list) do
    if v == value then return end
  end
  error((msg or 'list is missing value') .. ': ' .. tostring(value), 2)
end

-- Counts mock-level files.write calls by relative path while fn runs (the
-- resource generator's only write route); always restores files.write, even
-- when fn throws. Mirrors test_gamedata's established helper.
local function with_write_counts(fn)
  local counts = {}
  local base_write = files.write
  files.write = function(f, content, flush)
    counts[f.path] = (counts[f.path] or 0) + 1
    return base_write(f, content, flush)
  end
  local ok, err = pcall(fn)
  files.write = base_write
  if not ok then error(err, 0) end
  return counts
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

local MOUNT_CONTENT =
  '{"WAR": {"1": {"slots": {"5": {"type": "mount", "action": "Mount Roulette"}}}}}'

local WS_CONTENT =
  '{"WAR": {"1": {"slots": {"5": {"type": "ws", "action": "Red Lotus Blade", "target": "t"}}}}}'

-- Set 1 re-sourced to shared. Top-level settings keys replace their defaults
-- wholesale on load, so the full 8-set array is spelled out.
local SHARED_SET1_SETTINGS = '{"key_mapping_complete":true,"sets":['
  .. '{"name":"Set 1","source":"shared","skip_cycle":false},'
  .. '{"name":"Set 2","source":"job","skip_cycle":false},'
  .. '{"name":"Set 3","source":"job","skip_cycle":true},'
  .. '{"name":"Set 4","source":"job","skip_cycle":true},'
  .. '{"name":"Set 5","source":"job","skip_cycle":true},'
  .. '{"name":"Set 6","source":"shared","skip_cycle":false},'
  .. '{"name":"Set 7","source":"shared","skip_cycle":true},'
  .. '{"name":"Set 8","source":"shared","skip_cycle":false}]}'

local SHARED_SET1_CONTENT = '{"1": {"slots": {'
  .. '"5": {"type": "ma", "action": "Cure", "target": "t"},'
  .. '"6": {"type": "ma", "action": "Fire", "target": "t"}}}}'

local GENERATED_SPELLS    = 'data/generated/crossbar_spells.lua'
local GENERATED_ABILITIES = 'data/generated/crossbar_abilities.lua'

-- The generated-resources MD5 freshness pass reads Windower's res sources at
-- these exact relative walk-up keys (fixture bodies only need stable bytes).
local function seed_res_sources()
  windower._fs['../../res/spells.lua']        = '-- fixture: res/spells.lua\nreturn {}\n'
  windower._fs['../../res/job_abilities.lua'] = '-- fixture: res/job_abilities.lua\nreturn {}\n'
  windower._fs['../../res/weapon_skills.lua'] = '-- fixture: res/weapon_skills.lua\nreturn {}\n'
end

-- Crafted raw 'action' event table per the mock's fake-ActionPacket schema:
-- a weapon-skill finish (category 3, message 185) by the player that opens
-- resonance on target_id.
local function ws_act(action_id, target_id)
  return {
    category = 3,
    actor_id = 777,
    param    = action_id,
    targets  = { {
      id      = target_id,
      actions = { {
        message   = 185,
        resource  = 'weapon_skills',
        action_id = action_id,
      } },
    } },
  }
end

local function make_player()
  return {
    id = 777, name = 'TestChar', main_job = 'WAR', sub_job = 'NIN',
    buffs = {}, status = 0,
  }
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
-- _run_scheduled only drains the one-shot gesture timers. opts: content
-- (seed JOB_CONTENT), job_content/shared_content (seed raw hotbar JSON),
-- settings (settings.json body override), sources (seed the res sources the
-- generation pipeline hashes -- without them gamedata degrades to empty),
-- fs (extra path -> content pairs seeded before login).
local function fresh(opts)
  opts = opts or {}
  local a = load_addon()
  windower._fs[settings_file] = opts.settings or '{"key_mapping_complete":true}'
  if opts.sources then
    seed_res_sources()
  end
  if opts.content then
    windower._fs['data\\TestChar\\job.json'] = JOB_CONTENT
  end
  if opts.job_content then
    windower._fs['data\\TestChar\\job.json'] = opts.job_content
  end
  if opts.shared_content then
    windower._fs['data\\TestChar\\shared.json'] = opts.shared_content
  end
  for path, content in pairs(opts.fs or {}) do
    windower._fs[path] = content
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
  local hud    = require('hud')
  local wizard = require('wizard')
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
  local gamepad = require('gamepad')
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
  local config_ui = require('config_ui')
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
  local binder  = require('binder')
  local gamepad = require('gamepad')

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
  local tester = require('tester')
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
  local hud = require('hud')
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
  local hud       = require('hud')
  local tester    = require('tester')
  local config_ui = require('config_ui')
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

-- ---- (i) generated-resources pipeline: once per addon load, not per login

test('login generates the crossbar resources; a relogin does not regenerate', function()
  load_addon()
  seed_res_sources()
  windower._fs[settings_file] = '{"key_mapping_complete":true}'
  windower._created_dirs = {}
  windower._events['login']()
  windower._scheduled = {}

  local spells_content    = windower._fs[GENERATED_SPELLS]
  local abilities_content = windower._fs[GENERATED_ABILITIES]
  assert_eq('string', type(spells_content),    'spells file generated at the exact relative path')
  assert_eq('string', type(abilities_content), 'abilities file generated at the exact relative path')
  assert(contains(spells_content, '["cure"]'),               'fixture spell keyed into the generated table')
  assert(contains(abilities_content, '["red-lotus-blade"]'), 'fixture ws keyed into the generated table')
  local base = 'C:\\Program Files (x86)\\Windower4\\addons\\xivgamepad'
  assert_contains(windower._created_dirs, base .. '\\data',            'data dir created (absolute)')
  assert_contains(windower._created_dirs, base .. '\\data\\generated', 'generated dir created (absolute)')

  local counts = with_write_counts(function()
    windower._events['login']()
  end)
  windower._scheduled = {}
  assert_eq(nil, counts[GENERATED_SPELLS],    'second login writes no spells file')
  assert_eq(nil, counts[GENERATED_ABILITIES], 'second login writes no abilities file')
  assert_eq(spells_content,    windower._fs[GENERATED_SPELLS],    'spells content untouched by the relogin')
  assert_eq(abilities_content, windower._fs[GENERATED_ABILITIES], 'abilities content untouched by the relogin')
  local gamedata = require('gamedata')
  assert_eq(1, gamedata.spell('Cure').id, 'lookups still served after the relogin')
end)

-- ---- (j) HUD icons resolved through real gamedata over the generated files

test('shared set-1 slots render generated custom and default icons in the real hud', function()
  fresh({
    sources        = true,
    settings       = SHARED_SET1_SETTINGS,
    shared_content = SHARED_SET1_CONTENT,
    fs = { ['images/icons/iconpacks/default/white-magic/cure.png'] = 'png-bytes' },
  })
  local gamepad = require('gamepad')
  local hud     = require('hud')
  key(KEY_LT, true)
  windower._run_scheduled()
  assert_eq('xhb_l', gamepad.get_display_mode(), 'hold engaged XHB-L')

  local cure_icon = hud._layers_for_test(5).icon
  assert_eq(true, cure_icon:visible(), 'bound slot icon visible')
  assert_eq(addon_path .. 'images/icons/iconpacks/default/white-magic/cure.png',
    cure_icon:path(), 'existing iconpack custom icon wins')
  local fire_icon = hud._layers_for_test(6).icon
  assert_eq(addon_path .. 'images/icons/spells/00144.png',
    fire_icon:path(), 'missing custom icon falls back to the generated default icon')

  key(KEY_A, true)
  assert_eq('input /ma "Cure" <t>', windower._commands[1], 'shared set-1 slot is live end-to-end')
  key(KEY_A, false)
  key(KEY_LT, false)
  windower._run_scheduled()
end)

-- ---- (k) mount roulette: key-item chunk -> refresh -> slot dispatch

test('key-item chunk refreshes mounts and a bound slot rides the roulette', function()
  fresh({ job_content = MOUNT_CONTENT })
  local mounts = require('mounts')
  assert_eq(0, #mounts.list(), 'no owned mounts before the key-item update')

  windower.ffxi._key_items = { 3001 }
  windower._events['incoming chunk'](0x055, string.char(0, 0, 0, 0))
  local owned = mounts.list()
  assert_eq(1, #owned, 'exactly one owned mount after chunk 0x055')
  assert_eq('Raptor', owned[1], 'owned mount derived from the key item')

  key(KEY_LT, true)
  windower._run_scheduled()
  key(KEY_A, true)
  assert_eq(1, #windower._commands, 'exactly one command from the roulette slot')
  assert_eq('input /mount "raptor"', windower._commands[1], 'sole owned mount called')
  key(KEY_A, false)

  windower.ffxi._player.buffs = { 252 }
  windower._commands = {}
  key(KEY_A, true)
  assert_eq(1, #windower._commands, 'exactly one command while mounted')
  assert_eq('input /dismount', windower._commands[1], 'mounted buff 252 dismounts instead')
  key(KEY_A, false)
  key(KEY_LT, false)
  windower._run_scheduled()
  windower.ffxi._key_items = {}
end)

-- ---- (l) skillchain: resonance -> sc_timer + slot highlight -> Display toggle

test('WS resonance drives the sc_timer and slot highlight; the toggle disables both', function()
  fake_now = 100
  local a = fresh({ sources = true, job_content = WS_CONTENT })
  local hud       = require('hud')
  local config_ui = require('config_ui')
  windower.ffxi._target = { id = 4242, name = 'Sabotender', hpp = 100 }

  windower._events['action'](ws_act(32, 4242))
  windower._events['prerender']()
  local timer = hud._sc_timer_for_test()
  assert_eq(true, timer:visible(), 'sc_timer shown while the window is live')
  assert_eq('Wait 3.0', timer:text(), 'delay phase text')
  assert_eq(false, hud._layers_for_test(5).schain:visible(),
    'no highlight during the delay phase')

  fake_now = 104
  windower._events['prerender']()
  assert_eq('Go! 6.0', timer:text(), 'open-window phase text')
  local schain = hud._layers_for_test(5).schain
  assert_eq(true, schain:visible(), 'eligible ws slot highlighted inside the window')
  assert_eq(addon_path .. 'images/icons/iconpacks/default/skillchain/liquefaction.png',
    schain:path(), 'highlight icon resolved from the chain property')

  windower._events['addon command']('config')
  config_ui.toggle_skillchain_display()
  assert_eq(false, a._get_staged().skillchain_display, 'toggle staged')
  assert_eq(true,  a._get_live().skillchain_display,   'live untouched before save')
  windower._events['addon command']('save')
  assert_eq(false, a._get_live().skillchain_display, 'toggle committed')
  assert(contains(windower._fs[settings_file], '"skillchain_display":false'),
    'toggle persisted into the settings file in _fs')

  windower._events['prerender']()
  assert_eq(false, hud._sc_timer_for_test():visible(), 'timer hidden once disabled')
  assert_eq(false, hud._layers_for_test(5).schain:visible(), 'highlight hidden once disabled')

  windower._events['action'](ws_act(32, 4242))
  windower._events['prerender']()
  assert_eq(false, hud._sc_timer_for_test():visible(), 'disabled adapter ignores further actions')
end)

-- ---- (l2) WXHB always-show: settings -> build_view -> hud, end to end

local ALWAYS_SHOW_SETTINGS = '{"key_mapping_complete":true,"hide_empty_slots":true,'
  .. '"transparency_standard":20,"transparency_active":0,"transparency_inactive":60}'

local ALWAYS_SHOW_JOB_CONTENT = '{"WAR": {'
  .. '"1": {"slots": {"5": {"type": "ma", "action": "Cure", "target": "t"}}},'
  .. '"2": {"slots": {'
  .. '"1": {"type": "ja", "action": "Provoke", "target": "t"},'
  .. '"9": {"type": "ws", "action": "Fast Blade", "target": "t"}}}}}'

test('always_show_wxhb: settings toggle drives build_view and hud transparency end to end', function()
  local a = fresh({ settings = ALWAYS_SHOW_SETTINGS, job_content = ALWAYS_SHOW_JOB_CONTENT })
  local gamepad   = require('gamepad')
  local hud       = require('hud')
  local config_ui = require('config_ui')

  -- Idle, flag off (default): only active_set (position 1, slot 5) renders.
  assert_eq(true,  hud._layers_for_test(5).icon:visible(), 'active_set slot 5 (Cure) visible while idle')
  assert_eq(false, hud._layers_for_test(1).icon:visible(), 'wxhb-only slot 1 hidden while the flag is off')
  assert_eq(false, hud._layers_for_test(9).icon:visible(), 'wxhb-only slot 9 hidden while the flag is off')

  -- Enable always_show_wxhb through the real config window and save.
  windower._events['addon command']('config')
  config_ui.toggle_always_show_wxhb()
  assert_eq(true,  a._get_staged().always_show_wxhb, 'toggle staged')
  assert_eq(false, a._get_live().always_show_wxhb,   'live untouched before save')
  windower._events['addon command']('save')
  assert_eq(true, a._get_live().always_show_wxhb, 'toggle committed')
  assert(contains(windower._fs[settings_file], '"always_show_wxhb":true'),
    'toggle persisted into the settings file in _fs')

  -- Idle, flag on: both WXHB-assigned halves (default wxhb_l/wxhb_r -> set 2)
  -- now render at the standard idle transparency; position 1's own slot 5 is
  -- no longer part of either half.
  assert_eq(true, hud._layers_for_test(1).icon:visible(), 'wxhb_l set 2 slot 1 (Provoke) now visible')
  assert_eq(204,  hud._layers_for_test(1).icon._alpha,    'idle standard transparency (20 -> 204)')
  assert_eq(true, hud._layers_for_test(9).icon:visible(), 'wxhb_r set 2 slot 9 (Fast Blade) now visible')
  assert_eq(204,  hud._layers_for_test(9).icon._alpha,    'idle standard transparency on the right half too')
  assert_eq(false, hud._layers_for_test(5).icon:visible(), 'position 1 no longer feeds either half')

  -- Hold LT: XHB-L engages the left half from active_set (unchanged from
  -- today); the right half is not live, so always-show keeps rendering
  -- wxhb_r's content there, now at transparency_standard instead of inactive.
  key(KEY_LT, true)
  windower._run_scheduled()
  assert_eq('xhb_l', gamepad.get_display_mode(), 'hold engaged XHB-L')
  assert_eq(true, hud._layers_for_test(5).icon:visible(), 'live left half shows active_set slot 5 again')
  assert_eq(255,  hud._layers_for_test(5).icon._alpha,    'live half renders at the active transparency')
  assert_eq(true, hud._layers_for_test(9).icon:visible(), 'right half keeps showing wxhb_r content while not live')
  assert_eq(204,  hud._layers_for_test(9).icon._alpha,
    'right half renders at standard, not the inactive alpha it would use without the flag')

  key(KEY_LT, false)
  windower._run_scheduled()
  assert_eq(nil, gamepad.get_display_mode(), 'display released with the trigger')
end)

-- ---- (m) unload with the crossbar features live

test('unload with crossbar state live tears down cleanly (icons closed)', function()
  fake_now = 200
  fresh({ sources = true, job_content = WS_CONTENT })
  local hud = require('hud')
  windower.ffxi._key_items = { 3002 }
  windower._events['incoming chunk'](0x055, string.char(0, 0, 0, 0))
  windower.ffxi._target = { id = 555, name = 'Worm', hpp = 100 }
  windower._events['action'](ws_act(32, 555))
  windower._events['prerender']()
  assert_eq(true, hud._sc_timer_for_test():visible(), 'live skillchain display before unload')

  -- icons.close() runs inside unload; with no extraction this session it
  -- must be a clean no-op. A real extraction handle is not reachable
  -- end-to-end here: nothing calls icons.item_icon at runtime yet, and the
  -- fake-io swap only takes effect before crossbar/icon_extractor first
  -- loads. test_icons covers close() over an open fake handle.
  windower._commands = {}
  local ok, err = pcall(function() windower._events['unload']() end)
  assert(ok, 'unload must not error: ' .. tostring(err))
  assert_eq(16, #windower._commands, 'exactly 16 unbind commands on unload')
  assert_eq(nil, hud._label_for_test(),    'HUD destroyed')
  assert_eq(nil, hud._sc_timer_for_test(), 'sc_timer destroyed with the HUD')
  windower.ffxi._key_items = {}
end)

-- ---- suite hygiene: leave no real instances behind for later files

clear_xivgamepad_modules()
settings.discard()
os.clock = real_clock
windower._reset()

io.write(string.format('test_integration: %d passed, %d failed\n', pass, fail))
if fail > 0 then
  error(fail .. ' test(s) failed in test_integration.lua')
end
