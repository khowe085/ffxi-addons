local settings = require('lib.settings.settings')

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

-- In-memory filesystem for this test file
local vfs = {}
settings._set_io_provider({
  read_file  = function(path) return vfs[path] end,
  write_file = function(path, content) vfs[path] = content end,
})

local char_path = '/addon/data/TestChar/settings.json'

local function fresh(file)
  windower.ffxi._player = { name = 'TestChar' }
  vfs = {}
  if file then vfs[char_path] = file end
  settings.discard()
  local e = dofile('echo/echo.lua')
  e.init()
  return e
end

-- Echo's `size` is the BODY area (380x110); the total window is body + chrome.
-- One tab => total_width = 380+18 = 398, total_height = 18+110+36 = 164. The
-- footer band is the bottom two rows, y in [128,164) (center y = 146), holding a
-- right-aligned fixed-width Save/Discard pair (BTN_W = 96): Discard at x [298,394)
-- (center 346), Save just left of it at x [196,292) (center 244). Header row is
-- the top 18px.
local function save_point(gui_anchor_x, gui_anchor_y)
  return gui_anchor_x + 244, gui_anchor_y + 146
end

local function discard_point(gui_anchor_x, gui_anchor_y)
  return gui_anchor_x + 346, gui_anchor_y + 146
end

local function header_point(gui_anchor_x, gui_anchor_y)
  return gui_anchor_x + 5, gui_anchor_y + 5
end

-- ----

test('config opens the window: gui visible, overlay draggable, staging open', function()
  local e = fresh()
  e.dispatch('config')
  assert_eq(true, e.get_gui():is_open(), 'gui open after config')
  assert_eq(true, e.get_element()._draggable, 'overlay draggable during config')
  assert_eq(true, settings.in_setup(), 'staging session open')
end)

test('second config while open is a no-op', function()
  local e = fresh()
  e.dispatch('config')
  local staged_first = e.get_staged()
  e.dispatch('config')
  assert_eq(staged_first, e.get_staged(), 'staged table not recreated by second config')
  assert_eq(true, e.get_gui():is_open(), 'window still open')
end)

test('opening with empty text stages SAMPLE TEXT and overlay shows it', function()
  local e = fresh()
  e.dispatch('config')
  assert_eq('SAMPLE TEXT', e.get_staged().text, 'staged text defaults to SAMPLE TEXT')
  assert_eq('SAMPLE TEXT', e.get_element()._text, 'overlay shows SAMPLE TEXT')
end)

test('opening with non-empty text leaves it unchanged', function()
  local e = fresh('{"text":"Hello","pos_x":0,"pos_y":0,"config_x":100,"config_y":100}')
  e.dispatch('config')
  assert_eq('Hello', e.get_staged().text, 'existing text preserved')
end)

test('save command commits staged (incl SAMPLE TEXT), hides, clears staging, draggable off', function()
  local e = fresh()
  e.dispatch('config')
  e.dispatch('save')
  assert_eq('SAMPLE TEXT', e.get_live().text, 'SAMPLE TEXT committed to live')
  assert_eq(false, e.get_gui():is_open(), 'window hidden after save')
  assert_eq(nil, e.get_staged(), 'staging cleared after save')
  assert_eq(false, e.get_element()._draggable, 'overlay draggable off after save')
  assert_true(vfs[char_path] ~= nil, 'settings written on save')
end)

test('Save-button click commits and closes the window', function()
  local e = fresh()
  e.dispatch('config')
  local sx, sy = save_point(100, 100)
  local consumed = e.on_mouse(1, sx, sy)
  assert_eq(true, consumed, 'save click consumed/blocked')
  assert_eq('SAMPLE TEXT', e.get_live().text, 'SAMPLE TEXT committed via Save button')
  assert_eq(false, e.get_gui():is_open(), 'window closed via Save button')
  assert_eq(nil, e.get_staged(), 'staging cleared via Save button')
end)

test('discard command leaves live text unchanged, hides, clears staging', function()
  local e = fresh()
  e.cmd_set('KeepMe')
  vfs[char_path] = nil
  e.dispatch('config')
  e.cmd_set('Throwaway')
  e.dispatch('discard')
  assert_eq('KeepMe', e.get_live().text, 'live text unchanged after discard')
  assert_eq(false, e.get_gui():is_open(), 'window hidden after discard')
  assert_eq(nil, e.get_staged(), 'staging cleared after discard')
  assert_eq(nil, vfs[char_path], 'discard does not write')
end)

test('Discard-button click leaves live text unchanged and closes', function()
  local e = fresh('{"text":"KeepMe","pos_x":0,"pos_y":0,"config_x":100,"config_y":100}')
  e.dispatch('config')
  e.cmd_set('Throwaway')
  local dx, dy = discard_point(100, 100)
  local consumed = e.on_mouse(1, dx, dy)
  assert_eq(true, consumed, 'discard click consumed/blocked')
  assert_eq('KeepMe', e.get_live().text, 'live text unchanged via Discard button')
  assert_eq(false, e.get_gui():is_open(), 'window closed via Discard button')
end)

test('overlay drag-release updates staged pos and refreshes body', function()
  local e = fresh()
  e.dispatch('config')
  local el = e.get_element()
  -- Move the overlay (simulating Windower's built-in drag), then mouse-up
  -- OUTSIDE the window so the gui does not consume it.
  el._x = 12
  el._y = 34
  local consumed = e.on_mouse(2, 0, 0)
  assert_eq(false, consumed, 'release outside window is not consumed by gui')
  assert_eq(12, e.get_staged().pos_x, 'staged pos_x updated on release')
  assert_eq(34, e.get_staged().pos_y, 'staged pos_y updated on release')
  -- The body read-outs are refreshed (set_tabs called) — gui still open.
  assert_eq(true, e.get_gui():is_open(), 'window remains open after overlay drag')
end)

test('config-window drag stages config_x/config_y; save persists; reopen at new anchor', function()
  local e = fresh()
  e.dispatch('config')
  -- Drag the window header from anchor (100,100) by +30,+40.
  local hx, hy = header_point(100, 100)
  assert_eq(true, e.on_mouse(1, hx, hy), 'header down consumed')
  assert_eq(true, e.on_mouse(0, hx + 30, hy + 40), 'move consumed')
  assert_eq(true, e.on_mouse(2, hx + 30, hy + 40), 'release consumed')
  assert_eq(130, e.get_staged().config_x, 'staged config_x')
  assert_eq(140, e.get_staged().config_y, 'staged config_y')
  e.dispatch('save')
  assert_eq(130, e.get_live().config_x, 'config_x persisted to live')
  assert_eq(140, e.get_live().config_y, 'config_y persisted to live')

  -- Reload and reopen: the window opens at the persisted anchor, so a Save
  -- click at the NEW footer location commits.
  windower.ffxi._player = { name = 'TestChar' }
  local e2 = dofile('echo/echo.lua')
  e2.init()
  e2.dispatch('config')
  local sx, sy = save_point(130, 140)
  assert_eq(true, e2.on_mouse(1, sx, sy), 'save click at the persisted anchor consumed')
  assert_eq(false, e2.get_gui():is_open(), 'window closed at persisted anchor')
end)

test('config-window drag then discard reverts the anchor', function()
  local e = fresh()
  e.dispatch('config')
  local hx, hy = header_point(100, 100)
  e.on_mouse(1, hx, hy)
  e.on_mouse(0, hx + 50, hy + 60)
  e.on_mouse(2, hx + 50, hy + 60)
  e.dispatch('discard')
  assert_eq(100, e.get_live().config_x, 'config_x reverted after discard')
  assert_eq(100, e.get_live().config_y, 'config_y reverted after discard')
  -- Next open uses the prior live anchor (100,100): a Save click there commits.
  e.dispatch('config')
  local sx, sy = save_point(100, 100)
  assert_eq(true, e.on_mouse(1, sx, sy), 'save click at original anchor consumed')
  assert_eq(false, e.get_gui():is_open(), 'window closed at original anchor')
end)

test('clicks over the window are blocked; clicks outside are not', function()
  local e = fresh()
  e.dispatch('config')
  -- A point inside the body (off every control).
  assert_eq(true, e.on_mouse(1, 150, 150), 'click over window blocked')
  -- A point well outside the window.
  assert_eq(false, e.on_mouse(1, 1000, 1000), 'click outside not blocked')
end)

test('window is not draggable after save (no gui consumption when closed)', function()
  local e = fresh()
  e.dispatch('config')
  e.dispatch('save')
  -- With the window closed, gui:is_open() is false so on_mouse does not consume.
  assert_eq(false, e.on_mouse(1, 150, 150), 'closed window does not block clicks')
end)

test('print_help includes the updated config description', function()
  local e = fresh()
  windower._chat = {}
  e.print_help()
  local output = table.concat(windower._chat, '\n')
  assert_true(output:find('//ec config', 1, true) ~= nil, 'help lists //ec config')
  assert_true(output:find('config window', 1, true) ~= nil, 'help mentions the config window')
end)

-- ----

windower.ffxi._player = { name = 'TestChar' }
settings.discard()

io.write(string.format('test_config_gui: %d passed, %d failed\n', pass, fail))
if fail > 0 then
  error(fail .. ' test(s) failed in test_config_gui.lua')
end
