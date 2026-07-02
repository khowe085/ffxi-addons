-- Tests for xivgamepad/storage.lua: shared.json / job.json persistence.
--
-- Preloads a recording stub for xivgamepad.log (contracts.md: never stub
-- addon modules in the shared mock_windower; test files own this) before
-- requiring the module under test, so log.error calls on corrupt JSON are
-- observable without depending on the real logger module existing yet.

local log_calls = {}
package.loaded['xivgamepad.log'] = {
  debug = function() end,
  info  = function() end,
  error = function(fmt, ...) table.insert(log_calls, string.format(fmt, ...)) end,
}

local storage = require('xivgamepad.storage')

local pass = 0
local fail = 0

local function test(name, fn)
  log_calls = {}
  windower._reset()
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

local function assert_deep_eq(expected, actual, msg)
  if not deep_eq(expected, actual) then
    error((msg or 'tables not deep-equal'), 2)
  end
end

local win_path  = [[C:\Program Files (x86)\Windower4\addons\xivgamepad\]]
local unix_path = '/addon/'

-- A representative sets table exercising every requirement: sparse positions
-- (only 2 and 7 populated), sparse slots (1, 8, 16), a slot with two ordered
-- overlays, and all base binding field types.
local function sample_sets()
  return {
    [2] = {
      slots = {
        [1] = {
          type = 'ma', action = 1, target = 'me', alias = 'Cure',
          icon = 'cure.png', equip_slot = nil, warmup = 1.5, cooldown = 0,
          usable = true,
          overlays = {
            { overlay_type = 'light_arts', condition = {}, action = 2, alias = 'Cure II' },
            { overlay_type = 'subjob', condition = { subjob = 'WHM' }, action = 3, alias = 'Cure III' },
          },
        },
        [8] = {
          type = 'ja', action = 5, target = 't', alias = 'Provoke',
          icon = nil, equip_slot = nil, warmup = 0, cooldown = 30,
          usable = false, overlays = {},
        },
        [16] = {
          type = 'item', action = 4116, target = 'me', alias = 'Hi-Potion',
          icon = 'hipotion.png', equip_slot = nil, warmup = 0, cooldown = 1,
          usable = true, overlays = {},
        },
      },
    },
    [7] = {
      slots = {
        [1] = {
          type = 'ws', action = 32, target = 't', alias = 'Fast Blade',
          icon = 'fastblade.png', equip_slot = nil, warmup = 0, cooldown = 0,
          usable = true, overlays = {},
        },
      },
    },
  }
end

-- ----

test('load_shared on missing file returns {} with no dir creation, no writes', function()
  local result = storage.load_shared(win_path, 'TestChar')
  assert_deep_eq({}, result, 'result must be empty table')
  assert_eq(0, #windower._created_dirs, 'no dirs created on load')
  local any_fs = false
  for _ in pairs(windower._fs) do any_fs = true end
  assert_eq(false, any_fs, 'no files written on load')
end)

test('load_job on missing file returns {} with no dir creation, no writes', function()
  local result = storage.load_job(win_path, 'TestChar')
  assert_deep_eq({}, result, 'result must be empty table')
  assert_eq(0, #windower._created_dirs, 'no dirs created on load')
end)

test('save_shared constructs the exact expected Windows path and creates data + data\\TestChar dirs', function()
  storage.save_shared(win_path, 'TestChar', { [1] = { slots = {} } })

  -- files-API paths are addon-relative (the real library prefixes
  -- windower.addon_path onto every operation); separators match addon_path.
  local expected_path = [[data\TestChar\shared.json]]
  assert(windower._fs[expected_path] ~= nil, 'file must exist at the exact expected relative path')

  local expected_data_dir = [[C:\Program Files (x86)\Windower4\addons\xivgamepad\data]]
  local expected_char_dir = [[C:\Program Files (x86)\Windower4\addons\xivgamepad\data\TestChar]]
  assert_eq(2, #windower._created_dirs, 'exactly two dirs created')
  assert_eq(expected_data_dir, windower._created_dirs[1], 'data dir created first')
  assert_eq(expected_char_dir, windower._created_dirs[2], 'char dir created second')
  for _, dir in ipairs(windower._created_dirs) do
    assert(not dir:find('/', 1, true), 'no forward slash in: ' .. dir)
  end
end)

test('save_job constructs the exact expected Windows path and creates data + data\\TestChar dirs', function()
  storage.save_job(win_path, 'TestChar', { WAR = { [1] = { slots = {} } } })

  local expected_path = [[data\TestChar\job.json]]
  assert(windower._fs[expected_path] ~= nil, 'file must exist at the exact expected relative path')

  local expected_data_dir = [[C:\Program Files (x86)\Windower4\addons\xivgamepad\data]]
  local expected_char_dir = [[C:\Program Files (x86)\Windower4\addons\xivgamepad\data\TestChar]]
  assert_eq(2, #windower._created_dirs, 'exactly two dirs created')
  assert_eq(expected_data_dir, windower._created_dirs[1], 'data dir created first')
  assert_eq(expected_char_dir, windower._created_dirs[2], 'char dir created second')
end)

test('save_shared then load_shared round-trips a representative sparse sets table exactly', function()
  local sets = sample_sets()
  storage.save_shared(win_path, 'TestChar', sets)
  local loaded = storage.load_shared(win_path, 'TestChar')
  assert_deep_eq(sets, loaded, 'round-tripped sets must deep-equal the original')

  -- Sparse positions preserved: only 2 and 7 present, 1/3..6/8 absent.
  assert(loaded[2] ~= nil, 'position 2 present')
  assert(loaded[7] ~= nil, 'position 7 present')
  assert_eq(nil, loaded[1], 'position 1 absent')
  assert_eq(nil, loaded[3], 'position 3 absent')

  -- Sparse slots preserved: only 1, 8, 16 present in position 2.
  assert(loaded[2].slots[1] ~= nil, 'slot 1 present')
  assert(loaded[2].slots[8] ~= nil, 'slot 8 present')
  assert(loaded[2].slots[16] ~= nil, 'slot 16 present')
  assert_eq(nil, loaded[2].slots[2], 'slot 2 absent')
  assert_eq(nil, loaded[2].slots[15], 'slot 15 absent')

  -- Overlay ordering preserved (array, not object).
  assert_eq(2, #loaded[2].slots[1].overlays, 'two overlays on slot 1')
  assert_eq('light_arts', loaded[2].slots[1].overlays[1].overlay_type, 'overlay 1 order')
  assert_eq('subjob', loaded[2].slots[1].overlays[2].overlay_type, 'overlay 2 order')
  assert_eq('WHM', loaded[2].slots[1].overlays[2].condition.subjob, 'overlay condition field')

  -- Field-type spot checks: string, number, boolean, nil-omitted field.
  assert_eq('Cure', loaded[2].slots[1].alias, 'string field')
  assert_eq(1, loaded[2].slots[1].action, 'number field')
  assert_eq(true, loaded[2].slots[1].usable, 'boolean true field')
  assert_eq(false, loaded[2].slots[8].usable, 'boolean false field')
end)

test('job.json keyed by two jobs (SCH, WAR); loading returns both', function()
  local jobs = {
    SCH = { [1] = { slots = { [1] = { type = 'ma', action = 1, usable = true, overlays = {} } } } },
    WAR = { [1] = { slots = { [1] = { type = 'ws', action = 32, usable = true, overlays = {} } } } },
  }
  storage.save_job(win_path, 'TestChar', jobs)
  local loaded = storage.load_job(win_path, 'TestChar')

  assert(loaded.SCH ~= nil, 'SCH present')
  assert(loaded.WAR ~= nil, 'WAR present')
  assert_eq('ma', loaded.SCH[1].slots[1].type, 'SCH slot type')
  assert_eq('ws', loaded.WAR[1].slots[1].type, 'WAR slot type')
  assert_deep_eq(jobs, loaded, 'full job table round-trips')
end)

test('corrupt JSON in shared.json returns {}, logs an error, and leaves the file untouched', function()
  local path = [[data\TestChar\shared.json]]
  windower._fs[path] = '{ this is not valid json !!!'

  local result = storage.load_shared(win_path, 'TestChar')

  assert_deep_eq({}, result, 'corrupt load returns empty table')
  assert(#log_calls > 0, 'log.error must be called on corrupt JSON')
  assert_eq('{ this is not valid json !!!', windower._fs[path],
    'a failed load must never modify the file on disk')
  assert_eq(0, #windower._created_dirs, 'a failed load must not create directories')
end)

test('corrupt JSON in job.json returns {}, logs an error, and leaves the file untouched', function()
  local path = [[data\TestChar\job.json]]
  windower._fs[path] = '{"SCH": [1,2,'

  local result = storage.load_job(win_path, 'TestChar')

  assert_deep_eq({}, result, 'corrupt load returns empty table')
  assert(#log_calls > 0, 'log.error must be called on corrupt JSON')
  assert_eq('{"SCH": [1,2,', windower._fs[path], 'a failed load must never modify the file on disk')
end)

test('unix-style addon_path constructs forward-slash paths and round-trips', function()
  local sets = sample_sets()
  storage.save_shared(unix_path, 'TestChar', sets)

  local expected_path = 'data/TestChar/shared.json'
  assert(windower._fs[expected_path] ~= nil, 'file exists at exact unix-separator relative path')

  local expected_data_dir = '/addon/data'
  local expected_char_dir = '/addon/data/TestChar'
  assert_eq(expected_data_dir, windower._created_dirs[1], 'data dir (unix)')
  assert_eq(expected_char_dir, windower._created_dirs[2], 'char dir (unix)')
  for _, dir in ipairs(windower._created_dirs) do
    assert(not dir:find('\\', 1, true), 'no backslash in: ' .. dir)
  end

  local loaded = storage.load_shared(unix_path, 'TestChar')
  assert_deep_eq(sets, loaded, 'round-trips under unix-style addon_path')
end)

test('character names with spaces and mixed case pass through into the path verbatim', function()
  storage.save_shared(win_path, 'Mid Case Name', { [1] = { slots = {} } })

  local expected_path = [[data\Mid Case Name\shared.json]]
  assert(windower._fs[expected_path] ~= nil, 'file exists at the exact path with spaces/case preserved')

  local expected_char_dir = [[C:\Program Files (x86)\Windower4\addons\xivgamepad\data\Mid Case Name]]
  assert_eq(expected_char_dir, windower._created_dirs[2], 'char dir preserves spaces/case')
end)

test('string values with quotes, backslashes, newlines and tabs round-trip exactly', function()
  local sets = {
    [3] = {
      slots = {
        [5] = {
          type = 'ct', action = 1,
          alias = 'say "hi" \\ line\none\ttabbed',
          usable = true, overlays = {},
        },
      },
    },
  }
  storage.save_shared(win_path, 'TestChar', sets)
  local loaded = storage.load_shared(win_path, 'TestChar')
  assert_eq('say "hi" \\ line\none\ttabbed', loaded[3].slots[5].alias,
    'escaped string round-trips byte-for-byte')
  assert_deep_eq(sets, loaded, 'full structure round-trips with escaped strings')
end)

test('_decode: only canonical number strings become numeric keys', function()
  local decoded = storage._decode('{"1": "a", "16": "b", "007": "c", "1.0": "d", "1e2": "e"}')
  assert_eq('a', decoded[1], '"1" becomes numeric key 1')
  assert_eq('b', decoded[16], '"16" becomes numeric key 16')
  assert_eq('c', decoded['007'], '"007" stays a string key')
  assert_eq('d', decoded['1.0'], '"1.0" stays a string key')
  assert_eq('e', decoded['1e2'], '"1e2" stays a string key')
  assert_eq(nil, decoded[7], 'numeric 7 must not alias "007"')
  assert_eq(nil, decoded['1'], 'string "1" must not remain after numeric coercion')
end)

test('_decode rejects trailing garbage; load routes it to the corrupt path', function()
  assert_eq(false, (pcall(storage._decode, '{}garbage')), 'trailing garbage must raise')
  assert_eq(false, (pcall(storage._decode, '{"1": {"slots": {}}} {"2": {}}')),
    'second top-level value must raise')
  assert_eq(true, (pcall(storage._decode, '  {"1": true}  ')),
    'surrounding whitespace alone is fine')

  local path = [[data\TestChar\shared.json]]
  windower._fs[path] = '{"1": {"slots": {}}} trailing'
  local result = storage.load_shared(win_path, 'TestChar')
  assert_deep_eq({}, result, 'trailing garbage loads as empty table')
  assert(#log_calls > 0, 'log.error must be called for trailing garbage')
  assert_eq('{"1": {"slots": {}}} trailing', windower._fs[path], 'file left untouched')
end)

test('_decode rejects null inside arrays (would silently shift overlay order)', function()
  assert_eq(false, (pcall(storage._decode, '[1, null, 2]')), 'null array element must raise')

  local path = [[data\TestChar\job.json]]
  windower._fs[path] = '{"SCH": {"1": {"slots": {"1": {"type": "ma", "overlays": [null]}}}}}'
  local result = storage.load_job(win_path, 'TestChar')
  assert_deep_eq({}, result, 'null-in-overlays loads as empty table')
  assert(#log_calls > 0, 'log.error must be called for null array elements')
  assert_eq('{"SCH": {"1": {"slots": {"1": {"type": "ma", "overlays": [null]}}}}}',
    windower._fs[path], 'file left untouched')
end)

-- ----

io.write(string.format('test_storage: %d passed, %d failed\n', pass, fail))
if fail > 0 then
  error(fail .. ' test(s) failed in test_storage.lua')
end
