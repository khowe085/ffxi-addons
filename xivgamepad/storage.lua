-- Hotbar-content storage: shared.json and job.json, per character.
--
-- data/{CharacterName}/shared.json -> sets table (position 1..8 -> { slots = ... })
-- data/{CharacterName}/job.json    -> { [job_abbrev] = sets table }
--
-- Sparse containers (set positions 1..8, slot positions 1..16) are encoded as
-- JSON objects keyed by number strings, decoded back to numeric-keyed Lua
-- tables -- JSON arrays cannot represent holes. Dense arrays (overlays) are
-- encoded as JSON arrays.
--
-- Windower `files` API only -- no io.*, no os.execute/io.popen. Directory
-- creation mirrors the lib/settings contract: windower.create_dir, anchored
-- at the absolute addon_path, separators matched to addon_path, never
-- walking above addon_path.

local files = require('files')
local log   = require('log')

local M = {}

-- Forward declarations
local char_file_path
local decode_array
local decode_object
local decode_string
local decode_val
local encode_table
local encode_val
local ensure_char_dir
local is_dense_array
local load_file
local save_file
local sep_for
local strip_trailing_sep

-- Public functions

function M._decode(s)
  local val, pos = decode_val(s, 1)
  pos = (s:match('^%s*()', pos))
  if pos <= #s then
    error('unexpected trailing content at position ' .. pos)
  end
  return val
end

function M._encode(v)
  return encode_val(v)
end

function M.load_job(addon_path, char_name)
  return load_file(addon_path, char_name, 'job.json')
end

function M.load_shared(addon_path, char_name)
  return load_file(addon_path, char_name, 'shared.json')
end

function M.save_job(addon_path, char_name, jobs)
  save_file(addon_path, char_name, 'job.json', jobs)
end

function M.save_shared(addon_path, char_name, sets)
  save_file(addon_path, char_name, 'shared.json', sets)
end

-- Private functions

-- Relative to the addon directory: the Windower files library prefixes
-- windower.addon_path onto the stored path in every operation, so an
-- absolute path here would double-prefix and break all file I/O. Only
-- windower.create_dir (ensure_char_dir) takes absolute paths.
char_file_path = function(addon_path, char_name, filename)
  local sep = sep_for(addon_path)
  return 'data' .. sep .. char_name .. sep .. filename
end

decode_array = function(s, pos)
  local arr = {}
  pos = (s:match('^%s*()', pos + 1))
  if s:sub(pos, pos) == ']' then return arr, pos + 1 end
  while true do
    local val
    val, pos = decode_val(s, pos)
    -- Lua 5.1 table.insert(arr, nil) silently no-ops, which would shift
    -- every later element (reordering overlays). Treat null as corrupt.
    if val == nil then
      error('null is not supported inside JSON arrays (position ' .. pos .. ')')
    end
    table.insert(arr, val)
    pos = (s:match('^%s*()', pos))
    local sep = s:sub(pos, pos)
    if sep == ']' then return arr, pos + 1 end
    assert(sep == ',', 'expected "," or "]" at position ' .. pos)
    pos = (s:match('^%s*()', pos + 1))
  end
end

decode_object = function(s, pos)
  local obj = {}
  pos = (s:match('^%s*()', pos + 1))
  if s:sub(pos, pos) == '}' then return obj, pos + 1 end
  while true do
    local key
    key, pos = decode_val(s, pos)
    pos = (s:match('^%s*()', pos))
    assert(s:sub(pos, pos) == ':', 'expected ":" at position ' .. pos)
    pos = (s:match('^%s*()', pos + 1))
    local val
    val, pos = decode_val(s, pos)
    -- Number-string keys decode back to numeric keys so sparse position/slot
    -- containers ("1".."16") round trip to numeric-keyed Lua tables.
    local numeric_key = tonumber(key)
    if numeric_key and tostring(numeric_key) == key then
      obj[numeric_key] = val
    else
      obj[key] = val
    end
    pos = (s:match('^%s*()', pos))
    local sep = s:sub(pos, pos)
    if sep == '}' then return obj, pos + 1 end
    assert(sep == ',', 'expected "," or "}" at position ' .. pos)
    pos = (s:match('^%s*()', pos + 1))
  end
end

decode_string = function(s, pos)
  local chunks = {}
  pos = pos + 1
  while true do
    local plain, delim = s:match('^([^"\\]*)(["\\])', pos)
    if not plain then error('unterminated JSON string near position ' .. pos) end
    if plain ~= '' then table.insert(chunks, plain) end
    pos = pos + #plain
    if delim == '"' then
      pos = pos + 1
      break
    end
    local esc = s:sub(pos + 1, pos + 1)
    local map = { n = '\n', r = '\r', t = '\t', ['"'] = '"', ['\\'] = '\\', ['/'] = '/' }
    table.insert(chunks, map[esc] or esc)
    pos = pos + 2
  end
  return table.concat(chunks), pos
end

decode_val = function(s, pos)
  pos = (s:match('^%s*()', pos))
  local c = s:sub(pos, pos)

  if c == '"' then
    return decode_string(s, pos)
  elseif c == '{' then
    return decode_object(s, pos)
  elseif c == '[' then
    return decode_array(s, pos)
  elseif s:sub(pos, pos + 3) == 'true' then
    return true, pos + 4
  elseif s:sub(pos, pos + 4) == 'false' then
    return false, pos + 5
  elseif s:sub(pos, pos + 3) == 'null' then
    return nil, pos + 4
  else
    local num = s:match('^-?%d+%.?%d*[eE]?[+-]?%d*', pos)
    if num and num ~= '' and num ~= '-' then return tonumber(num), pos + #num end
    error('unexpected character "' .. c .. '" at position ' .. pos)
  end
end

-- A table is encoded as a JSON array only when every key is a positive
-- integer forming a contiguous 1..n run with no holes; anything else
-- (including our intentionally sparse position/slot containers) becomes a
-- JSON object keyed by stringified keys, so numeric-with-holes tables round
-- trip through decode_object's numeric-key coercion.
encode_table = function(t, indent)
  indent = indent or ''
  local next_indent = indent .. '  '
  local dense, n = is_dense_array(t)
  if dense then
    local parts = {}
    for i = 1, n do
      parts[i] = next_indent .. encode_val(t[i], next_indent)
    end
    return '[\n' .. table.concat(parts, ',\n') .. '\n' .. indent .. ']'
  end

  local keys = {}
  for k in pairs(t) do table.insert(keys, k) end
  if #keys == 0 then return '{}' end
  table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)

  local parts = {}
  for i, k in ipairs(keys) do
    parts[i] = next_indent .. encode_val(tostring(k)) .. ': '
      .. encode_val(t[k], next_indent)
  end
  return '{\n' .. table.concat(parts, ',\n') .. '\n' .. indent .. '}'
end

encode_val = function(v, indent)
  local t = type(v)
  if t == 'nil' then
    return 'null'
  elseif t == 'boolean' then
    return v and 'true' or 'false'
  elseif t == 'number' then
    return tostring(v)
  elseif t == 'string' then
    return '"' .. v:gsub('\\', '\\\\'):gsub('"', '\\"'):gsub('\n', '\\n')
      :gsub('\r', '\\r'):gsub('\t', '\\t') .. '"'
  elseif t == 'table' then
    return encode_table(v, indent)
  end
  error('cannot JSON-encode type: ' .. t)
end

-- Never walks above addon_path: only ever creates addon_path/data and
-- addon_path/data/<char>, both anchored at the given absolute addon_path.
ensure_char_dir = function(addon_path, char_name)
  if not (windower and windower.create_dir) then return end
  local sep  = sep_for(addon_path)
  local base = strip_trailing_sep(addon_path)
  windower.create_dir(base .. sep .. 'data')
  windower.create_dir(base .. sep .. 'data' .. sep .. char_name)
end

is_dense_array = function(t)
  local n = 0
  for k in pairs(t) do
    n = n + 1
    if type(k) ~= 'number' or k < 1 or math.floor(k) ~= k then
      return false
    end
  end
  if n == 0 then return false end
  for i = 1, n do
    if t[i] == nil then return false end
  end
  return true, n
end

load_file = function(addon_path, char_name, filename)
  local path = char_file_path(addon_path, char_name, filename)
  local f = files.new(path)
  if not f:exists() then return {} end
  local content = f:read()
  if not content then return {} end
  local ok, decoded = pcall(M._decode, content)
  if not ok or type(decoded) ~= 'table' then
    log.error('xivgamepad: failed to parse %s: %s', path, tostring(decoded))
    return {}
  end
  return decoded
end

save_file = function(addon_path, char_name, filename, data)
  ensure_char_dir(addon_path, char_name)
  local path = char_file_path(addon_path, char_name, filename)
  local f = files.new(path)
  f:write(M._encode(data))
end

sep_for = function(addon_path)
  return addon_path:find('\\', 1, true) and '\\' or '/'
end

strip_trailing_sep = function(addon_path)
  return (addon_path:gsub('[/\\]+$', ''))
end

return M
