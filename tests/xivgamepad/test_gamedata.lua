-- Tests for xivgamepad/gamedata.lua and the ported crossbar/ generated-
-- resources pipeline: directory creation, generation into the in-memory fs,
-- loadstring round-trip, MD5 freshness (skip / regenerate per source),
-- lookup queries, icon resolution precedence with existence caching,
-- recast keys, category enumeration and graceful degradation.
--
-- The log stub is preloaded via package.loaded before requiring the module
-- under test (contracts doc: tests own this stub, never the shared mock).

local log_stub = { _errors = {}, _infos = {}, _debugs = {} }
local function recorder(list)
  return function(fmt, ...)
    local ok, msg = pcall(string.format, tostring(fmt), ...)
    table.insert(list, ok and msg or tostring(fmt))
  end
end
log_stub.error = recorder(log_stub._errors)
log_stub.info  = recorder(log_stub._infos)
log_stub.debug = recorder(log_stub._debugs)
package.loaded['log'] = log_stub

-- Require fresh instances in case an earlier manifest file cached any of them.
package.loaded['gamedata'] = nil
package.loaded['crossbar/resource_generator'] = nil
package.loaded['crossbar/kebab_casify'] = nil
package.loaded['crossbar/ordered_pairs'] = nil
package.loaded['crossbar/md5'] = nil

-- Augment shared res fixtures by mutation (never edit the mock). Earlier
-- manifest files add res entries without the optional fields the generator
-- dereferences (test_binder's spells have no element and reference skills
-- absent from res.skills; its 'Sic' ability has no element/tp_cost), so
-- before anything generates: add this file's own fixtures, then defensively
-- fill missing fields on EVERY entry -- additively, never overwriting.
res.job_abilities[150] = { id = 150, en = 'Assault', type = 'PetCommand', prefix = '/pet', recast_id = 150, tp_cost = 0, element = 15 }
res.spells[503] = { id = 503, en = 'Test Verse', type = 'BardSong', skill = 40, prefix = '/song', mp_cost = 0, recast_id = 9001, element = 15 }

local function fill_missing(entry, field, value)
  if entry[field] == nil then entry[field] = value end
end

for id, spell in pairs(res.spells) do
  fill_missing(spell, 'type', 'WhiteMagic')
  fill_missing(spell, 'skill', 33)
  fill_missing(spell, 'recast_id', id)
  fill_missing(spell, 'mp_cost', 0)
  fill_missing(spell, 'element', 15)
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
  if res.elements[ability.element] == nil then
    res.elements[ability.element] = { id = ability.element, en = 'None' }
  end
end

for _, ws in pairs(res.weapon_skills) do
  if ws.skill ~= nil then
    fill_missing(ws, 'element', 15)
    if res.skills[ws.skill] == nil then
      res.skills[ws.skill] = { id = ws.skill, en = 'Skill ' .. ws.skill }
    end
    if res.elements[ws.element] == nil then
      res.elements[ws.element] = { id = ws.element, en = 'None' }
    end
  end
end

local gamedata = require('gamedata')
local md5 = require('crossbar/md5')

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

local function assert_contains(list, value, msg)
  for _, v in ipairs(list) do
    if v == value then return end
  end
  error((msg or 'list is missing value') .. ': ' .. tostring(value), 2)
end

local function assert_sorted(list, msg)
  for i = 2, #list do
    if not (list[i - 1] < list[i]) then
      error(string.format('%s: %s !< %s at index %d',
        msg or 'list not strictly sorted', tostring(list[i - 1]), tostring(list[i]), i), 2)
    end
  end
end

local win_path  = 'C:\\Program Files (x86)\\Windower4\\addons\\xivgamepad\\'
local unix_path = '/home/user/Windower4/addons/xivgamepad/'

local spells_relpath    = 'data/generated/crossbar_spells.lua'
local abilities_relpath = 'data/generated/crossbar_abilities.lua'

local spells_src_v1    = '-- fixture: res/spells.lua v1\nreturn {}\n'
local spells_src_v2    = '-- fixture: res/spells.lua v2 (changed)\nreturn {}\n'
local abilities_src_v1 = '-- fixture: res/job_abilities.lua v1\nreturn {}\n'
local abilities_src_v2 = '-- fixture: res/job_abilities.lua v2 (changed)\nreturn {}\n'
local ws_src_v1        = '-- fixture: res/weapon_skills.lua v1\nreturn {}\n'
local ws_src_v2        = '-- fixture: res/weapon_skills.lua v2 (changed)\nreturn {}\n'

-- The MD5 freshness reads walk up to Windower's res sources; seed the exact
-- relative keys production code constructs.
local function seed_res_sources(spells_src, abilities_src, ws_src)
  windower._fs['../../res/spells.lua']        = spells_src or spells_src_v1
  windower._fs['../../res/job_abilities.lua'] = abilities_src or abilities_src_v1
  windower._fs['../../res/weapon_skills.lua'] = ws_src or ws_src_v1
end

local function fresh_session(path)
  windower._reset()
  seed_res_sources()
  gamedata.init(path or win_path)
end

local function generated_session(path)
  fresh_session(path)
  gamedata.ensure_fresh()
end

-- Counts generator writes by relative path while fn runs; always restores the
-- mock's module-level files.write, even when fn throws.
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

-- ---- pipeline: generation, freshness, degradation

test('md5 port produces RFC 1321 reference digests in this harness', function()
  assert_eq('d41d8cd98f00b204e9800998ecf8427e', md5.sumhexa(''), 'empty string vector')
  assert_eq('900150983cd24fb0d6963f7d28e17f72', md5.sumhexa('abc'), 'abc vector')
end)

test('first ensure_fresh creates data/generated and writes both generated files', function()
  fresh_session()
  gamedata.ensure_fresh()
  local spells_content = windower._fs[spells_relpath]
  local abilities_content = windower._fs[abilities_relpath]
  assert_eq('string', type(spells_content), 'spells file written at exact relative path')
  assert_eq('string', type(abilities_content), 'abilities file written at exact relative path')
  assert(spells_content:find('Automatically generated', 1, true), 'spells file carries generator banner')
  assert(abilities_content:find('Automatically generated', 1, true), 'abilities file carries generator banner')
  local expected_data = 'C:\\Program Files (x86)\\Windower4\\addons\\xivgamepad\\data'
  assert_contains(windower._created_dirs, expected_data, 'created data dir (absolute, backslash)')
  assert_contains(windower._created_dirs, expected_data .. '\\generated', 'created generated dir (absolute, backslash)')
end)

test('create_dir separators match a unix-style addon_path', function()
  fresh_session(unix_path)
  gamedata.ensure_fresh()
  assert_contains(windower._created_dirs, '/home/user/Windower4/addons/xivgamepad/data')
  assert_contains(windower._created_dirs, '/home/user/Windower4/addons/xivgamepad/data/generated')
end)

test('generated content round-trips through loadstring and embeds source MD5s', function()
  generated_session()
  local spells_table = assert(loadstring(windower._fs[spells_relpath]))()
  assert_eq('table', type(spells_table), 'spells chunk returns a table')
  assert_eq(md5.sumhexa(spells_src_v1), spells_table['spells.lua.md5'], 'spells source hash embedded')
  assert_eq('Cure', spells_table['cure'].en, 'spell entry present under kebab key')
  local abilities_table = assert(loadstring(windower._fs[abilities_relpath]))()
  assert_eq(md5.sumhexa(abilities_src_v1), abilities_table['job_abilities.lua.md5'], 'abilities source hash embedded')
  assert_eq(md5.sumhexa(ws_src_v1), abilities_table['weapon_skills.lua.md5'], 'weapon skills source hash embedded')
  assert_eq('Berserk', abilities_table['berserk'].en, 'ability entry present under kebab key')
end)

test('ensure_fresh is idempotent within a session', function()
  generated_session()
  local counts = with_write_counts(function()
    gamedata.ensure_fresh()
    gamedata.ensure_fresh()
  end)
  assert_eq(nil, next(counts), 'no writes on repeat calls')
end)

test('new session with unchanged res sources skips regeneration', function()
  generated_session()
  gamedata.init(win_path)
  local counts = with_write_counts(function()
    gamedata.ensure_fresh()
  end)
  assert_eq(nil, counts[spells_relpath], 'spells file not rewritten')
  assert_eq(nil, counts[abilities_relpath], 'abilities file not rewritten')
  assert_eq(1, gamedata.spell('Cure').id, 'queries served from the existing files')
end)

test('changed spells source regenerates only the spells file', function()
  generated_session()
  windower._fs['../../res/spells.lua'] = spells_src_v2
  gamedata.init(win_path)
  local counts = with_write_counts(function()
    gamedata.ensure_fresh()
  end)
  assert_eq(1, counts[spells_relpath], 'spells file rewritten once')
  assert_eq(nil, counts[abilities_relpath], 'abilities file untouched')
  assert(windower._fs[spells_relpath]:find(md5.sumhexa(spells_src_v2), 1, true),
    'new spells source hash embedded')
end)

test('changed job_abilities source regenerates only the abilities file', function()
  generated_session()
  windower._fs['../../res/job_abilities.lua'] = abilities_src_v2
  gamedata.init(win_path)
  local counts = with_write_counts(function()
    gamedata.ensure_fresh()
  end)
  assert_eq(1, counts[abilities_relpath], 'abilities file rewritten once')
  assert_eq(nil, counts[spells_relpath], 'spells file untouched')
  assert(windower._fs[abilities_relpath]:find(md5.sumhexa(abilities_src_v2), 1, true),
    'new abilities source hash embedded')
end)

test('changed weapon_skills source regenerates the abilities file', function()
  generated_session()
  windower._fs['../../res/weapon_skills.lua'] = ws_src_v2
  gamedata.init(win_path)
  local counts = with_write_counts(function()
    gamedata.ensure_fresh()
  end)
  assert_eq(1, counts[abilities_relpath], 'abilities file rewritten once')
  assert_eq(nil, counts[spells_relpath], 'spells file untouched')
end)

test('corrupt generated spells file is regenerated', function()
  generated_session()
  windower._fs[spells_relpath] = 'this is not lua {{{'
  gamedata.init(win_path)
  gamedata.ensure_fresh()
  assert_eq(1, gamedata.spell('Cure').id, 'spell served after regeneration')
  assert_eq('table', type(loadstring(windower._fs[spells_relpath])()), 'file valid again')
end)

test('generated file that is valid lua but not a table is regenerated', function()
  generated_session()
  windower._fs[abilities_relpath] = 'return 42\n'
  gamedata.init(win_path)
  gamedata.ensure_fresh()
  assert_eq('Berserk', gamedata.ability('Berserk').en, 'ability served after regeneration')
end)

test('missing res sources degrade gracefully: one error, nil queries, no raise', function()
  windower._reset()
  gamedata.init(win_path)
  local errors_before = #log_stub._errors
  gamedata.ensure_fresh()
  assert_eq(errors_before + 1, #log_stub._errors, 'exactly one error logged')
  assert_eq(nil, gamedata.spell('Cure'), 'spell query returns nil')
  assert_eq(nil, gamedata.ability('Berserk'), 'ability query returns nil')
  assert_eq(nil, gamedata.entry_for({ type = 'ma', action = 'Cure' }), 'entry_for returns nil')
  assert_eq(nil, gamedata.icon_for({ type = 'ma', action = 'Cure' }), 'icon_for returns nil')
  assert_eq(nil, gamedata.recast_key({ type = 'ma', action = 'Cure' }), 'recast_key returns nil')
  assert_eq(0, #gamedata.categories('spells'), 'categories empty')
  gamedata.ensure_fresh()
  assert_eq(errors_before + 1, #log_stub._errors, 'no repeat error within the session')
end)

test('a later session recovers once res sources are present', function()
  windower._reset()
  gamedata.init(win_path)
  gamedata.ensure_fresh()
  assert_eq(nil, gamedata.spell('Cure'), 'degraded session serves nil')
  seed_res_sources()
  gamedata.init(win_path)
  gamedata.ensure_fresh()
  assert_eq(1, gamedata.spell('Cure').id, 'fresh session regenerates and serves')
end)

-- ---- lookups

test('spell lookup returns the full generated entry', function()
  generated_session()
  local cure = gamedata.spell('Cure')
  assert_eq('table', type(cure), 'entry found')
  assert_eq(1, cure.id, 'id')
  assert_eq('Cure', cure.en, 'en')
  assert_eq('spells', cure.res_key, 'res_key')
  assert_eq('ma', cure.type, 'type')
  assert_eq(1, cure.recast_id, 'recast_id')
  assert_eq('white magic', cure.category, 'category')
  assert_eq('Light', cure.element, 'element')
  assert_eq('Healing Magic', cure.skill, 'skill')
  assert_eq(8, cure.mp_cost, 'mp_cost')
  assert_eq(0, cure.tp_cost, 'tp_cost')
  assert_eq('/images/icons/spells/00001.png', cure.default_icon, 'default_icon')
  assert_eq('white-magic/cure.png', cure.custom_icon, 'custom_icon')
end)

test('spell lookup kebab-cases punctuated names and accepts kebab keys', function()
  generated_session()
  assert_eq(338, gamedata.spell('Utsusemi: Ichi').id, 'display name')
  assert_eq(338, gamedata.spell('utsusemi-ichi').id, 'kebab key')
end)

test('unknown or invalid lookup names return nil', function()
  generated_session()
  assert_eq(nil, gamedata.spell('Nonexistent Spell'), 'unknown spell')
  assert_eq(nil, gamedata.spell(nil), 'nil name')
  assert_eq(nil, gamedata.spell(''), 'empty name')
  assert_eq(nil, gamedata.ability('Nonexistent Ability'), 'unknown ability')
  assert_eq(nil, gamedata.ability('job_abilities.lua.md5'), 'md5 metadata never leaks')
end)

test('ability lookup covers ja, pet and ws entries', function()
  generated_session()
  local berserk = gamedata.ability('Berserk')
  assert_eq('job_abilities', berserk.res_key, 'ja res_key')
  assert_eq('ja', berserk.type, 'ja type')
  assert_eq('abilities', berserk.category, 'ja category')
  local assault = gamedata.ability('Assault')
  assert_eq('pet', assault.type, 'pet type')
  assert_eq('pet-commands', assault.category, 'pet category')
  local fast_blade = gamedata.ability('Fast Blade')
  assert_eq('weapon_skills', fast_blade.res_key, 'ws res_key')
  assert_eq('ws', fast_blade.type, 'ws type')
  assert_eq('sword', fast_blade.category, 'ws category')
  assert_eq(1000, fast_blade.tp_cost, 'ws tp_cost')
end)

test('entry_for routes by binding type', function()
  generated_session()
  assert_eq(144, gamedata.entry_for({ type = 'ma', action = 'Fire' }).id, 'ma -> spells')
  assert_eq(5, gamedata.entry_for({ type = 'ja', action = 'Provoke' }).id, 'ja -> abilities')
  assert_eq(32, gamedata.entry_for({ type = 'ws', action = 'Fast Blade' }).id, 'ws -> abilities')
  assert_eq(150, gamedata.entry_for({ type = 'pet', action = 'Assault' }).id, 'pet -> abilities')
  assert_eq(nil, gamedata.entry_for({ type = 'item', action = 'Hi-Potion' }), 'other types -> nil')
  assert_eq(nil, gamedata.entry_for({ type = 'ma' }), 'missing action -> nil')
  assert_eq(nil, gamedata.entry_for(nil), 'nil binding -> nil')
end)

-- ---- icon resolution

test('icon_for prefers binding.icon and strips any leading slash', function()
  generated_session()
  assert_eq('images/mine.png',
    gamedata.icon_for({ type = 'ma', action = 'Cure', icon = '/images/mine.png' }),
    'leading slash stripped')
  assert_eq('images/mine.png',
    gamedata.icon_for({ type = 'ma', action = 'Cure', icon = 'images/mine.png' }),
    'clean path passes through')
end)

test('icon_for uses the iconpack custom icon when the file exists', function()
  generated_session()
  windower._fs['images/icons/iconpacks/default/white-magic/cure.png'] = 'png-bytes'
  assert_eq('images/icons/iconpacks/default/white-magic/cure.png',
    gamedata.icon_for({ type = 'ma', action = 'Cure' }))
end)

test('icon_for caches custom-icon existence for the session', function()
  generated_session()
  windower._fs['images/icons/iconpacks/default/white-magic/cure.png'] = 'png-bytes'
  local binding = { type = 'ma', action = 'Cure' }
  assert_eq('images/icons/iconpacks/default/white-magic/cure.png', gamedata.icon_for(binding), 'hit cached')
  windower._fs['images/icons/iconpacks/default/white-magic/cure.png'] = nil
  assert_eq('images/icons/iconpacks/default/white-magic/cure.png', gamedata.icon_for(binding),
    'positive result served from cache after file removal')
  local fire = { type = 'ma', action = 'Fire' }
  assert_eq('images/icons/spells/00144.png', gamedata.icon_for(fire), 'miss cached')
  windower._fs['images/icons/iconpacks/default/black-magic/fire.png'] = 'png-bytes'
  assert_eq('images/icons/spells/00144.png', gamedata.icon_for(fire),
    'negative result served from cache after file appears')
  gamedata.init(win_path)
  gamedata.ensure_fresh()
  assert_eq('images/icons/iconpacks/default/black-magic/fire.png', gamedata.icon_for(fire),
    'new session re-checks existence')
end)

test('icon_for serves generator default icons with the slash stripped', function()
  generated_session()
  assert_eq('images/icons/spells/00144.png',
    gamedata.icon_for({ type = 'ma', action = 'Fire' }), 'spell default')
  assert_eq('images/icons/abilities/00001.png',
    gamedata.icon_for({ type = 'ja', action = 'Berserk' }), 'ability default')
  assert_eq('images/icons/weapons/sword.png',
    gamedata.icon_for({ type = 'ws', action = 'Fast Blade' }), 'weapon skill default')
end)

test('icon_for returns nil for unresolvable bindings', function()
  generated_session()
  assert_eq(nil, gamedata.icon_for({ type = 'ct', action = 'foo' }), 'type without entries')
  assert_eq(nil, gamedata.icon_for({ type = 'ma', action = 'Unknown Spell' }), 'unknown entry')
  assert_eq(nil, gamedata.icon_for(nil), 'nil binding')
end)

-- ---- recast keys, categories, lists

test('recast_key returns recast id (or id fallback) plus res_key', function()
  generated_session()
  local id, res_key = gamedata.recast_key({ type = 'ma', action = 'Cure' })
  assert_eq(1, id, 'spell recast id')
  assert_eq('spells', res_key, 'spell res_key')
  id, res_key = gamedata.recast_key({ type = 'ma', action = 'Test Verse' })
  assert_eq(9001, id, 'recast_id preferred over id')
  id, res_key = gamedata.recast_key({ type = 'ja', action = 'Provoke' })
  assert_eq(5, id, 'ability recast id')
  assert_eq('job_abilities', res_key, 'ability res_key')
  id, res_key = gamedata.recast_key({ type = 'ws', action = 'Fast Blade' })
  assert_eq(32, id, 'weapon skills fall back to id')
  assert_eq('weapon_skills', res_key, 'ws res_key')
  assert_eq(nil, gamedata.recast_key({ type = 'ma', action = 'Unknown Spell' }), 'unknown -> nil')
end)

test('categories are distinct, sorted and scoped to the res_key', function()
  generated_session()
  local spell_cats = gamedata.categories('spells')
  assert_sorted(spell_cats, 'spell categories sorted')
  assert_contains(spell_cats, 'white magic')
  assert_contains(spell_cats, 'black magic')
  assert_contains(spell_cats, 'ninjutsu')
  assert_contains(spell_cats, 'songs')
  local ja_cats = gamedata.categories('job_abilities')
  assert_sorted(ja_cats, 'ability categories sorted')
  assert_contains(ja_cats, 'abilities')
  assert_contains(ja_cats, 'pet-commands')
  for _, cat in ipairs(ja_cats) do
    assert(cat ~= 'sword', 'ws categories never bleed into job_abilities')
  end
  local ws_cats = gamedata.categories('weapon_skills')
  assert_contains(ws_cats, 'sword')
  assert_eq(0, #gamedata.categories('bogus_res_key'), 'unknown res_key -> empty')
end)

test('list returns matching entries sorted by display name', function()
  generated_session()
  local swords = gamedata.list('weapon_skills', 'sword')
  assert(#swords >= 2, 'both fixture weapon skills listed')
  local names = {}
  for _, entry in ipairs(swords) do
    assert_eq('weapon_skills', entry.res_key, 'res_key scoped')
    assert_eq('sword', entry.category, 'category scoped')
    table.insert(names, entry.en)
  end
  assert_sorted(names, 'weapon skills sorted by en')
  assert_contains(names, 'Fast Blade')
  assert_contains(names, 'Red Lotus Blade')
  local blacks = gamedata.list('spells', 'black magic')
  local black_names = {}
  for _, entry in ipairs(blacks) do
    assert_eq('black magic', entry.category, 'category scoped')
    table.insert(black_names, entry.en)
  end
  assert_sorted(black_names, 'spells sorted by en')
  assert_contains(black_names, 'Fire')
  assert_eq(0, #gamedata.list('spells', 'no such category'), 'unknown category -> empty')
  assert_eq(0, #gamedata.list('spells', nil), 'nil category -> empty')
end)

-- ----

-- Clear this file's module instances and stubs so later manifest files
-- (test_integration loads the real modules) start clean.
package.loaded['log'] = nil
package.loaded['gamedata'] = nil
package.loaded['crossbar/resource_generator'] = nil
package.loaded['crossbar/kebab_casify'] = nil
package.loaded['crossbar/ordered_pairs'] = nil
package.loaded['crossbar/md5'] = nil
windower._reset()

io.write(string.format('test_gamedata: %d passed, %d failed\n', pass, fail))
if fail > 0 then
  error(fail .. ' test(s) failed in test_gamedata.lua')
end
