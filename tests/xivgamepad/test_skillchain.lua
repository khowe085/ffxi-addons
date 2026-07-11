-- Tests for xivgamepad/skillchain.lua driving the REAL ported lib
-- (crossbar/skillchain/skillchains.lua + skills.lua) through the adapter,
-- over the mock's Wave-0 shims (lists/sets/luau/pack/fake ActionPacket).
--
-- Action fixtures follow the fake-ActionPacket field mapping documented in
-- mock_windower.lua. Time is controlled by replacing os.clock with a settable
-- fake (installed before the modules load, restored at file end). Fixture
-- mutations only -- no shared-mock edits were needed: player identity via
-- windower.ffxi._player.id, target via windower.ffxi._target (the lib reads
-- targ.hpp), login state via windower.ffxi._info.logged_in.

local log_stub = { _lines = {} }
local function record_log(fmt, ...) table.insert(log_stub._lines, tostring(fmt)) end
log_stub.debug, log_stub.info, log_stub.error = record_log, record_log, record_log
package.loaded['log'] = log_stub

-- Earlier manifest files mutate the shared res fixtures; re-establish every
-- entry the lib dereferences (prerender reads res[res_key][id].name).
res.weapon_skills[32]  = { id = 32,  en = 'Fast Blade',      name = 'Fast Blade',      skill = 2,  prefix = '/weaponskill', element = 15, targets = 32 }
res.weapon_skills[33]  = { id = 33,  en = 'Red Lotus Blade', name = 'Red Lotus Blade', skill = 2,  prefix = '/weaponskill', element = 0,  targets = 32 }
res.spells[144]        = { id = 144, en = 'Fire',            name = 'Fire',            skill = 36, prefix = '/magic', type = 'BlackMagic', mp_cost = 7, recast_id = 144, element = 0, targets = 32 }
res.job_abilities[5]   = { id = 5,   en = 'Provoke',         name = 'Provoke',         prefix = '/jobability', type = 'JobAbility', recast_id = 5, element = 15, tp_cost = 0, targets = 32 }

local PLAYER_ID = 999
local TARGET_ID = 1234

local fake_now = 0
local real_clock = os.clock
os.clock = function() return fake_now end

local enabled_flag = true
local sc

local function reload(skip_init)
  package.loaded['skillchain'] = nil
  package.loaded['crossbar/skillchain/skillchains'] = nil
  package.loaded['crossbar/skillchain/skills'] = nil
  sc = require('skillchain')
  if not skip_init then
    sc.init({ enabled = function() return enabled_flag end })
  end
end

local function fresh(t0)
  fake_now = t0
  enabled_flag = true
  windower._reset()
  windower.ffxi._player.id = PLAYER_ID
  windower.ffxi._info.logged_in = true
  windower.ffxi._target = { id = TARGET_ID, name = 'Target Dummy', hpp = 100 }
  reload()
  sc.on_login()
end

-- Fixture per the mock's documented fake-ActionPacket schema. Defaults model
-- a weapon-skill finish (category 3, message 185) by the player on the
-- default target; get_spell()'s param falls back to act.param.
local function make_act(opts)
  return {
    category = opts.category or 3,
    actor_id = opts.actor or PLAYER_ID,
    param    = opts.param or opts.action_id,
    targets  = { {
      id      = opts.target or TARGET_ID,
      actions = { {
        message    = opts.message or 185,
        add_effect = opts.add_effect,
        resource   = opts.resource or 'weapon_skills',
        action_id  = opts.action_id,
        conclusion = opts.conclusion,
      } },
    } },
  }
end

-- 0x63 buff-state chunk against the pack shim's little-endian layout: the lib
-- checks byte 5 == 9, then reads 32 unsigned shorts at offsets 9, 11, .. 71.
local function buff_chunk(buff_ids)
  local bytes = { string.char(0, 0, 0, 0, 9, 0, 0, 0) }
  for n = 1, 32 do
    local id = buff_ids[n] or 0
    bytes[#bytes + 1] = string.char(id % 256, math.floor(id / 256))
  end
  return table.concat(bytes)
end

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

local function assert_near(expected, actual, msg, eps)
  eps = eps or 0.01
  if type(actual) ~= 'number' or math.abs(expected - actual) > eps then
    error(string.format('%s\n    expected: %s (+/- %s)\n      actual: %s',
      msg or 'values not near', tostring(expected), tostring(eps), tostring(actual)), 2)
  end
end

-- ----

test('loads and no-ops safely with no player logged in', function()
  fake_now = 50
  enabled_flag = true
  windower._reset()
  windower.ffxi._player = nil
  reload()
  sc.on_action(make_act({ action_id = 32 }))
  sc.on_login()
  sc.on_job_change('WAR')
  sc.tick()
  assert_eq(nil, sc.window(), 'window nil with no player')
  assert_eq(nil, sc.prop_for(33, 'weapon_skills'), 'prop_for nil with no player')
end)

test('single WS opens resonance: delay counts down into a step-scaled window', function()
  fresh(100)
  sc.on_action(make_act({ action_id = 32 }))
  local d, w = sc.window()
  assert_near(3, d, 'full delay pending right after the WS')
  assert_near(10, w, 'step-1 window = delay + 8 - step')
  assert_eq(nil, sc.prop_for(33, 'weapon_skills'), 'no property during the delay')
  sc.tick()
  fake_now = 104
  sc.tick()
  d, w = sc.window()
  assert_near(0, d, 'delay elapsed')
  assert_near(6, w, 'window remaining after 4s')
end)

test('prop_for returns the chain property for an eligible WS, nil for ineligible', function()
  fresh(100)
  sc.on_action(make_act({ action_id = 32 }))
  fake_now = 104
  assert_eq('Liquefaction', sc.prop_for(33, 'weapon_skills'), 'Burning Blade follows Scission')
  assert_eq(nil, sc.prop_for(32, 'weapon_skills'), 'Scission cannot follow Scission')
  assert_eq(nil, sc.prop_for(9999, 'weapon_skills'), 'unknown id')
  assert_eq(nil, sc.prop_for(32, 'no_such_resource'), 'unknown resource')
end)

test('two-step chain advances and a third eligible WS follows sc_info', function()
  fresh(200)
  sc.on_action(make_act({ action_id = 32 }))
  fake_now = 204
  sc.on_action(make_act({ action_id = 33,
    add_effect = { message_id = 288, animation = 'liquefaction' }, conclusion = true }))
  local d, w = sc.window()
  assert_near(3, d, 'step-2 delay restarts')
  assert_near(9, w, 'step-2 window = delay + 8 - 2')
  fake_now = 208
  assert_eq('Scission', sc.prop_for(32, 'weapon_skills'), 'Scission follows Liquefaction')
  assert_eq('Fusion', sc.prop_for(1, 'weapon_skills'), 'Impaction on Liquefaction yields Fusion')
  assert_eq(nil, sc.prop_for(33, 'weapon_skills'), 'Liquefaction cannot follow itself')
  sc.tick()
  sc.on_action(make_act({ action_id = 32,
    add_effect = { message_id = 289, animation = 'scission' }, conclusion = true }))
  fake_now = 212
  assert_eq('Liquefaction', sc.prop_for(33, 'weapon_skills'), 'step-3 props follow sc_info.Scission')
  d, w = sc.window()
  assert_near(0, d, 'step-3 delay elapsed')
  assert_near(4, w, 'step-3 window = delay + 8 - 3, one second in')
end)

test('window expiry: prop_for goes nil, window dead, tick purges later', function()
  fresh(300)
  sc.on_action(make_act({ action_id = 32 }))
  fake_now = 311
  assert_eq(nil, sc.prop_for(33, 'weapon_skills'), 'no property past the window')
  local d, w = sc.window()
  assert_near(0, d, 'delay long gone')
  assert_true(w <= 0, 'window dead, got ' .. tostring(w))
  fake_now = 321
  sc.tick()
  d, w = sc.window()
  assert_eq(0, d, 'resonance purged 10s past expiry')
  assert_eq(0, w, 'window empty after purge')
end)

test('completion add_effect with no prior resonance restarts state at step 2', function()
  fresh(400)
  sc.on_action(make_act({ action_id = 33,
    add_effect = { message_id = 385, animation = 'liquefaction' }, conclusion = true }))
  fake_now = 404
  assert_eq('Scission', sc.prop_for(32, 'weapon_skills'), 'restarted chain is live')
  local d, w = sc.window()
  assert_near(0, d, 'delay elapsed')
  assert_near(5, w, 'seeded at step 2: delay + 8 - 2, four seconds in')
end)

test('five completion steps close the chain: no props inside a live window', function()
  fresh(500)
  sc.on_action(make_act({ action_id = 32 }))
  local ids   = { 33, 32, 33, 32, 33 }
  local anims = { 'liquefaction', 'scission', 'liquefaction', 'scission', 'liquefaction' }
  for i = 1, 5 do
    fake_now = 500 + i
    sc.on_action(make_act({ action_id = ids[i],
      add_effect = { message_id = 288, animation = anims[i] }, conclusion = true }))
  end
  fake_now = 508.5
  assert_eq(nil, sc.prop_for(32, 'weapon_skills'), 'closed chain yields no props')
  local d, w = sc.window()
  assert_near(0, d, 'delay elapsed')
  assert_true(w > 0, 'window itself still ticking, got ' .. tostring(w))
  sc.tick()
  d, w = sc.window()
  assert_eq(0, d, 'closed resonance purged by tick')
  assert_eq(0, w, 'window empty after purge')
end)

test('chainbound (message 529) seeds chainbound state', function()
  fresh(600)
  sc.on_action(make_act({ category = 6, param = 1, message = 529,
    resource = 'job_abilities', action_id = 5 }))
  local d, w = sc.window()
  assert_near(2, d, 'chainbound delay is 2')
  assert_near(9, w, 'chainbound window = 2 + 8 - 1')
  fake_now = 602.5
  assert_eq('Fusion', sc.prop_for(1, 'weapon_skills'), 'Impaction chains off the Lv.1 chainbound list')
  sc.tick()
end)

test('0x63 buff chunk drives the SCH Immanence branch; buff consumed by one cast', function()
  fresh(700)
  sc.on_incoming_chunk(0x63, buff_chunk({ 470 }))
  sc.on_action(make_act({ category = 4, param = 144, message = 2,
    resource = 'spells', action_id = 144 }))
  local d, w = sc.window()
  assert_near(3, d, 'spell opened resonance under Immanence')
  assert_near(10, w, 'spell resonance window')
  fake_now = 704
  assert_eq('Scission', sc.prop_for(32, 'weapon_skills'), 'WS follows the spell property')
  sc.tick()
  windower.ffxi._target = { id = 5678, name = 'Other Dummy', hpp = 100 }
  sc.on_action(make_act({ category = 4, param = 144, message = 2,
    resource = 'spells', action_id = 144, target = 5678 }))
  d, w = sc.window()
  assert_eq(0, d, 'Immanence spent: second cast opens nothing')
  assert_eq(0, w, 'no window on the second target')
end)

test('zone change clears resonance', function()
  fresh(800)
  sc.on_action(make_act({ action_id = 32 }))
  fake_now = 804
  assert_eq('Liquefaction', sc.prop_for(33, 'weapon_skills'), 'chain live before zoning')
  sc.on_zone_change()
  assert_eq(nil, sc.prop_for(33, 'weapon_skills'), 'no property after zoning')
  local d, w = sc.window()
  assert_eq(0, d, 'no delay after zoning')
  assert_eq(0, w, 'no window after zoning')
end)

test('logout clears state and is repeat-safe', function()
  fresh(900)
  sc.on_action(make_act({ action_id = 32 }))
  fake_now = 904
  sc.on_logout()
  assert_eq(nil, sc.prop_for(33, 'weapon_skills'), 'no property after logout')
  local d, w = sc.window()
  assert_eq(0, d, 'no delay after logout')
  assert_eq(0, w, 'no window after logout')
  sc.on_logout()
end)

test('job_change with a job abbreviation does not raise', function()
  fresh(1000)
  sc.on_job_change('SCH')
  sc.on_job_change('SCH')
  sc.on_job_change('WAR')
end)

test('disabled gate: on_action is ignored', function()
  fresh(1100)
  enabled_flag = false
  sc.on_action(make_act({ action_id = 32 }))
  fake_now = 1104
  assert_eq(nil, sc.prop_for(33, 'weapon_skills'), 'queries nil while disabled')
  assert_eq(nil, sc.window(), 'window nil while disabled')
  enabled_flag = true
  local d, w = sc.window()
  assert_eq(0, d, 'action fired while disabled was dropped')
  assert_eq(0, w, 'no window from the dropped action')
end)

test('disabled gate: queries return nil even mid-chain; state intact on re-enable', function()
  fresh(1200)
  sc.on_action(make_act({ action_id = 32 }))
  fake_now = 1204
  assert_eq('Liquefaction', sc.prop_for(33, 'weapon_skills'), 'chain live while enabled')
  enabled_flag = false
  assert_eq(nil, sc.prop_for(33, 'weapon_skills'), 'prop_for nil mid-chain while disabled')
  assert_eq(nil, sc.window(), 'window nil mid-chain while disabled')
  enabled_flag = true
  assert_eq('Liquefaction', sc.prop_for(33, 'weapon_skills'), 'state intact after re-enable')
end)

test('disabled gate: incoming chunks are ignored', function()
  fresh(1300)
  enabled_flag = false
  sc.on_incoming_chunk(0x63, buff_chunk({ 470 }))
  enabled_flag = true
  sc.on_action(make_act({ category = 4, param = 144, message = 2,
    resource = 'spells', action_id = 144 }))
  local d, w = sc.window()
  assert_eq(0, d, 'no Immanence recorded while disabled')
  assert_eq(0, w, 'spell opened nothing')
end)

test('before init the adapter treats everything as disabled', function()
  fake_now = 1400
  windower._reset()
  reload(true)
  sc.on_action(make_act({ action_id = 32 }))
  assert_eq(nil, sc.window(), 'window nil before init')
  assert_eq(nil, sc.prop_for(33, 'weapon_skills'), 'prop_for nil before init')
end)

-- ----

os.clock = real_clock
windower._reset()
package.loaded['log'] = nil
package.loaded['skillchain'] = nil
package.loaded['crossbar/skillchain/skillchains'] = nil
package.loaded['crossbar/skillchain/skills'] = nil

io.write(string.format('test_skillchain: %d passed, %d failed\n', pass, fail))
if fail > 0 then
  error(fail .. ' test(s) failed in test_skillchain.lua')
end
