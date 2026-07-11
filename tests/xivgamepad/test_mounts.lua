-- Tests for xivgamepad/mounts.lua (frozen adapter API: refresh / list /
-- ride_random / has_mounts) driving the REAL ported crossbar/mountroulette
-- lib over the shared mock's key-item, res.mounts and res.key_items fixtures.
--
-- The log stub is preloaded via package.loaded before requiring the module
-- under test (contracts doc: tests own this stub, never the shared mock);
-- it is restored — and the modules under test cleared — at file end.

-- test_binder (earlier in the manifest) overwrites res.mounts[1] with a
-- name-less entry; the ported lib snapshots res.mounts at require time and
-- reads .name, so re-establish the mock's canonical mount fixtures by
-- mutation BEFORE the fresh require below.
res.mounts[1] = { id = 1, en = 'Raptor',  name = 'Raptor' }
res.mounts[2] = { id = 2, en = 'Crab',    name = 'Crab' }
res.mounts[3] = { id = 3, en = 'Chocobo', name = 'Chocobo' }

local prior_log = package.loaded['log']
local log_stub = { _debug = {}, _info = {}, _error = {} }
log_stub.debug = function(fmt, ...) table.insert(log_stub._debug, string.format(fmt, ...)) end
log_stub.info  = function(fmt, ...) table.insert(log_stub._info,  string.format(fmt, ...)) end
log_stub.error = function(fmt, ...) table.insert(log_stub._error, string.format(fmt, ...)) end
package.loaded['log'] = log_stub

-- Fresh instances after a clean mock state: the require below is what proves
-- the PORT edits (no event registration, no require-time key-item read).
windower._reset()
package.loaded['mounts'] = nil
package.loaded['crossbar/mountroulette'] = nil
local mounts = require('mounts')
local required_with_event = next(windower._events) ~= nil

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

local function assert_list_eq(expected, actual, msg)
  assert_eq(#expected, #actual, (msg or 'list') .. ' length')
  for i = 1, #expected do
    assert_eq(expected[i], actual[i], (msg or 'list') .. '[' .. i .. ']')
  end
end

-- Reset the mock, hand the player the given key items (and optional buffs),
-- and rederive owned mounts — every test starts from explicit state.
local function fresh(key_items, buffs)
  windower._reset()
  windower.ffxi._key_items = key_items or {}
  if buffs then
    windower.ffxi._player.buffs = buffs
  end
  mounts.refresh()
end

-- Deterministic randomness, technique pinned: swap math.random for a stub and
-- restore it afterwards. Seeding via math.randomseed would NOT be
-- deterministic here — the seed-to-sequence mapping is interpreter/platform
-- dependent, and the ported lib already reseeded with os.time() at require
-- time. The call is pcall-guarded so math.random is restored even on error.
local function with_fixed_random(value, fn)
  local real_random = math.random
  math.random = function() return value end
  local ok, err = pcall(fn)
  math.random = real_random
  if not ok then error(err, 2) end
end

-- ----

test('require registers no windower events and starts with no owned mounts', function()
  assert_eq(false, required_with_event, 'no event registered at require time')
  windower._reset()
  assert_eq(false, mounts.has_mounts(), 'no owned mounts before any refresh')
end)

test('refresh derives exactly the owned set from key items', function()
  fresh({ 3001, 3002 })
  assert_list_eq({ 'Crab', 'Raptor' }, mounts.list(), 'owned mounts')
end)

test('refresh follows key-item changes: added KI appears, removed KI disappears', function()
  fresh({ 3001 })
  assert_list_eq({ 'Raptor' }, mounts.list(), 'initial owned set')
  windower.ffxi._key_items = { 3001, 3003 }
  mounts.refresh()
  assert_list_eq({ 'Chocobo', 'Raptor' }, mounts.list(), 'after adding a KI')
  windower.ffxi._key_items = { 3003 }
  mounts.refresh()
  assert_list_eq({ 'Chocobo' }, mounts.list(), 'after removing a KI')
end)

test("trainer's whistle never appears among owned mounts", function()
  fresh({ 3001, 3004 })
  assert_list_eq({ 'Raptor' }, mounts.list(), 'whistle excluded alongside a real mount')
  fresh({ 3004 })
  assert_eq(false, mounts.has_mounts(), 'whistle alone owns nothing')
  assert_list_eq({}, mounts.list(), 'whistle alone lists nothing')
end)

test('non-mount and unknown key items are ignored', function()
  fresh({ 3005, 9999, 3002 })
  assert_list_eq({ 'Crab' }, mounts.list(), 'only the Mounts-category KI counts')
end)

test('list returns sorted res.mounts display names, not lib-internal lowercase', function()
  fresh({ 3003, 3001, 3002 })
  assert_list_eq({ 'Chocobo', 'Crab', 'Raptor' }, mounts.list(), 'sorted display names')
end)

test('list skips an owned mount with no res.mounts display entry and logs a diagnostic', function()
  fresh({ 3001, 3002 })
  local raptor = res.mounts[1]
  res.mounts[1] = nil
  local ok, err = pcall(function()
    log_stub._debug = {}
    assert_list_eq({ 'Crab' }, mounts.list(), 'unmatched mount skipped')
    assert_eq(1, #log_stub._debug, 'one diagnostic logged')
    assert(log_stub._debug[1]:find('raptor', 1, true), 'diagnostic names the mount: ' .. log_stub._debug[1])
  end)
  res.mounts[1] = raptor
  assert(ok, tostring(err))
end)

test('has_mounts is false with no mounts and true with one', function()
  fresh({})
  assert_eq(false, mounts.has_mounts(), 'no key items')
  fresh({ 3002 })
  assert_eq(true, mounts.has_mounts(), 'one owned mount')
end)

test('ride_random while mounted (buff 252) sends exactly /dismount', function()
  fresh({ 3001 }, { 100, 252 })
  mounts.ride_random()
  assert_eq(1, #windower._commands, 'exactly one command')
  assert_eq('input /dismount', windower._commands[1], 'dismount command')
end)

test('ride_random unmounted with one owned mount sends the exact /mount command', function()
  fresh({ 3001 })
  with_fixed_random(0.5, function()
    mounts.ride_random()
  end)
  assert_eq(1, #windower._commands, 'exactly one command')
  -- The lib sends the res.mounts name it stored (lowercased) — upstream
  -- behavior, unchanged by the port; display casing is list()'s concern.
  assert_eq('input /mount "raptor"', windower._commands[1], 'mount command')
end)

test('ride_random with several owned mounts picks from the owned set (top of range)', function()
  fresh({ 3001, 3002, 3003 })
  with_fixed_random(0.999, function()
    mounts.ride_random()
  end)
  assert_eq(1, #windower._commands, 'exactly one command')
  local name = windower._commands[1]:match('^input /mount "(%a+)"$')
  assert(name, 'well-formed mount command: ' .. windower._commands[1])
  local owned = { raptor = true, crab = true, chocobo = true }
  assert(owned[name], 'picked an owned mount: ' .. name)
end)

test('ride_random with zero owned mounts sends nothing and does not raise', function()
  fresh({})
  mounts.ride_random()
  assert_eq(0, #windower._commands, 'no command sent')
end)

test('logged out: refresh/list/ride_random/has_mounts are all safe no-ops', function()
  fresh({ 3001 })
  windower.ffxi._player = nil
  mounts.refresh()
  mounts.ride_random()
  assert_eq(0, #windower._commands, 'no command sent while logged out')
  assert_eq(false, mounts.has_mounts(), 'has_mounts false while logged out')
  assert_list_eq({}, mounts.list(), 'list empty while logged out')
end)

-- ----

-- Restore the shared harness state for later manifest files: the prior log
-- module goes back, the modules under test are cleared so the next consumer
-- loads fresh instances, and the mock is reset.
package.loaded['log'] = prior_log
package.loaded['mounts'] = nil
package.loaded['crossbar/mountroulette'] = nil
windower._reset()

io.write(string.format('test_mounts: %d passed, %d failed\n', pass, fail))
if fail > 0 then
  error(fail .. ' test(s) failed in test_mounts.lua')
end
