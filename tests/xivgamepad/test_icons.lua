-- Icon extraction: the ported crossbar/icon_extractor and the icons adapter.
--
-- The extractor binary-reads FFXI ROM DATs through raw io (the reviewed
-- carve-out), so this file preloads windower._make_fake_io over a
-- synthetic-DAT fs map BEFORE requiring the module, per the mock's usage
-- comment, and restores the real io at file end.
--
-- Synthetic DAT design: an item record is 0xC00 bytes; the extractor seeks
-- to (id - (min + offset)) * 0xC00 + 0x2BD and reads 0x800 bytes -- a
-- 0x400-byte color palette (256 entries x 4 BGRA bytes) followed by 0x400
-- palette-index bytes (32x32 pixels). Every stored byte is bit-rotated:
-- stored s decodes to rot3(s) = (s % 0x20) * 8 + floor(s / 0x20), and the
-- palette's alpha channel is additionally doubled and clamped to 255. The
-- fixture specifies DECODED values and stores inv_rot3 of them, so the
-- expected BMP bytes are computed independently of the code under test.

windower._reset()

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

local function assert_bytes(expected, actual, what)
  if expected == actual then return end
  assert(actual, what .. ': actual is nil')
  local n = math.min(#expected, #actual)
  for i = 1, n do
    if expected:byte(i) ~= actual:byte(i) then
      error(string.format('%s: byte %d differs (expected %d, got %d)',
        what, i, expected:byte(i), actual:byte(i)), 2)
    end
  end
  error(string.format('%s: length differs (expected %d, got %d)',
    what, #expected, #actual), 2)
end

local floor = math.floor
local char  = string.char
local rep   = string.rep

-- ---- synthetic DAT fixture ----

local function rot3(s) return (s % 0x20) * 0x8 + floor(s / 0x20) end
local function inv_rot3(v) return (v % 0x8) * 0x20 + floor(v / 0x8) end

-- palette_entries: { { index, b, g, r, a } } with DECODED channel values;
-- the resulting BMP alpha is min(2 * a, 255). pixels: pixel position (1..1024)
-- -> palette entry index.
local function make_icon_bytes(palette_entries, pixels)
  local bytes = {}
  for i = 1, 0x800 do bytes[i] = 0 end
  for _, e in ipairs(palette_entries) do
    local base = e.index * 4
    bytes[base + 1] = inv_rot3(e.b)
    bytes[base + 2] = inv_rot3(e.g)
    bytes[base + 3] = inv_rot3(e.r)
    bytes[base + 4] = inv_rot3(e.a)
  end
  for pos, entry_index in pairs(pixels) do
    bytes[0x400 + pos] = inv_rot3(entry_index)
  end
  local out = {}
  for i = 1, 0x800 do out[i] = char(bytes[i]) end
  return table.concat(out)
end

-- Two ranges of the extractor's item dat map, exercised by one id each.
local general_range = { min = 0x0001, offset = -1, dat = '118/106' } -- General Items
local usable_range  = { min = 0x1000, offset = 0,  dat = '118/107' } -- Usable Items

local function record_offset(id, range)
  return (id - (range.min + range.offset)) * 0xC00 + 0x2BD
end

local function make_dat(id, range, icon_bytes)
  return rep('\0', record_offset(id, range)) .. icon_bytes
end

-- Hi-Potion (4116, usable range): pixel 1 = entry 5 (alpha 0x80 doubles past
-- 255 and clamps), pixel 2 = entry 9 (alpha 0x20 doubles to 0x40).
local icon_4116 = make_icon_bytes(
  { { index = 5, b = 0x10, g = 0x20, r = 0x30, a = 0x80 },
    { index = 9, b = 0x08, g = 0x88, r = 0xC8, a = 0x20 } },
  { [1] = 5, [2] = 9 })
local body_4116 = char(0x10, 0x20, 0x30, 0xFF)
  .. char(0x08, 0x88, 0xC8, 0x40)
  .. rep('\0', 0x1000 - 8)

-- id 2 (general range, offset -1): pixel 1 = entry 3, a distinct color so a
-- wrong dat-map/seek cannot produce this output.
local icon_2 = make_icon_bytes(
  { { index = 3, b = 0x40, g = 0x50, r = 0x60, a = 0x80 } },
  { [1] = 3 })
local body_2 = char(0x40, 0x50, 0x60, 0xFF) .. rep('\0', 0x1000 - 4)

-- open_dat builds: game_path .. '/ROM/' .. dat_path .. '.DAT'
local dat_106_path = windower.ffxi_path .. '/ROM/' .. general_range.dat .. '.DAT'
local dat_107_path = windower.ffxi_path .. '/ROM/' .. usable_range.dat .. '.DAT'

local fake_fs = {
  [dat_106_path] = make_dat(2, general_range, icon_2),
  [dat_107_path] = make_dat(4116, usable_range, icon_4116),
}

-- ---- expected BMP header (mirrors the source's 122-byte builder) ----

local function le32(n)
  return char(n % 256, floor(n / 256) % 256, floor(n / 65536) % 256, floor(n / 16777216) % 256)
end

local function ru32(s, pos)
  local b1, b2, b3, b4 = s:byte(pos, pos + 3)
  return ((b4 * 256 + b3) * 256 + b2) * 256 + b1
end

local function ru16(s, pos)
  local b1, b2 = s:byte(pos, pos + 1)
  return b2 * 256 + b1
end

local expected_header = 'BM' .. le32(122 + 4096) .. '\0\0' .. '\0\0' .. le32(122)
  .. le32(108) .. le32(32) .. le32(32) .. char(1, 0) .. char(32, 0)
  .. le32(3) .. le32(4096) .. le32(0) .. le32(0) .. le32(0) .. le32(0)
  .. char(0, 0, 255, 0) .. char(0, 255, 0, 0) .. char(255, 0, 0, 0) .. char(0, 0, 0, 255)
  .. 'sRGB' .. rep('\0', 36) .. le32(0) .. le32(0) .. le32(0)

-- ---- preload the fakes, then require the modules under test ----

local real_io  = package.loaded['io']
local real_log = package.loaded['log']

local fake_io = windower._make_fake_io(fake_fs)
local open_count = 0
local open_log = {}
local base_open = fake_io.open
fake_io.open = function(path, mode)
  open_count = open_count + 1
  local handle, err = base_open(path, mode)
  if handle then
    table.insert(open_log, { path = path, mode = mode or 'r', handle = handle })
  end
  return handle, err
end

local function opens_of(path, mode)
  local n = 0
  for _, entry in ipairs(open_log) do
    if entry.path == path and entry.mode == mode then n = n + 1 end
  end
  return n
end

package.loaded['io'] = fake_io

local log_stub = { _debug = {} }
log_stub.debug = function(fmt, ...) table.insert(log_stub._debug, { fmt, ... }) end
log_stub.info  = function() end
log_stub.error = function() end
package.loaded['log'] = log_stub

local icon_extractor = require('crossbar/icon_extractor')
local icons = require('icons')

local win_base = 'C:\\Program Files (x86)\\Windower4\\addons\\xivgamepad'
local out_4116_abs = win_base .. '\\data\\icons\\items\\4116.bmp'
local out_2_abs    = win_base .. '\\data\\icons\\items\\2.bmp'

-- ----

test('fixture self-check: inv_rot3 inverts the extractor byte rotation', function()
  for v = 0, 255 do
    assert_eq(v, rot3(inv_rot3(v)), 'rot3(inv_rot3(' .. v .. '))')
  end
end)

test('ported module registers no events and exposes close on the module table', function()
  assert_eq(nil, windower._events['unload'], 'no unload registration')
  assert_eq(nil, next(windower._events), 'no event registration at all')
  assert_eq('function', type(icon_extractor.close), 'close exposed')
  assert_eq('function', type(icon_extractor.item_by_id), 'item_by_id kept')
  assert_eq('function', type(icon_extractor.buff_by_id), 'buff_by_id kept')
  assert_eq('function', type(icon_extractor.ffxi_path), 'ffxi_path kept')
end)

test('item_icon before init returns nil without raising', function()
  local ok, result = pcall(icons.item_icon, 4116)
  assert_eq(true, ok, 'no raise before init')
  assert_eq(nil, result, 'nil before init')
end)

test('extraction writes the BMP to the absolute output path and returns the relative path', function()
  icons.init(windower.addon_path)
  assert_eq('data/icons/items/4116.bmp', icons.item_icon(4116), 'addon-relative path')
  local content = fake_fs[out_4116_abs]
  assert(content, 'BMP written at ' .. out_4116_abs)
  assert_eq(122 + 4096, #content, 'header + 32x32x4 pixel bytes')
  assert_bytes(expected_header, content:sub(1, 122), 'exact 122-byte header')
end)

test('first extraction creates the icon dirs: absolute, separator-matched, never above addon_path', function()
  assert_eq(3, #windower._created_dirs, 'three dir levels created')
  assert_eq(win_base .. '\\data',                 windower._created_dirs[1], 'data dir')
  assert_eq(win_base .. '\\data\\icons',          windower._created_dirs[2], 'icons dir')
  assert_eq(win_base .. '\\data\\icons\\items',   windower._created_dirs[3], 'items dir')
  for _, dir in ipairs(windower._created_dirs) do
    assert_eq(1, dir:find(win_base, 1, true), 'anchored beneath addon_path: ' .. dir)
  end
end)

test('BMP header fields decode: BM magic, sizes, offsets, dimensions', function()
  local content = fake_fs[out_4116_abs]
  assert_eq('BM', content:sub(1, 2), 'magic')
  assert_eq(122 + 4096, ru32(content, 3), 'file size field')
  assert_eq(122, ru32(content, 11), 'pixel array starting address')
  assert_eq(108, ru32(content, 15), 'DIB header size (BITMAPV4)')
  assert_eq(32, ru32(content, 19), 'width')
  assert_eq(32, ru32(content, 23), 'height')
  assert_eq(1, ru16(content, 27), 'color planes')
  assert_eq(32, ru16(content, 29), 'bits per pixel')
  assert_eq(3, ru32(content, 31), 'compression (BI_BITFIELDS)')
  assert_eq(4096, ru32(content, 35), 'image size')
end)

test('palette decode: rotated indexes resolve and alpha is doubled/clamped', function()
  local body = fake_fs[out_4116_abs]:sub(123)
  assert_bytes(body_4116, body, 'decoded pixel data')
end)

test('seek math: ids in different dat-map ranges extract their own records', function()
  assert_eq('data/icons/items/2.bmp', icons.item_icon(2), 'general-range path')
  local content = fake_fs[out_2_abs]
  assert(content, 'BMP written at ' .. out_2_abs)
  assert_bytes(expected_header, content:sub(1, 122), 'header for id 2')
  assert_bytes(body_2, content:sub(123), 'general-range record decoded')
  assert_eq(1, opens_of(dat_106_path, 'rb'), 'general DAT opened')
  assert_eq(1, opens_of(dat_107_path, 'rb'), 'usable DAT opened')
end)

test('cache hit: second request for the same id performs no io.open', function()
  local before = open_count
  assert_eq('data/icons/items/4116.bmp', icons.item_icon(4116), 'same path returned')
  assert_eq(before, open_count, 'no io.open on cache hit')
end)

test('cache hit: a file pre-existing via files.exists short-circuits extraction', function()
  icons.init(windower.addon_path)
  windower._fs['data/icons/items/4157.bmp'] = 'cached from a previous session'
  local before = open_count
  assert_eq('data/icons/items/4157.bmp', icons.item_icon(4157), 'cached path returned')
  assert_eq(before, open_count, 'no io.open when files.exists hits')
end)

test('name resolution: res.items en match is case-insensitive', function()
  assert_eq('data/icons/items/4116.bmp', icons.item_icon('hi-potion'), 'lowercase name')
  assert_eq('data/icons/items/4116.bmp', icons.item_icon('HI-POTION'), 'uppercase name')
end)

test('name resolution: an augmented res.items entry resolves to its id', function()
  res.items[2] = { id = 2, en = 'Test Ingot', category = 'General' }
  local ok, err = pcall(function()
    assert_eq('data/icons/items/2.bmp', icons.item_icon('Test INGOT'), 'augmented entry')
  end)
  res.items[2] = nil
  assert(ok, tostring(err))
end)

test('unresolvable name: nil with exactly one log.debug per name per session', function()
  local before = #log_stub._debug
  assert_eq(nil, icons.item_icon('No Such Item'), 'first request nil')
  assert_eq(before + 1, #log_stub._debug, 'one debug line')
  assert_eq(nil, icons.item_icon('No Such Item'), 'repeat request nil')
  assert_eq(nil, icons.item_icon('NO SUCH ITEM'), 'case variant shares the memo')
  assert_eq(before + 1, #log_stub._debug, 'still one debug line')
end)

test('unresolvable name: repeat lookup is memoized and never rescans res.items', function()
  local scan_hits = 0
  local probe = setmetatable({}, { __index = function(_, key)
    if key == 'en' then scan_hits = scan_hits + 1 end
    return nil
  end })
  res.items[59999] = probe
  local before = #log_stub._debug
  local ok, err = pcall(function()
    assert_eq(nil, icons.item_icon('Memoized Missing Item'), 'first request nil')
    assert_eq(1, scan_hits, 'first miss performs the one full scan')
    assert_eq(nil, icons.item_icon('Memoized Missing Item'), 'repeat request nil')
    assert_eq(1, scan_hits, 'repeat miss does not rescan res.items')
    assert_eq(before + 1, #log_stub._debug, 'exactly one debug line')
  end)
  res.items[59999] = nil
  assert(ok, tostring(err))
end)

test('junk input never raises', function()
  local ok, result = pcall(icons.item_icon, {})
  assert_eq(true, ok, 'table input does not raise')
  assert_eq(nil, result, 'table input returns nil')
  ok, result = pcall(icons.item_icon, nil)
  assert_eq(true, ok, 'nil input does not raise')
  assert_eq(nil, result, 'nil input returns nil')
end)

test('missing DAT: nil with exactly one log.debug and one open attempt per id', function()
  local before_log = #log_stub._debug
  local before_open = open_count
  assert_eq(nil, icons.item_icon(0x2800), 'armor-range DAT absent from the fake fs')
  assert_eq(before_log + 1, #log_stub._debug, 'one debug line')
  assert_eq(before_open + 1, open_count, 'one open attempt')
  assert_eq(nil, icons.item_icon(0x2800), 'repeat request nil')
  assert_eq(before_log + 1, #log_stub._debug, 'still one debug line')
  assert_eq(before_open + 1, open_count, 'no second open attempt')
end)

test('close() closes the cached DAT handles', function()
  local dat_handles = {}
  for _, entry in ipairs(open_log) do
    if entry.mode == 'rb' then table.insert(dat_handles, entry) end
  end
  assert_eq(2, #dat_handles, 'one handle per DAT range')
  for _, entry in ipairs(dat_handles) do
    assert_eq(false, entry.handle._closed, 'handle open before close(): ' .. entry.path)
  end
  icons.close()
  for _, entry in ipairs(dat_handles) do
    assert_eq(true, entry.handle._closed, 'handle closed: ' .. entry.path)
  end
end)

test('after close(), the next extraction reopens the DAT', function()
  icons.init(windower.addon_path)
  local rb_before = opens_of(dat_107_path, 'rb')
  assert_eq('data/icons/items/4116.bmp', icons.item_icon(4116), 're-extraction succeeds')
  assert_eq(rb_before + 1, opens_of(dat_107_path, 'rb'), 'DAT reopened')
end)

test('unix-style addon_path: forward-slash dirs and output path', function()
  windower._reset()
  local unix_base = '/home/user/Windower4/addons/xivgamepad'
  icons.init(unix_base .. '/')
  assert_eq('data/icons/items/4116.bmp', icons.item_icon(4116), 'relative path unchanged')
  assert_eq(3, #windower._created_dirs, 'three dir levels created')
  assert_eq(unix_base .. '/data',             windower._created_dirs[1], 'data dir')
  assert_eq(unix_base .. '/data/icons',       windower._created_dirs[2], 'icons dir')
  assert_eq(unix_base .. '/data/icons/items', windower._created_dirs[3], 'items dir')
  local content = fake_fs[unix_base .. '/data/icons/items/4116.bmp']
  assert(content, 'BMP written at the unix absolute path')
  assert_bytes(expected_header .. body_4116, content, 'full BMP content')
end)

-- ----

-- Restore the shared environment for later manifest files: the real io (per
-- the mock's _make_fake_io usage comment), the previously cached log module,
-- and a fresh require for the modules bound to this file's fakes.
package.loaded['io'] = real_io
package.loaded['log'] = real_log
package.loaded['crossbar/icon_extractor'] = nil
package.loaded['icons'] = nil
windower._reset()

io.write(string.format('test_icons: %d passed, %d failed\n', pass, fail))
if fail > 0 then
  error(fail .. ' test(s) failed in test_icons.lua')
end
