-- Generated-resources adapter over the ported crossbar/ pipeline (contract:
-- .planning/xivgamepad-contracts.md, "Crossbar port amendments" / gamedata).
--
-- Generated files live at data/generated/crossbar_{spells,abilities}.lua and
-- are loaded via files.read + loadstring inside pcall, never require --
-- require would serve a stale cached module after a regeneration, and tests
-- must stay on the in-memory files mock. Freshness is the ported generator's
-- MD5 check against Windower's res sources, read via
-- files.new('../../res/*.lua') -- the documented read-only walk-up exception
-- (the never-walk-above-addon_path rule governs directory creation and
-- writes, not these reads). When regeneration itself fails (e.g. the res
-- sources are unreadable), the failure is logged once per session and empty
-- tables are served, so every query degrades to nil without raising.

local files = require('files')
local log = require('log')
local kebab_casify = require('crossbar/kebab_casify')
local resource_generator = require('crossbar/resource_generator')

local addon_path = nil
local ensured = false
local spells = {}
local abilities = {}
local icon_exists_cache = {}

local spells_relpath    = 'data/generated/crossbar_spells.lua'
local abilities_relpath = 'data/generated/crossbar_abilities.lua'
local iconpack          = 'default'

local M = {}

-- Forward declarations
local ensure_generated_dir
local icon_exists
local load_generated
local lookup
local sep_for
local source_table
local strip_leading_slash
local strip_trailing_sep

-- Public functions

function M.ability(name)
  return lookup(abilities, name)
end

function M.categories(res_key)
  local seen = {}
  local names = {}
  for _, entry in pairs(source_table(res_key)) do
    if type(entry) == 'table' and entry.res_key == res_key
        and entry.category ~= nil and not seen[entry.category] then
      seen[entry.category] = true
      table.insert(names, entry.category)
    end
  end
  table.sort(names)
  return names
end

function M.ensure_fresh()
  if ensured then return end
  ensured = true
  ensure_generated_dir()
  local ok, err = pcall(resource_generator.generate_outdated_resources)
  if not ok then
    log.error('resource generation failed: %s', tostring(err))
    spells, abilities = {}, {}
    return
  end
  spells = load_generated(spells_relpath)
  abilities = load_generated(abilities_relpath)
  if spells and abilities then return end
  -- Defense in depth: a generated file the outdated-pass considered current
  -- still failed to load; force a full regeneration before giving up.
  ok, err = pcall(resource_generator.generate_all_resources)
  if ok then
    spells = load_generated(spells_relpath)
    abilities = load_generated(abilities_relpath)
  end
  if not (spells and abilities) then
    log.error('generated resources unavailable%s',
      ok and '' or (': ' .. tostring(err)))
    spells = spells or {}
    abilities = abilities or {}
  end
end

function M.entry_for(binding)
  if type(binding) ~= 'table' then return nil end
  local btype = binding.type
  if btype == 'ma' then
    return M.spell(binding.action)
  elseif btype == 'ja' or btype == 'ws' or btype == 'pet' then
    return M.ability(binding.action)
  end
  return nil
end

function M.icon_for(binding)
  if type(binding) ~= 'table' then return nil end
  if type(binding.icon) == 'string' and binding.icon ~= '' then
    return strip_leading_slash(binding.icon)
  end
  local entry = M.entry_for(binding)
  if not entry then return nil end
  if type(entry.custom_icon) == 'string' then
    local custom_path = 'images/icons/iconpacks/' .. iconpack .. '/' .. entry.custom_icon
    if icon_exists(custom_path) then
      return custom_path
    end
  end
  if type(entry.default_icon) == 'string' then
    return strip_leading_slash(entry.default_icon)
  end
  return nil
end

function M.init(path)
  addon_path = path
  ensured = false
  spells = {}
  abilities = {}
  icon_exists_cache = {}
end

function M.list(res_key, category)
  local entries = {}
  if category ~= nil then
    for _, entry in pairs(source_table(res_key)) do
      if type(entry) == 'table' and entry.res_key == res_key
          and entry.category == category then
        table.insert(entries, entry)
      end
    end
  end
  table.sort(entries, function(a, b) return (a.en or '') < (b.en or '') end)
  return entries
end

function M.recast_key(binding)
  local entry = M.entry_for(binding)
  if not entry then return nil end
  return entry.recast_id or entry.id, entry.res_key
end

function M.spell(name)
  return lookup(spells, name)
end

-- Private functions

-- create_dir takes an absolute path and is not recursive: create data then
-- data/generated beneath addon_path (which always exists), separators matched
-- to addon_path, never walking above it.
ensure_generated_dir = function()
  if not (windower and windower.create_dir) then return end
  if not addon_path then return end
  local sep  = sep_for(addon_path)
  local base = strip_trailing_sep(addon_path)
  windower.create_dir(base .. sep .. 'data')
  windower.create_dir(base .. sep .. 'data' .. sep .. 'generated')
end

-- files.exists hits the real filesystem on every call in-game; icon lookups
-- run per HUD refresh, so both hits and misses are cached for the session.
icon_exists = function(path)
  local cached = icon_exists_cache[path]
  if cached ~= nil then return cached end
  local exists = not not files.exists(path)
  icon_exists_cache[path] = exists
  return exists
end

load_generated = function(relpath)
  local f = files.new(relpath)
  local content = f:read()
  if type(content) ~= 'string' then return nil end
  local ok, result = pcall(function() return loadstring(content)() end)
  if not ok or type(result) ~= 'table' then return nil end
  return result
end

-- Generated tables are keyed by kebab-cased display name; kebab_casify is
-- idempotent on already-kebab keys, so both forms look up correctly. The
-- md5 metadata entries are strings, never tables, so they can't leak out.
lookup = function(t, name)
  if type(name) ~= 'string' or name == '' then return nil end
  local entry = t[kebab_casify(name)]
  if type(entry) ~= 'table' then return nil end
  return entry
end

sep_for = function(path)
  return path:find('\\', 1, true) and '\\' or '/'
end

source_table = function(res_key)
  if res_key == 'spells' then
    return spells
  elseif res_key == 'job_abilities' or res_key == 'weapon_skills' then
    return abilities
  end
  return {}
end

strip_leading_slash = function(path)
  return (path:gsub('^[/\\]+', ''))
end

strip_trailing_sep = function(path)
  return (path:gsub('[/\\]+$', ''))
end

return M
