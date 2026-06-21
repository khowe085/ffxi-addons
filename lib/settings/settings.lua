-- Minimal JSON encoder/decoder for Lua 5.1

local json = {}

local function encode_val(v)
  local t = type(v)
  if t == 'nil' then
    return 'null'
  elseif t == 'boolean' then
    return v and 'true' or 'false'
  elseif t == 'number' then
    return tostring(v)
  elseif t == 'string' then
    return '"' .. v:gsub('\\', '\\\\'):gsub('"', '\\"'):gsub('\n', '\\n'):gsub('\r', '\\r'):gsub('\t', '\\t') .. '"'
  elseif t == 'table' then
    local n = 0
    local is_arr = true
    for k in pairs(v) do
      n = n + 1
      if type(k) ~= 'number' or k < 1 or math.floor(k) ~= k then
        is_arr = false
        break
      end
    end
    is_arr = is_arr and n > 0 and n == #v
    if is_arr then
      local parts = {}
      for i, val in ipairs(v) do
        parts[i] = encode_val(val)
      end
      return '[' .. table.concat(parts, ',') .. ']'
    else
      local parts = {}
      for k, val in pairs(v) do
        table.insert(parts, encode_val(tostring(k)) .. ':' .. encode_val(val))
      end
      return '{' .. table.concat(parts, ',') .. '}'
    end
  end
  error('cannot JSON-encode type: ' .. t)
end

function json.encode(v)
  return encode_val(v)
end

local function skip_ws(s, pos)
  return (s:match('^%s*()', pos))
end

local function decode_val(s, pos)
  pos = skip_ws(s, pos)
  local c = s:sub(pos, pos)

  if c == '"' then
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

  elseif c == '{' then
    local obj = {}
    pos = skip_ws(s, pos + 1)
    if s:sub(pos, pos) == '}' then return obj, pos + 1 end
    while true do
      local key
      key, pos = decode_val(s, pos)
      pos = skip_ws(s, pos)
      assert(s:sub(pos, pos) == ':', 'expected ":" at position ' .. pos)
      pos = skip_ws(s, pos + 1)
      local val
      val, pos = decode_val(s, pos)
      obj[key] = val
      pos = skip_ws(s, pos)
      local sep = s:sub(pos, pos)
      if sep == '}' then return obj, pos + 1 end
      assert(sep == ',', 'expected "," or "}" at position ' .. pos)
      pos = skip_ws(s, pos + 1)
    end

  elseif c == '[' then
    local arr = {}
    pos = skip_ws(s, pos + 1)
    if s:sub(pos, pos) == ']' then return arr, pos + 1 end
    while true do
      local val
      val, pos = decode_val(s, pos)
      table.insert(arr, val)
      pos = skip_ws(s, pos)
      local sep = s:sub(pos, pos)
      if sep == ']' then return arr, pos + 1 end
      assert(sep == ',', 'expected "," or "]" at position ' .. pos)
      pos = skip_ws(s, pos + 1)
    end

  elseif s:sub(pos, pos + 3) == 'true'  then return true,  pos + 4
  elseif s:sub(pos, pos + 4) == 'false' then return false, pos + 5
  elseif s:sub(pos, pos + 3) == 'null'  then return nil,   pos + 4

  else
    local num = s:match('^-?%d+%.?%d*[eE]?[+-]?%d*', pos)
    if num then return tonumber(num), pos + #num end
    error('unexpected character "' .. c .. '" at position ' .. pos)
  end
end

function json.decode(s)
  local val = (decode_val(s, 1))
  return val
end

-- Settings library

local M = {}

local _in_setup = false

-- Create dir and any missing parents using only windower.create_dir (no shell-out).
-- create_dir is not recursive, so walk the path and create each segment in turn.
local function ensure_dir(dir)
  if not (windower and windower.create_dir) then return end
  -- Preserve the full leading separator run so UNC roots (\\server\share) and
  -- POSIX absolute roots (/a/b) are not collapsed.
  local prefix = dir:match('^([/\\]+)') or ''
  local accum = prefix
  for segment in dir:gmatch('[^/\\]+') do
    if accum == '' or accum == prefix then
      accum = accum .. segment
    else
      accum = accum .. '/' .. segment
    end
    -- Skip a bare-root accumulator (e.g. just '/' or '\\') with no segment yet.
    if accum ~= prefix then
      windower.create_dir(accum)
    end
  end
end

-- IO provider — swapped out in tests via M._set_io_provider
local io_provider = {
  read_file = function(path)
    local f = io.open(path, 'r')
    if not f then return nil end
    local content = f:read('*all')
    f:close()
    return content
  end,
  write_file = function(path, content)
    local f = io.open(path, 'w')
    if not f then
      local dir = path:match('^(.*)[/\\][^/\\]+$')
      if dir then ensure_dir(dir) end
      f = assert(io.open(path, 'w'), 'cannot open for writing: ' .. path)
    end
    f:write(content)
    f:close()
  end,
}

local function deep_copy(t)
  if type(t) ~= 'table' then return t end
  local copy = {}
  for k, v in pairs(t) do
    copy[k] = deep_copy(v)
  end
  return copy
end

local function settings_path(addon_path)
  local char_name = windower.ffxi.get_player().name
  return addon_path .. 'data/' .. char_name .. '/settings.json'
end

function M.load(addon_path, defaults)
  assert(M.logged_in(), 'lib/settings: cannot load settings — no character is logged in')
  local path    = settings_path(addon_path)
  local content = io_provider.read_file(path)
  local result  = deep_copy(defaults)
  if content then
    local saved = json.decode(content)
    if type(saved) == 'table' then
      for k, v in pairs(saved) do
        result[k] = v
      end
    end
  end
  return result
end

function M.open_setup(live)
  _in_setup = true
  return deep_copy(live)
end

function M.stage_set(staged, key, value)
  staged[key] = value
end

function M.commit(staged, addon_path)
  assert(M.logged_in(), 'lib/settings: cannot commit settings — no character is logged in')
  local path    = settings_path(addon_path)
  local content = json.encode(staged)
  io_provider.write_file(path, content)
  _in_setup = false
  return deep_copy(staged)
end

function M.discard()
  _in_setup = false
end

function M.in_setup()
  return _in_setup
end

function M.logged_in()
  local player = windower.ffxi.get_player()
  return player ~= nil and player.name ~= nil and player.name ~= ''
end

-- For tests only: swap in an in-memory IO provider
function M._set_io_provider(provider)
  io_provider = provider
end

-- For tests only: the live IO provider, so the real default write_file can be
-- exercised directly without going through commit's per-character path.
function M._io_provider()
  return io_provider
end

return M
