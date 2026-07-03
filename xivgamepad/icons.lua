-- Item-icon adapter over the ported crossbar/icon_extractor (contract:
-- .planning/xivgamepad-contracts.md, "icons"). Extracted 32x32 BMPs are
-- cached at data/icons/items/{item_id}.bmp; any failure (missing DAT,
-- non-Windows env, unresolvable name) returns nil with one log.debug per
-- item per session, so callers can fall back to iconpack art. item_icon
-- never raises into a render path. All raw io stays inside
-- crossbar/icon_extractor -- the single reviewed exception to the no-io
-- rule; this module hands it an ABSOLUTE output path because raw io does
-- not resolve paths relative to the addon directory the way the Windower
-- files API does.

local files          = require('files')
local log            = require('log')
local res            = require('resources')
local icon_extractor = require('crossbar/icon_extractor')

local M = {}

local addon_path   = nil
local dirs_created = false
local extracted    = {}
local failed       = {}
local name_ids     = {}

-- Forward declarations
local absolute_path
local ensure_icon_dirs
local fail_once
local resolve_id
local sep_for
local strip_trailing_sep

-- Public functions

function M.close()
  icon_extractor.close()
end

function M.init(path)
  addon_path   = path
  dirs_created = false
  extracted    = {}
  failed       = {}
  name_ids     = {}
end

function M.item_icon(item)
  if not addon_path then return nil end
  local id = resolve_id(item)
  if not id then
    return fail_once(type(item) == 'string' and item:lower() or tostring(item), item)
  end
  if failed[id] then return nil end
  local rel = 'data/icons/items/' .. id .. '.bmp'
  if extracted[id] or files.exists(rel) then
    return rel
  end
  ensure_icon_dirs()
  local ok = pcall(icon_extractor.item_by_id, id, absolute_path(rel))
  if not ok then
    return fail_once(id, item)
  end
  extracted[id] = true
  return rel
end

-- Private functions

absolute_path = function(rel)
  local sep  = sep_for(addon_path)
  local base = strip_trailing_sep(addon_path)
  if sep ~= '/' then
    rel = rel:gsub('/', sep)
  end
  return base .. sep .. rel
end

-- create_dir takes absolute paths and is not recursive: create each level
-- beneath addon_path (which always exists), never walking above it.
ensure_icon_dirs = function()
  if dirs_created then return end
  dirs_created = true
  if not (windower and windower.create_dir) then return end
  local sep  = sep_for(addon_path)
  local base = strip_trailing_sep(addon_path)
  windower.create_dir(base .. sep .. 'data')
  windower.create_dir(base .. sep .. 'data' .. sep .. 'icons')
  windower.create_dir(base .. sep .. 'data' .. sep .. 'icons' .. sep .. 'items')
end

fail_once = function(key, item)
  if not failed[key] then
    failed[key] = true
    log.debug('item icon unavailable: %s', tostring(item))
  end
  return nil
end

-- Misses are memoized as false so a repeated bad name costs one table hit
-- instead of an O(n) res.items rescan (item_icon is on the render path).
resolve_id = function(item)
  if type(item) == 'number' then return item end
  if type(item) ~= 'string' then return nil end
  local wanted = item:lower()
  local memo = name_ids[wanted]
  if memo ~= nil then return memo or nil end
  for id, entry in pairs(res.items) do
    if entry.en and entry.en:lower() == wanted then
      name_ids[wanted] = id
      return id
    end
  end
  name_ids[wanted] = false
  return nil
end

sep_for = function(path)
  return path:find('\\', 1, true) and '\\' or '/'
end

strip_trailing_sep = function(path)
  return (path:gsub('[/\\]+$', ''))
end

return M
