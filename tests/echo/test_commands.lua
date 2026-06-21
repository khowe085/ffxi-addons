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

local function contains(haystack, needle)
  return haystack:find(needle, 1, true) ~= nil
end

-- In-memory filesystem for this test file
local vfs = {}
settings._set_io_provider({
  read_file  = function(path) return vfs[path] end,
  write_file = function(path, content) vfs[path] = content end,
})

local char_path = '/addon/data/TestChar/settings.json'

local function fresh()
  windower.ffxi._player = { name = 'TestChar' }
  vfs = {}
  settings.discard()
  local e = dofile('echo/echo.lua')
  e.init()
  return e
end

-- ----

test('cmd_set outside setup writes text to live', function()
  local e = fresh()
  e.cmd_set('Hello World')
  assert_eq('Hello World', e.get_live().text, 'live text should be set')
end)

test('cmd_set outside setup commits to the vfs', function()
  local e = fresh()
  e.cmd_set('Hello World')
  assert(vfs[char_path] ~= nil, 'settings file should be written on cmd_set')
  local reloaded = settings.load('/addon/', { text = '', pos_x = 0, pos_y = 0 })
  assert_eq('Hello World', reloaded.text, 'reloaded text should match committed value')
end)

test('cmd_set outside setup updates the element', function()
  local e = fresh()
  e.cmd_set('Hello World')
  assert_eq('Hello World', e.get_element()._text, 'element text should be updated')
end)

test('cmd_set outside setup never opens setup or the config window', function()
  local e = fresh()
  e.cmd_set('Hello World')
  assert_eq(false, settings.in_setup(), 'in_setup must stay false after a plain set')
  assert_eq(false, e.get_gui():is_open(), 'config window must not open on a plain set')
  assert_eq(nil, e.get_staged(), 'no staging session may be opened by a plain set')
end)

test('cmd_clear outside setup never opens setup or the config window', function()
  local e = fresh()
  e.cmd_set('Hello World')
  e.cmd_clear()
  assert_eq('', e.get_live().text, 'live text should be cleared')
  assert_eq(false, settings.in_setup(), 'in_setup must stay false after a plain clear')
  assert_eq(false, e.get_gui():is_open(), 'config window must not open on a plain clear')
  assert_eq(nil, e.get_staged(), 'no staging session may be opened by a plain clear')
end)

test('cmd_set/cmd_clear outside setup never stage SAMPLE TEXT', function()
  local e = fresh()
  e.cmd_set('Hello World')
  e.cmd_clear()
  assert(not contains(vfs[char_path] or '', 'SAMPLE TEXT'),
    'SAMPLE TEXT must never be written by set/clear outside config')
  assert_eq(false, settings.in_setup(), 'in_setup false after set/clear')
  e.dispatch('config')
  assert_eq('SAMPLE TEXT', e.get_staged().text, 'SAMPLE TEXT appears only after explicit config')
  e.dispatch('discard')
end)

test('cmd_set inside setup stages text only', function()
  local e = fresh()
  e.setup_open()
  e.cmd_set('Hi')
  assert_eq('Hi', e.get_staged().text, 'staged text should be set')
end)

test('cmd_set inside setup leaves live unchanged', function()
  local e = fresh()
  e.setup_open()
  e.cmd_set('Hi')
  assert_eq('', e.get_live().text, 'live text should be unchanged during setup')
end)

test('cmd_set inside setup updates the element', function()
  local e = fresh()
  e.setup_open()
  e.cmd_set('Hi')
  assert_eq('Hi', e.get_element()._text, 'element text should reflect staged value')
end)

test('cmd_set inside setup does not write to the vfs', function()
  local e = fresh()
  e.setup_open()
  e.cmd_set('Hi')
  assert_eq(nil, vfs[char_path], 'no file should be written while staging')
end)

test('setup_close_save commits staged text to live', function()
  local e = fresh()
  e.setup_open()
  e.cmd_set('Hi')
  e.setup_close_save()
  assert_eq('Hi', e.get_live().text, 'staged text should be committed to live on save')
end)

test('cmd_clear delegates to cmd_set with empty string (element)', function()
  local e = fresh()
  e.cmd_set('X')
  e.cmd_clear()
  assert_eq('', e.get_element()._text, 'element text should be cleared')
end)

test('cmd_clear delegates to cmd_set with empty string (live)', function()
  local e = fresh()
  e.cmd_set('X')
  e.cmd_clear()
  assert_eq('', e.get_live().text, 'live text should be cleared')
end)

test('print_help prints a line for every command', function()
  local e = fresh()
  windower._chat = {}
  e.print_help()
  local output = table.concat(windower._chat, '\n')
  assert(contains(output, '//ec set'),    'help should list //ec set')
  assert(contains(output, '//ec clear'),  'help should list //ec clear')
  assert(contains(output, '//ec config'),  'help should list //ec config')
  assert(contains(output, '//ec save'),    'help should list //ec save')
  assert(contains(output, '//ec discard'), 'help should list //ec discard')
  assert(contains(output, '//ec help'),   'help should list //ec help')
end)

test('dispatch set joins multi-word text and displays it', function()
  local e = fresh()
  e.dispatch('set', 'Hello', 'World')
  assert_eq('Hello World', e.get_element()._text, 'element shows joined text')
  assert_eq('Hello World', e.get_live().text, 'live text is joined text')
end)

test('dispatch set with no args prints help and does not change text', function()
  local e = fresh()
  windower._chat = {}
  e.dispatch('set')
  assert_eq('', e.get_live().text, 'live text unchanged')
  assert_eq('', e.get_element()._text, 'element text unchanged')
  local output = table.concat(windower._chat, '\n')
  assert(contains(output, '//ec help'), 'help should be printed')
  assert_eq(nil, vfs[char_path], 'empty-set guard must not commit a settings file')
end)

test('dispatch clear empties the text', function()
  local e = fresh()
  e.dispatch('set', 'X')
  e.dispatch('clear')
  assert_eq('', e.get_element()._text, 'element text cleared')
  assert_eq('', e.get_live().text, 'live text cleared')
end)

test('dispatch unknown command prints help', function()
  local e = fresh()
  windower._chat = {}
  e.dispatch('bogus')
  local output = table.concat(windower._chat, '\n')
  assert(contains(output, '//ec help'), 'help should be printed for unknown command')
end)

test('dispatch nil command prints help', function()
  local e = fresh()
  windower._chat = {}
  e.dispatch(nil)
  local output = table.concat(windower._chat, '\n')
  assert(contains(output, '//ec help'), 'help should be printed for nil command')
end)

test('dispatch discard discards staged changes', function()
  local e = fresh()
  e.dispatch('config')
  e.change_pos(70, 80)
  e.dispatch('discard')
  assert_eq(nil, e.get_staged(), 'staged should be nil after discard')
  assert_eq(0, e.get_live().pos_x, 'live.pos_x unchanged after discard')
  assert_eq(nil, vfs[char_path], 'discard must not write to vfs')
end)

test('dispatch d discards staged changes', function()
  local e = fresh()
  e.dispatch('config')
  e.change_pos(70, 80)
  e.dispatch('d')
  assert_eq(nil, e.get_staged(), 'staged should be nil after d')
  assert_eq(0, e.get_live().pos_x, 'live.pos_x unchanged after d')
  assert_eq(nil, vfs[char_path], 'discard must not write to vfs')
end)

test('dispatch save persists staged changes', function()
  local e = fresh()
  e.dispatch('config')
  e.change_pos(70, 80)
  e.dispatch('save')
  assert_eq(nil, e.get_staged(), 'staged should be nil after save')
  assert_eq(70, e.get_live().pos_x, 'live.pos_x committed after save')
  assert(vfs[char_path] ~= nil, 'save must write to vfs')
end)

test('dispatch s persists staged changes', function()
  local e = fresh()
  e.dispatch('config')
  e.change_pos(70, 80)
  e.dispatch('s')
  assert_eq(nil, e.get_staged(), 'staged should be nil after s')
  assert_eq(70, e.get_live().pos_x, 'live.pos_x committed after s')
  assert(vfs[char_path] ~= nil, 'save must write to vfs')
end)

test('dispatch c opens config', function()
  local e = fresh()
  e.dispatch('c')
  assert_eq(true, e.get_staged() ~= nil, 'c should open a staging session')
  e.dispatch('discard')
end)

-- ----

io.write(string.format('test_commands: %d passed, %d failed\n', pass, fail))
if fail > 0 then
  error(fail .. ' test(s) failed in test_commands.lua')
end
