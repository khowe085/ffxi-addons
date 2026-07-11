-- Tests for xivgamepad/binder.lua: toggle lifecycle, trigger-held navigation
-- with pause/resume, the empty-slot bind flows (ma with skill sub-menu, ja,
-- ct presets, a, map, ex), the get_mounts mount menu with its Mount Roulette
-- entry, gamedata-driven job-ability category sub-menus, occupied-slot
-- operations (Overlay / Replace / Remove / Swap / Reorder), and overlay-type
-- is_available filtering.
--
-- The log stub is preloaded via package.loaded before requiring the module
-- under test (contracts doc: tests own this stub, never the shared mock).
-- Init opts are faked with a recording save accessor; flows are driven by
-- feeding on_button sequences.

local log_stub = { _debug = {}, _info = {}, _error = {} }
log_stub.debug = function(fmt, ...) table.insert(log_stub._debug, string.format(fmt, ...)) end
log_stub.info  = function(fmt, ...) table.insert(log_stub._info,  string.format(fmt, ...)) end
log_stub.error = function(fmt, ...) table.insert(log_stub._error, string.format(fmt, ...)) end
package.loaded['log'] = log_stub

local binder = require('binder')

-- Isolate the action registry: the binder enumerates the LIVE overlay-type
-- registry of whatever action instance it is handed, and other suite files
-- (test_action) register extra types on the shared instance. Require a fresh,
-- private instance for these tests and restore the previous one at file end,
-- so no registrations leak in either direction and no test depends on
-- manifest order.
local prior_action = package.loaded['action']
package.loaded['action'] = nil
local action = require('action')

-- Augment shared res fixtures by mutation (never edit the mock): spells across
-- the magic skill categories, pet-type job abilities (PetCommand plus two
-- Monster-type BST Ready moves for the gamedata reclassification tests), and
-- a mounts table.
res.spells[57]  = { id = 57,  en = 'Haste',       type = 'WhiteMagic', skill = 34, prefix = '/magic', mp_cost = 40, recast_id = 57 }
res.spells[220] = { id = 220, en = 'Poison',      type = 'BlackMagic', skill = 35, prefix = '/magic', mp_cost = 5,  recast_id = 220 }
res.spells[245] = { id = 245, en = 'Drain',       type = 'BlackMagic', skill = 37, prefix = '/magic', mp_cost = 21, recast_id = 245 }
res.spells[296] = { id = 296, en = 'Carbuncle',   type = 'SummonerPact', skill = 38, prefix = '/magic', mp_cost = 7, recast_id = 296 }
res.spells[378] = { id = 378, en = 'Honor March', type = 'BardSong',   skill = 40, prefix = '/song',  mp_cost = 0,  recast_id = 378 }
res.spells[513] = { id = 513, en = 'Kupipi',      type = 'Trust',      skill = 0,  prefix = '/magic', mp_cost = 0,  recast_id = 513 }
res.spells[623] = { id = 623, en = 'Head Butt',   type = 'BlueMagic',  skill = 43, prefix = '/magic', mp_cost = 12, recast_id = 623 }
res.spells[769] = { id = 769, en = 'Geo-Haste',   type = 'Geomancy',   skill = 44, prefix = '/magic', mp_cost = 46, recast_id = 769 }
res.job_abilities[100] = { id = 100, en = 'Sic', type = 'PetCommand', prefix = '/pet', recast_id = 100 }
res.job_abilities[200] = { id = 200, en = 'Foot Kick',    type = 'Monster', prefix = '/pet', recast_id = 200, tp_cost = 0, element = 15, targets = 32 }
res.job_abilities[201] = { id = 201, en = 'Sheep Charge', type = 'Monster', prefix = '/pet', recast_id = 201, tp_cost = 0, element = 15, targets = 32 }
res.mounts = res.mounts or {}
res.mounts[1] = { id = 1, en = 'Chocobo' }

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

local function deep_copy(v)
  if type(v) ~= 'table' then return v end
  local out = {}
  for k, val in pairs(v) do out[k] = deep_copy(val) end
  return out
end

local function deep_eq(a, b)
  if a == b then return true end
  if type(a) ~= 'table' or type(b) ~= 'table' then return false end
  for k, v in pairs(a) do
    if not deep_eq(v, b[k]) then return false end
  end
  for k in pairs(b) do
    if a[k] == nil then return false end
  end
  return true
end

local function repr(v, depth)
  depth = depth or 0
  if type(v) ~= 'table' then return tostring(v) end
  if depth > 4 then return '{...}' end
  local parts = {}
  for k, val in pairs(v) do
    parts[#parts + 1] = tostring(k) .. '=' .. repr(val, depth + 1)
  end
  table.sort(parts)
  return '{' .. table.concat(parts, ', ') .. '}'
end

local function assert_deep(expected, actual, msg)
  if not deep_eq(expected, actual) then
    error(string.format('%s\n    expected: %s\n      actual: %s',
      msg or 'tables not deep-equal', repr(expected), repr(actual)), 2)
  end
end

-- Recording init-opts fake: get_set serves live set tables, save_set snapshots
-- every write (the binder mutates the live table after saving, so snapshots
-- must be deep copies).
local function make_env(cfg)
  cfg = cfg or {}
  local env = { sets = {}, saves = {}, closes = 0 }
  env.player = {
    buffs      = cfg.buffs or {},
    main_job   = cfg.main_job or 'WAR',
    sub_job    = cfg.sub_job,
    is_mounted = false,
    in_event   = false,
  }
  env.opts = {
    action           = action,
    get_set          = function(position)
      env.sets[position] = env.sets[position] or { slots = {} }
      return env.sets[position]
    end,
    save_set         = function(position, set)
      env.sets[position] = set
      table.insert(env.saves, { position = position, set = deep_copy(set) })
    end,
    get_player_state = function() return env.player end,
    texts            = texts,
    images           = images,
    on_close         = function() env.closes = env.closes + 1 end,
    ct_presets       = cfg.ct_presets,
    get_mounts       = cfg.get_mounts,
    gamedata         = cfg.gamedata,
  }
  return env
end

local function press(name) binder.on_button(name, true) end
local function release(name) binder.on_button(name, false) end
local function tap(name)
  press(name)
  release(name)
end

local function open_binder(ctx)
  binder.toggle(ctx or { active_set = 1, display_mode = 'xhb_l', mode = 'job' })
end

local function setup(cfg)
  if binder.is_open() then binder.close() end
  windower._reset()
  log_stub._debug = {}
  log_stub._info = {}
  log_stub._error = {}
  local env = make_env(cfg)
  binder.init(env.opts)
  return env
end

local function move_to(pred)
  local state = binder._state()
  local target
  for i, item in ipairs(state.items) do
    if pred(item) then
      target = i
      break
    end
  end
  assert(target ~= nil, 'menu item not found in ' .. repr(state.items))
  local delta = target - state.index
  local button = delta >= 0 and 'DPAD_DOWN' or 'DPAD_UP'
  for _ = 1, math.abs(delta) do tap(button) end
  assert_eq(target, binder._state().index, 'selection did not reach the item')
end

local function choose(label_fragment)
  move_to(function(item) return item.label:find(label_fragment, 1, true) ~= nil end)
  tap('A')
end

local function select_index(n)
  move_to(function(item) return binder._state().items[n] == item end)
  tap('A')
end

local function item_labels()
  local labels = {}
  for _, item in ipairs(binder._state().items) do
    labels[#labels + 1] = item.label
  end
  return labels
end

local function last_save(env)
  return env.saves[#env.saves]
end

-- ---- Lifecycle / toggle ----

test('toggle before init logs an error and stays closed', function()
  binder.toggle({ active_set = 1, display_mode = 'xhb_l' })
  assert_eq(false, binder.is_open())
  assert_eq(true, #log_stub._error > 0, 'expected a logged error')
end)

test('init validates required opts', function()
  local ok = pcall(binder.init, { get_set = function() end })
  assert_eq(false, ok, 'init should reject incomplete opts')
  local ok2 = pcall(binder.init, nil)
  assert_eq(false, ok2, 'init should reject nil opts')
end)

test('toggle opens at the slot menu targeting the ctx set and half', function()
  local env = setup()
  binder.toggle({ active_set = 3, display_mode = 'xhb_r', mode = 'shared' })
  local state = binder._state()
  assert_eq(true, state.open)
  assert_eq(false, state.paused, 'open gesture holds a trigger; must not start paused')
  assert_eq(3, state.active_set)
  assert_eq('right', state.half)
  assert_eq('slots', state.menu)
  assert_eq(8, #state.items)
  assert_eq(1, state.index)
  assert_eq(0, #env.saves, 'opening must not write')
end)

test('toggle while open closes and fires on_close', function()
  local env = setup()
  open_binder()
  assert_eq(true, binder.is_open())
  binder.toggle({ active_set = 1, display_mode = 'xhb_l' })
  assert_eq(false, binder.is_open())
  assert_eq(1, env.closes)
end)

test('close is safe when already closed', function()
  local env = setup()
  binder.close()
  assert_eq(false, binder.is_open())
  assert_eq(0, env.closes, 'on_close must not fire for a no-op close')
end)

test('re-init while open closes the session', function()
  local env = setup()
  open_binder()
  binder.init(env.opts)
  assert_eq(false, binder.is_open())
  assert_eq(1, env.closes)
end)

test('on_button is ignored while closed', function()
  setup()
  press('LT')
  press('A')
  tap('DPAD_DOWN')
  assert_eq(false, binder.is_open())
end)

test('UI elements show on open and hide on close', function()
  setup()
  open_binder()
  local ui = binder._ui()
  assert_eq(true, ui.body:visible())
  assert_eq(true, ui.backdrop:visible())
  binder.close()
  assert_eq(false, ui.body:visible())
  assert_eq(false, ui.backdrop:visible())
end)

-- ---- Navigation, pause/resume, close gesture ----

test('d-pad moves the selection while a trigger is held', function()
  setup()
  open_binder()
  tap('DPAD_DOWN')
  tap('DPAD_DOWN')
  assert_eq(3, binder._state().index)
  tap('DPAD_UP')
  assert_eq(2, binder._state().index)
  tap('DPAD_RIGHT')
  assert_eq(3, binder._state().index)
  tap('DPAD_LEFT')
  assert_eq(2, binder._state().index)
end)

test('selection clamps at the menu edges', function()
  setup()
  open_binder()
  tap('DPAD_UP')
  assert_eq(1, binder._state().index)
  for _ = 1, 20 do tap('DPAD_DOWN') end
  assert_eq(8, binder._state().index)
end)

test('releasing all triggers pauses navigation', function()
  setup()
  open_binder()
  tap('DPAD_DOWN')
  release('LT')
  local state = binder._state()
  assert_eq(true, state.paused)
  tap('DPAD_DOWN')
  press('A')
  press('B')
  state = binder._state()
  assert_eq(2, state.index, 'input must be ignored while paused')
  assert_eq('slots', state.menu)
  assert_eq(true, binder.is_open())
end)

test('paused state is indicated in the UI', function()
  setup()
  open_binder()
  release('LT')
  assert_eq(true, binder._ui().status:text():find('PAUSED', 1, true) ~= nil)
  press('RT')
  assert_eq(nil, binder._ui().status:text():find('PAUSED', 1, true))
end)

test('re-holding either trigger resumes navigation', function()
  setup()
  open_binder()
  release('LT')
  assert_eq(true, binder._state().paused)
  press('RT')
  assert_eq(false, binder._state().paused)
  tap('DPAD_DOWN')
  assert_eq(2, binder._state().index)
end)

test('binder stays open across arbitrary button noise while paused', function()
  setup()
  open_binder()
  release('LT')
  local noise = { 'A', 'B', 'X', 'Y', 'LB', 'RB', 'START', 'BACK',
    'DPAD_UP', 'DPAD_DOWN', 'DPAD_LEFT', 'DPAD_RIGHT', 'L4', 'R5', 'TRACKPAD_3' }
  for _, name in ipairs(noise) do tap(name) end
  local state = binder._state()
  assert_eq(true, state.open)
  assert_eq(1, state.index)
  assert_eq('slots', state.menu)
end)

test('unmapped buttons while a trigger is held are ignored without crashing', function()
  setup()
  open_binder()
  tap('DPAD_DOWN')
  for _, name in ipairs({ 'X', 'Y', 'LB', 'RB', 'START', 'L4', 'R5', 'TRACKPAD_2' }) do
    tap(name)
  end
  local state = binder._state()
  assert_eq(true, state.open)
  assert_eq('slots', state.menu)
  assert_eq(2, state.index)
end)

test('B backs up one level; B at the root is a no-op', function()
  setup()
  open_binder()
  tap('A')
  assert_eq('types', binder._state().menu)
  tap('B')
  assert_eq('slots', binder._state().menu)
  tap('B')
  local state = binder._state()
  assert_eq('slots', state.menu)
  assert_eq(true, state.open)
end)

test('BACK with a trigger held closes the binder', function()
  local env = setup()
  open_binder()
  press('BACK')
  assert_eq(false, binder.is_open())
  assert_eq(1, env.closes)
end)

test('BACK while paused does not close the binder', function()
  setup()
  open_binder()
  release('LT')
  press('BACK')
  assert_eq(true, binder.is_open())
end)

-- ---- Empty-slot bind flows ----

test('ma flow: type, skill sub-menu, action, target, confirm writes the binding', function()
  local env = setup()
  open_binder()
  tap('A')
  assert_eq('types', binder._state().menu)
  choose('Magic')
  assert_eq('skills', binder._state().menu)
  choose('Healing')
  assert_eq('actions', binder._state().menu)
  choose('Cure')
  assert_eq('targets', binder._state().menu)
  choose('<me>')
  assert_eq('confirm', binder._state().menu)
  tap('A')
  local save = last_save(env)
  assert_eq(1, save.position)
  assert_deep({ type = 'ma', action = 'Cure', target = 'me' }, save.set.slots[1])
  assert_eq('slots', binder._state().menu, 'confirm must return to the slot list')
  assert_eq(true, binder.is_open())
end)

test('magic sub-menu lists only spells of the chosen skill', function()
  setup()
  open_binder()
  tap('A')
  choose('Magic')
  choose('Healing')
  assert_deep({ 'Cure' }, item_labels())
  tap('B')
  choose('Enfeebling')
  assert_deep({ 'Poison' }, item_labels())
  tap('B')
  choose('Ninjutsu')
  assert_deep({ 'Utsusemi: Ichi' }, item_labels())
  tap('B')
  choose('Song')
  assert_deep({ 'Honor March' }, item_labels())
  tap('B')
  choose('Trust')
  assert_deep({ 'Kupipi' }, item_labels())
end)

test('ja flow skips the skill sub-menu and excludes pet abilities', function()
  local env = setup()
  open_binder()
  tap('DPAD_DOWN')
  tap('A')
  choose('Job Ability')
  assert_eq('actions', binder._state().menu)
  assert_deep({ 'Berserk', 'Provoke' }, item_labels())
  choose('Provoke')
  choose('<t>')
  tap('A')
  local save = last_save(env)
  assert_eq(1, save.position)
  assert_deep({ type = 'ja', action = 'Provoke', target = 't' }, save.set.slots[2])
end)

test('ct flow uses injected presets and skips the target menu', function()
  local env = setup({ ct_presets = { { label = 'Dance!', command = 'input /dance' } } })
  open_binder()
  tap('A')
  choose('Raw Command')
  assert_deep({ 'Dance!' }, item_labels())
  tap('A')
  assert_eq('confirm', binder._state().menu, 'ct must skip the target menu')
  tap('A')
  assert_deep({ type = 'ct', action = 'input /dance', alias = 'Dance!' },
    last_save(env).set.slots[1])
end)

test('ct falls back to built-in presets when none are injected', function()
  setup()
  open_binder()
  tap('A')
  choose('Raw Command')
  local labels = item_labels()
  assert_eq(true, #labels > 0, 'default ct presets must exist')
  assert_eq(true, labels[1]:find('/heal', 1, true) ~= nil)
end)

test('a flow goes straight to the target menu', function()
  local env = setup()
  open_binder()
  tap('A')
  choose('Attack')
  assert_eq('targets', binder._state().menu)
  choose('<bt>')
  tap('A')
  assert_deep({ type = 'a', target = 'bt' }, last_save(env).set.slots[1])
end)

test('map flow confirms directly with no action or target', function()
  local env = setup()
  open_binder()
  tap('A')
  choose('View Map')
  assert_eq('confirm', binder._state().menu)
  tap('A')
  assert_deep({ type = 'map' }, last_save(env).set.slots[1])
end)

test('ex flow lists the display modes and skips the target menu', function()
  local env = setup()
  open_binder()
  tap('A')
  choose('Display Mode')
  assert_eq(6, #binder._state().items)
  choose('WXHB-L')
  assert_eq('confirm', binder._state().menu)
  tap('A')
  assert_deep({ type = 'ex', action = 'wxhb_l' }, last_save(env).set.slots[1])
end)

test('xhb_r half addresses absolute slots 9..16', function()
  local env = setup()
  binder.toggle({ active_set = 2, display_mode = 'xhb_r', mode = 'job' })
  tap('A')
  choose('View Map')
  tap('A')
  local save = last_save(env)
  assert_eq(2, save.position)
  assert_deep({ type = 'map' }, save.set.slots[9])
  assert_eq(nil, save.set.slots[1])
end)

-- ---- Mount menu: get_mounts and the Mount Roulette entry ----

local function owned_mounts()
  return { 'Crab', 'Raptor' }
end

test('mount menu without get_mounts lists every res mount and no roulette', function()
  setup()
  open_binder()
  tap('A')
  choose('Mount')
  local expected = {}
  for _, mount in pairs(res.mounts) do expected[#expected + 1] = mount.en end
  table.sort(expected)
  assert_deep(expected, item_labels())
  for _, label in ipairs(item_labels()) do
    assert_eq(false, label == 'Mount Roulette', 'no roulette entry without get_mounts')
  end
end)

test('mount menu with get_mounts lists owned mounts with Mount Roulette last', function()
  setup({ get_mounts = owned_mounts })
  open_binder()
  tap('A')
  choose('Mount')
  assert_deep({ 'Crab', 'Raptor', 'Mount Roulette' }, item_labels())
end)

test('selecting Mount Roulette skips the target menu and writes the frozen binding', function()
  local env = setup({ get_mounts = owned_mounts })
  open_binder()
  tap('A')
  choose('Mount')
  choose('Mount Roulette')
  assert_eq('confirm', binder._state().menu, 'mount flow must skip the target menu')
  tap('A')
  assert_deep({ type = 'mount', action = 'Mount Roulette' }, last_save(env).set.slots[1])
  assert_eq('slots', binder._state().menu, 'confirm must return to the slot list')
end)

test('selecting an owned mount still writes a plain mount binding', function()
  local env = setup({ get_mounts = owned_mounts })
  open_binder()
  tap('A')
  choose('Mount')
  choose('Raptor')
  assert_eq('confirm', binder._state().menu)
  tap('A')
  assert_deep({ type = 'mount', action = 'Raptor' }, last_save(env).set.slots[1])
end)

-- ---- Job-ability category sub-menus (gamedata) ----

-- Minimal gamedata fake over the frozen categories/list surface, shaped like
-- the generated abilities table: kebab category names, entries carrying
-- en/type ('ja' | 'pet'), sorted output like the real adapter.
local function make_gamedata(fixture)
  return {
    categories = function(res_key)
      if res_key ~= 'job_abilities' then return {} end
      local names = {}
      for category in pairs(fixture) do names[#names + 1] = category end
      table.sort(names)
      return names
    end,
    list = function(res_key, category)
      if res_key ~= 'job_abilities' then return {} end
      local entries = {}
      for _, entry in ipairs(fixture[category] or {}) do entries[#entries + 1] = entry end
      table.sort(entries, function(a, b) return a.en < b.en end)
      return entries
    end,
  }
end

-- The generator mislabels Monster-type (BST Ready) abilities as type='ja'
-- (only blood pacts and pet commands map to 'pet'), so the fixture mirrors
-- that: Foot Kick and Sheep Charge carry type='ja' with ids resolving to
-- Monster-type res.job_abilities rows, and the binder must reclassify them
-- as pet -- hiding 'ready' entirely and filtering them from mixed lists.
local ja_fixture = {
  ['abilities'] = {
    { en = 'Provoke', type = 'ja' },
    { en = 'Berserk', type = 'ja' },
    { en = 'Fight',   type = 'pet' },
    { en = 'Sheep Charge', id = 201, type = 'ja' },
  },
  ['phantom-rolls'] = {
    { en = "Corsair's Roll", type = 'ja' },
    { en = 'Chaos Roll',     type = 'ja' },
  },
  ['quick-draw'] = { { en = 'Fire Shot', type = 'ja' } },
  ['stratagems'] = { { en = 'Penury',    type = 'ja' } },
  ['pet-commands'] = { { en = 'Sic', type = 'pet' } },
  ['ready'] = { { en = 'Foot Kick', id = 200, type = 'ja' } },
}

test('ja flow with gamedata shows readable category labels; pet-only and ready hidden', function()
  setup({ gamedata = make_gamedata(ja_fixture) })
  open_binder()
  tap('A')
  choose('Job Ability')
  assert_eq('ja_categories', binder._state().menu)
  assert_deep({ 'Abilities', 'Phantom Rolls', 'Quick Draw', 'Stratagems' }, item_labels(),
    'pet-commands and ready (all entries pet after res reclassification) must be hidden')
end)

test('choosing a category lists its abilities sorted, pet entries filtered', function()
  setup({ gamedata = make_gamedata(ja_fixture) })
  open_binder()
  tap('A')
  choose('Job Ability')
  choose('Phantom Rolls')
  assert_eq('actions', binder._state().menu)
  assert_deep({ 'Chaos Roll', "Corsair's Roll" }, item_labels())
  tap('B')
  assert_eq('ja_categories', binder._state().menu, 'B must back up to the categories')
  choose('Abilities')
  assert_deep({ 'Berserk', 'Provoke' }, item_labels(),
    'generated-pet (Fight) and res-reclassified Monster (Sheep Charge) entries'
    .. ' must be filtered from ja category lists')
end)

test('ja category flow writes the binding through target and confirm', function()
  local env = setup({ gamedata = make_gamedata(ja_fixture) })
  open_binder()
  tap('A')
  choose('Job Ability')
  choose('Quick Draw')
  choose('Fire Shot')
  assert_eq('targets', binder._state().menu)
  choose('<t>')
  tap('A')
  assert_deep({ type = 'ja', action = 'Fire Shot', target = 't' }, last_save(env).set.slots[1])
end)

test('ja flow with an empty gamedata falls back to the flat res list', function()
  setup({ gamedata = make_gamedata({}) })
  open_binder()
  tap('A')
  choose('Job Ability')
  assert_eq('actions', binder._state().menu)
  assert_deep({ 'Berserk', 'Provoke' }, item_labels())
end)

test('pet and magic flows stay res-driven with gamedata provided', function()
  setup({ gamedata = make_gamedata(ja_fixture) })
  open_binder()
  tap('A')
  choose('Pet Command')
  assert_eq('actions', binder._state().menu)
  assert_deep({ 'Foot Kick', 'Sheep Charge', 'Sic' }, item_labels(),
    'Monster-type Ready moves stay reachable through the pet binding type')
  tap('B')
  choose('Magic')
  assert_eq('skills', binder._state().menu)
  choose('Healing')
  assert_deep({ 'Cure' }, item_labels())
end)

-- ---- Occupied-slot operations ----

local function seed_occupied(env, abs_slot, binding)
  env.sets[1] = env.sets[1] or { slots = {} }
  env.sets[1].slots[abs_slot] = binding
end

test('selecting an occupied slot opens the slot-operations menu', function()
  local env = setup()
  seed_occupied(env, 1, { type = 'ma', action = 'Cure', target = 't' })
  open_binder()
  tap('A')
  assert_eq('slot_ops', binder._state().menu)
  assert_deep({ 'Overlay', 'Replace', 'Remove', 'Swap', 'Reorder Overlays' }, item_labels())
end)

test('Replace clears the base binding and all overlays', function()
  local env = setup()
  seed_occupied(env, 1, {
    type = 'ma', action = 'Cure', target = 't',
    overlays = {
      { overlay_type = 'light_arts', condition = {}, type = 'ma', action = 'Cure III', target = 't' },
    },
  })
  open_binder()
  tap('A')
  choose('Replace')
  assert_eq('types', binder._state().menu)
  choose('Weapon Skill')
  choose('Fast Blade')
  choose('<t>')
  tap('A')
  local slot = last_save(env).set.slots[1]
  assert_deep({ type = 'ws', action = 'Fast Blade', target = 't' }, slot)
  assert_eq(nil, slot.overlays, 'Replace must drop every overlay')
end)

test('backing out of a Replace flow writes nothing', function()
  local env = setup()
  seed_occupied(env, 1, { type = 'ma', action = 'Cure', target = 't' })
  open_binder()
  tap('A')
  choose('Replace')
  choose('Weapon Skill')
  tap('B')
  tap('B')
  tap('B')
  assert_eq('slots', binder._state().menu)
  assert_eq(0, #env.saves)
  assert_eq('Cure', env.sets[1].slots[1].action)
end)

test('confirm title after backing out of an overlay flow into Replace', function()
  local env = setup({ main_job = 'SCH', sub_job = 'WHM' })
  seed_occupied(env, 1, { type = 'ma', action = 'Cure', target = 't' })
  open_binder()
  tap('A')
  choose('Overlay')
  choose('Light Arts')
  tap('B')
  tap('B')
  choose('Replace')
  choose('View Map')
  assert_eq('confirm', binder._state().menu)
  assert_eq(nil, binder._state().breadcrumb:find('overlay', 1, true),
    'Replace confirm must not read as an overlay')
  tap('A')
  assert_deep({ type = 'map' }, last_save(env).set.slots[1])
end)

test('Remove empties the slot immediately', function()
  local env = setup()
  seed_occupied(env, 1, { type = 'ja', action = 'Provoke', target = 't' })
  open_binder()
  tap('A')
  choose('Remove')
  local save = last_save(env)
  assert_eq(1, save.position)
  assert_eq(nil, save.set.slots[1])
  assert_eq('slots', binder._state().menu)
  assert_eq(true, binder._state().items[1].label:find('(empty)', 1, true) ~= nil)
end)

test('Swap exchanges two slots of the displayed half', function()
  local env = setup()
  seed_occupied(env, 1, { type = 'ja', action = 'Provoke', target = 't' })
  seed_occupied(env, 3, { type = 'ma', action = 'Cure', target = 'me' })
  open_binder()
  tap('A')
  choose('Swap')
  assert_eq('swap', binder._state().menu)
  select_index(3)
  local save = last_save(env)
  assert_deep({ type = 'ma', action = 'Cure', target = 'me' }, save.set.slots[1])
  assert_deep({ type = 'ja', action = 'Provoke', target = 't' }, save.set.slots[3])
end)

test('Swap with an empty target slot moves the binding', function()
  local env = setup()
  seed_occupied(env, 1, { type = 'ja', action = 'Provoke', target = 't' })
  open_binder()
  tap('A')
  choose('Swap')
  select_index(3)
  local save = last_save(env)
  assert_eq(nil, save.set.slots[1])
  assert_deep({ type = 'ja', action = 'Provoke', target = 't' }, save.set.slots[3])
end)

test('Overlay appends an entry with the chosen overlay type and condition', function()
  local env = setup({ main_job = 'SCH', sub_job = 'WHM' })
  seed_occupied(env, 1, { type = 'ma', action = 'Cure', target = 't' })
  open_binder()
  tap('A')
  choose('Overlay')
  assert_eq('overlay_types', binder._state().menu)
  choose('Light Arts')
  assert_eq('types', binder._state().menu)
  choose('Magic')
  choose('Healing')
  choose('Cure')
  choose('<me>')
  tap('A')
  local slot = last_save(env).set.slots[1]
  assert_eq('Cure', slot.action, 'base binding must be untouched')
  assert_eq(1, #slot.overlays)
  assert_deep({ overlay_type = 'light_arts', condition = {},
    type = 'ma', action = 'Cure', target = 'me' }, slot.overlays[1])
end)

test('Overlay append preserves existing overlays and appends at the end', function()
  local env = setup({ main_job = 'SCH', sub_job = 'WHM' })
  seed_occupied(env, 1, {
    type = 'ma', action = 'Cure', target = 't',
    overlays = { { overlay_type = 'light_arts', condition = {}, type = 'ma', action = 'Cure III', target = 't' } },
  })
  open_binder()
  tap('A')
  choose('Overlay')
  choose('Subjob')
  choose('Job Ability')
  choose('Berserk')
  choose('<me>')
  tap('A')
  local overlays = last_save(env).set.slots[1].overlays
  assert_eq(2, #overlays)
  assert_eq('light_arts', overlays[1].overlay_type, 'existing overlay must keep its position')
  assert_deep({ overlay_type = 'subjob', condition = { subjob = 'WHM' },
    type = 'ja', action = 'Berserk', target = 'me' }, overlays[2])
end)

test('overlay flow offers noop to blank the base; it confirms directly', function()
  local env = setup({ main_job = 'SCH', sub_job = 'WHM' })
  seed_occupied(env, 1, { type = 'ma', action = 'Cure', target = 't' })
  open_binder()
  tap('A')
  choose('Overlay')
  choose('Light Arts')
  choose('Empty (noop)')
  assert_eq('confirm', binder._state().menu, 'noop must skip the action and target menus')
  tap('A')
  assert_deep({ overlay_type = 'light_arts', condition = {}, type = 'noop' },
    last_save(env).set.slots[1].overlays[1])
end)

test('noop is not offered in the base bind type menu', function()
  setup()
  open_binder()
  tap('A')
  assert_eq('types', binder._state().menu)
  for _, item in ipairs(binder._state().items) do
    assert_eq(false, item.code == 'noop', 'noop must be overlay-only')
  end
end)

test('subjob overlay captures the current subjob as its condition', function()
  local env = setup({ main_job = 'WAR', sub_job = 'WHM' })
  seed_occupied(env, 1, { type = 'ja', action = 'Provoke', target = 't' })
  open_binder()
  tap('A')
  choose('Overlay')
  choose('Subjob')
  choose('Job Ability')
  choose('Berserk')
  choose('<me>')
  tap('A')
  assert_deep({ overlay_type = 'subjob', condition = { subjob = 'WHM' },
    type = 'ja', action = 'Berserk', target = 'me' },
    last_save(env).set.slots[1].overlays[1])
end)

-- ---- Overlay-type filtering (is_available) ----

local function overlay_menu_labels(env)
  seed_occupied(env, 1, { type = 'ma', action = 'Cure', target = 't' })
  open_binder()
  tap('A')
  choose('Overlay')
  return item_labels()
end

test('SCH with a subjob sees subjob and all arts overlay types', function()
  local env = setup({ main_job = 'SCH', sub_job = 'WHM' })
  assert_deep({ 'Addendum: Black', 'Addendum: White', 'Dark Arts', 'Light Arts', 'Subjob' },
    overlay_menu_labels(env))
end)

test('SCH subjob also unlocks the arts overlay types', function()
  local env = setup({ main_job = 'WAR', sub_job = 'SCH' })
  assert_deep({ 'Addendum: Black', 'Addendum: White', 'Dark Arts', 'Light Arts', 'Subjob' },
    overlay_menu_labels(env))
end)

test('non-SCH with a subjob sees only the subjob overlay type', function()
  local env = setup({ main_job = 'WAR', sub_job = 'NIN' })
  assert_deep({ 'Subjob' }, overlay_menu_labels(env))
end)

test('SCH with no subjob sees the arts types but not subjob', function()
  local env = setup({ main_job = 'SCH', sub_job = nil })
  assert_deep({ 'Addendum: Black', 'Addendum: White', 'Dark Arts', 'Light Arts' },
    overlay_menu_labels(env))
end)

test('a runtime-registered overlay type appears when is_available passes', function()
  action.register_overlay_type('pet_out', {
    check        = function() return false end,
    is_available = function(player_state) return player_state.main_job == 'BST' end,
  })
  local env = setup({ main_job = 'BST', sub_job = nil })
  assert_deep({ 'Pet Out' }, overlay_menu_labels(env))
  action.register_overlay_type('pet_out', {
    check        = function() return false end,
    is_available = function() return false end,
  })
end)

test('non-SCH with no subjob sees an empty overlay menu; A is a no-op', function()
  local env = setup({ main_job = 'WAR', sub_job = nil })
  assert_deep({}, overlay_menu_labels(env))
  tap('A')
  assert_eq('overlay_types', binder._state().menu)
  tap('B')
  assert_eq('slot_ops', binder._state().menu)
end)

-- ---- Reorder Overlays ----

local function seed_three_overlays(env)
  seed_occupied(env, 1, {
    type = 'ma', action = 'Cure', target = 't',
    overlays = {
      { overlay_type = 'addendum_white', condition = {}, type = 'ma', action = 'Cure IV', target = 't' },
      { overlay_type = 'light_arts',     condition = {}, type = 'ma', action = 'Cure III', target = 't' },
      { overlay_type = 'dark_arts',      condition = {}, type = 'ma', action = 'Drain', target = 't' },
    },
  })
end

local function overlay_actions(set)
  local out = {}
  for i, entry in ipairs(set.slots[1].overlays) do out[i] = entry.action end
  return out
end

test('Reorder grabs with A, moves with the d-pad, and commits on drop', function()
  local env = setup({ main_job = 'SCH', sub_job = 'WHM' })
  seed_three_overlays(env)
  open_binder()
  tap('A')
  choose('Reorder')
  assert_eq('reorder', binder._state().menu)
  assert_eq(3, #binder._state().items)
  tap('A')
  assert_eq(true, binder._state().grabbed)
  tap('DPAD_DOWN')
  assert_eq(2, binder._state().index, 'grabbed overlay moves with the selection')
  assert_eq(0, #env.saves, 'moving must not write until drop')
  tap('A')
  assert_eq(false, binder._state().grabbed)
  assert_eq(1, #env.saves)
  assert_deep({ 'Cure III', 'Cure IV', 'Drain' }, overlay_actions(last_save(env).set))
end)

test('Reorder clamps at the top edge while grabbed', function()
  local env = setup({ main_job = 'SCH', sub_job = 'WHM' })
  seed_three_overlays(env)
  open_binder()
  tap('A')
  choose('Reorder')
  tap('A')
  tap('DPAD_UP')
  assert_eq(1, binder._state().index)
  tap('A')
  assert_deep({ 'Cure IV', 'Cure III', 'Drain' }, overlay_actions(last_save(env).set))
end)

test('Reorder clamps at the bottom edge while grabbed', function()
  local env = setup({ main_job = 'SCH', sub_job = 'WHM' })
  seed_three_overlays(env)
  open_binder()
  tap('A')
  choose('Reorder')
  tap('DPAD_DOWN')
  tap('DPAD_DOWN')
  assert_eq(3, binder._state().index)
  tap('A')
  tap('DPAD_DOWN')
  assert_eq(3, binder._state().index, 'grabbed overlay must not move past the end')
  tap('A')
  assert_deep({ 'Cure IV', 'Cure III', 'Drain' }, overlay_actions(last_save(env).set))
end)

test('a committed reorder does not alias the live set: discard after commit', function()
  local env = setup({ main_job = 'SCH', sub_job = 'WHM' })
  seed_three_overlays(env)
  open_binder()
  tap('A')
  choose('Reorder')
  tap('A')
  tap('DPAD_DOWN')
  tap('A')
  assert_eq(1, #env.saves)
  assert_deep({ 'Cure III', 'Cure IV', 'Drain' }, overlay_actions(last_save(env).set))
  tap('A')
  tap('DPAD_DOWN')
  tap('B')
  assert_eq(1, #env.saves, 'a discarded grab-move must not save')
  local live = {}
  for i, entry in ipairs(env.sets[1].slots[1].overlays) do live[i] = entry.action end
  assert_deep({ 'Cure III', 'Cure IV', 'Drain' }, live,
    'the discarded working order must not leak into the live set')
  local state = binder._state()
  assert_eq(false, state.grabbed)
  assert_eq(true, state.items[2].label:find('Cure IV', 1, true) ~= nil,
    'menu must rebuild from the committed order')
end)

test('B while grabbed discards the working order without saving', function()
  local env = setup({ main_job = 'SCH', sub_job = 'WHM' })
  seed_three_overlays(env)
  open_binder()
  tap('A')
  choose('Reorder')
  tap('A')
  tap('DPAD_DOWN')
  tap('B')
  local state = binder._state()
  assert_eq('reorder', state.menu, 'B while grabbed must not pop the menu')
  assert_eq(false, state.grabbed)
  assert_eq(0, #env.saves)
  assert_eq(true, state.items[1].label:find('Cure IV', 1, true) ~= nil,
    'original order must be restored')
  tap('B')
  assert_eq('slot_ops', binder._state().menu)
end)

-- ---- Rendering ----

test('body renders a selection cursor and title renders the breadcrumb', function()
  setup()
  open_binder()
  tap('A')
  choose('Magic')
  tap('DPAD_DOWN')
  local ui = binder._ui()
  assert_eq(true, ui.title:text():find('Slots > Type > Magic', 1, true) ~= nil)
  local first_two = {}
  for line in ui.body:text():gmatch('[^\n]+') do first_two[#first_two + 1] = line end
  assert_eq(true, first_two[1]:sub(1, 2) == '  ')
  assert_eq(true, first_two[2]:sub(1, 2) == '> ')
end)

test('slot labels show binding descriptions and overlay counts', function()
  local env = setup()
  seed_occupied(env, 1, {
    type = 'ma', action = 'Cure', target = 't',
    overlays = { { overlay_type = 'light_arts', condition = {}, type = 'ma', action = 'Cure III', target = 't' } },
  })
  open_binder()
  local labels = item_labels()
  assert_eq(true, labels[1]:find('Cure [+1]', 1, true) ~= nil)
  assert_eq(true, labels[2]:find('(empty)', 1, true) ~= nil)
end)

-- ----

-- Restore the shared action instance (see the isolation note at the top)
-- before reporting, so it happens even when this file fails the suite.
package.loaded['action'] = prior_action

io.write(string.format('test_binder: %d passed, %d failed\n', pass, fail))
if fail > 0 then
  error(fail .. ' test(s) failed in test_binder.lua')
end
