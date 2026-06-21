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

-- In-memory filesystem for this test file
local vfs = {}
settings._set_io_provider({
  read_file  = function(path) return vfs[path] end,
  write_file = function(path, content) vfs[path] = content end,
})

-- These tests manipulate login state, so they must NOT auto-init.
local function load_addon()
  settings.discard()
  return dofile('echo/echo.lua')
end

-- ----

test('on_load defers init when not logged in (no crash, no element)', function()
  windower.ffxi._player = nil
  vfs = {}
  local e = load_addon()
  e.on_load()
  assert_eq(nil, e.get_element(), 'no element created pre-login')
  assert_eq(nil, e.get_live(),    'no settings loaded pre-login')
end)

test('login initializes and loads the current character settings', function()
  vfs = {}
  vfs['/addon/data/TestChar/settings.json'] = '{"text":"Saved","pos_x":5,"pos_y":6}'
  windower.ffxi._player = { name = 'TestChar' }
  local e = load_addon()
  e.init()
  assert_eq('Saved', e.get_live().text,  'text loaded')
  assert_eq(5,       e.get_live().pos_x, 'pos_x loaded')
  assert_eq(6,       e.get_live().pos_y, 'pos_y loaded')
  assert_eq('Saved', e.get_element()._text, 'element shows loaded text')
end)

test('init shows the overlay', function()
  vfs = {}
  windower.ffxi._player = { name = 'TestChar' }
  local e = load_addon()
  e.init()
  assert_eq(true, e.get_element()._visible, 'overlay shown after init')
end)

test('character switch reloads settings and does not clobber the other character file', function()
  vfs = {}
  vfs['/addon/data/Beta/settings.json'] = '{"text":"Beta","pos_x":99,"pos_y":99}'
  windower.ffxi._player = { name = 'Alpha' }
  local e = load_addon()
  e.init()
  e.cmd_set('AlphaText')
  e.setup_open(); e.change_pos(11, 22); e.setup_close_save()
  windower.ffxi._player = { name = 'Beta' }
  e.init()
  assert_eq('Beta', e.get_live().text,  'Beta settings loaded, not Alpha')
  assert_eq(99,     e.get_live().pos_x, 'Beta pos loaded')
  e.cmd_set('BetaNew')
  windower.ffxi._player = { name = 'Beta' }
  local b = settings.load('/addon/', {})
  assert_eq('BetaNew', b.text, 'Beta file received the new text')
  windower.ffxi._player = { name = 'Alpha' }
  local a = settings.load('/addon/', {})
  assert_eq('AlphaText', a.text,  'Alpha text intact')
  assert_eq(11,          a.pos_x, 'Alpha pos intact')
end)

test('init during an open setup session discards the stale staged state', function()
  vfs = {}
  windower.ffxi._player = { name = 'TestChar' }
  local e = load_addon()
  e.init()
  e.setup_open()
  assert_eq(true, settings.in_setup(), 'in setup after setup_open')
  e.change_pos(40, 50)
  e.init()
  assert_eq(false, settings.in_setup(),        'session cleared by re-init')
  assert_eq(nil,   e.get_staged(),             'staged cleared by re-init')
  assert_eq(false, e.get_element()._draggable, 're-init leaves element non-draggable')
end)

test('logout hides the overlay and abandons an open setup session', function()
  vfs = {}
  windower.ffxi._player = { name = 'TestChar' }
  local e = load_addon()
  e.init()
  e.setup_open()
  assert_eq(true, settings.in_setup(), 'in setup before logout')
  e.on_logout()
  assert_eq(false, e.get_element()._visible,   'overlay hidden')
  assert_eq(false, settings.in_setup(),        'setup session abandoned')
  assert_eq(nil,   e.get_staged(),             'staged cleared')
  assert_eq(false, e.get_element()._draggable, 'draggable disabled')
end)

test('on_load initializes the overlay when already logged in', function()
  vfs = {}
  vfs['/addon/data/TestChar/settings.json'] = '{"text":"Live","pos_x":7,"pos_y":8}'
  windower.ffxi._player = { name = 'TestChar' }
  local e = load_addon()
  e.on_load()
  assert(e.get_element() ~= nil, 'element created when loaded while logged in')
  assert_eq('Live', e.get_live().text,      'live settings loaded via on_load')
  assert_eq('Live', e.get_element()._text,  'overlay shows loaded text')
  assert_eq(true,   e.get_element()._visible, 'overlay shown')
end)

test('logout before init is safe when no element exists', function()
  vfs = {}
  windower.ffxi._player = { name = 'TestChar' }
  local e = load_addon()
  e.on_logout()
  assert_eq(nil,   e.get_element(), 'element stays nil')
  assert_eq(false, settings.in_setup(), 'no setup session opened')
end)

test('logout when not in setup hides the overlay without error', function()
  vfs = {}
  windower.ffxi._player = { name = 'TestChar' }
  local e = load_addon()
  e.init()
  assert_eq(false, settings.in_setup(), 'not in setup')
  e.on_logout()
  assert_eq(false, e.get_element()._visible,   'overlay hidden')
  assert_eq(false, e.get_element()._draggable, 'draggable disabled')
end)

test('init reuses the same element across re-init (no leak)', function()
  vfs = {}
  windower.ffxi._player = { name = 'TestChar' }
  local e = load_addon()
  e.init()
  local first = e.get_element()
  e.init()
  assert(e.get_element() == first, 're-init must reuse the existing element, not recreate it')
end)

test('login creates the config window hidden and non-draggable', function()
  vfs = {}
  windower.ffxi._player = { name = 'TestChar' }
  local e = load_addon()
  e.init()
  assert(e.get_gui() ~= nil, 'gui created on init')
  assert_eq(false, e.get_gui():is_open(), 'config window starts hidden')
end)

test('init reuses the same gui across re-init (no leak)', function()
  vfs = {}
  windower.ffxi._player = { name = 'TestChar' }
  local e = load_addon()
  e.init()
  local first = e.get_gui()
  e.init()
  assert(e.get_gui() == first, 're-init must reuse the existing gui, not recreate it')
end)

test('re-init during an open config session clears staging and hides the window', function()
  vfs = {}
  windower.ffxi._player = { name = 'TestChar' }
  local e = load_addon()
  e.init()
  e.setup_open()
  assert_eq(true, e.get_gui():is_open(), 'window open after config')
  assert_eq(true, settings.in_setup(), 'in setup after config')
  e.init()
  assert_eq(false, e.get_gui():is_open(), 're-init hides the config window')
  assert_eq(false, settings.in_setup(), 're-init clears stale staging')
  assert_eq(nil,   e.get_staged(),       're-init clears staged table')
end)

test('logout hides the config window and abandons an open config session', function()
  vfs = {}
  windower.ffxi._player = { name = 'TestChar' }
  local e = load_addon()
  e.init()
  e.setup_open()
  assert_eq(true, e.get_gui():is_open(), 'window open before logout')
  e.on_logout()
  assert_eq(false, e.get_gui():is_open(), 'config window hidden on logout')
  assert_eq(false, settings.in_setup(),   'setup session abandoned on logout')
end)

test('logout before init is safe when no gui exists', function()
  vfs = {}
  windower.ffxi._player = { name = 'TestChar' }
  local e = load_addon()
  local ok = pcall(function() e.on_logout() end)
  assert_eq(true, ok, 'logout before init must not error')
  assert_eq(nil, e.get_gui(), 'gui stays nil before init')
end)

test('on_mouse before init is safe (no gui, no setup)', function()
  vfs = {}
  windower.ffxi._player = { name = 'TestChar' }
  local e = load_addon()
  local ok, result = pcall(function() return e.on_mouse(1, 10, 10) end)
  assert_eq(true,  ok,     'on_mouse before init must not error')
  assert_eq(false, result, 'on_mouse before init returns false')
end)

test('unload destroys the overlay and the config window', function()
  vfs = {}
  windower.ffxi._player = { name = 'TestChar' }
  local e = load_addon()
  e.init()
  local el  = e.get_element()
  local g   = e.get_gui()
  windower._events['unload']()
  assert_eq(true,  el._destroyed,        'overlay destroyed on unload')
  assert_eq(false, g:is_open(),          'gui closed on unload')
end)

test('unload before init is safe when nothing was created', function()
  vfs = {}
  windower.ffxi._player = { name = 'TestChar' }
  load_addon()
  local ok = pcall(function() windower._events['unload']() end)
  assert_eq(true, ok, 'unload before init must not error')
end)

-- ----

windower.ffxi._player = { name = 'TestChar' }
settings.discard()

io.write(string.format('test_lifecycle: %d passed, %d failed\n', pass, fail))
if fail > 0 then
  error(fail .. ' test(s) failed in test_lifecycle.lua')
end
