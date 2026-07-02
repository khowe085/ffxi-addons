-- Earlier test files in the manifest may have preloaded a xivgamepad.log stub;
-- clear it so this file exercises the real module (and its load-time state).
package.loaded['xivgamepad.log'] = nil
local log = require('xivgamepad.log')

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

local win_path     = 'C:\\Program Files (x86)\\Windower4\\addons\\xivgamepad\\'
local win_data_dir = 'C:\\Program Files (x86)\\Windower4\\addons\\xivgamepad\\data'

local unix_path     = '/home/user/Windower4/addons/xivgamepad/'
local unix_data_dir = '/home/user/Windower4/addons/xivgamepad/data'

-- The files API resolves paths relative to windower.addon_path, so the log
-- file key is the same addon-relative path under both addon_path styles.
local rel_log_path = 'data/debug.log'

local ts_pattern = '%d%d%d%d%-%d%d%-%d%d %d%d:%d%d:%d%d'

local function fresh(path)
  windower._reset()
  log.set_debug(false)
  log.init(path or win_path)
end

local function fs_is_empty()
  return next(windower._fs) == nil
end

local function file_lines(path)
  local content = windower._fs[path]
  assert(content, 'expected log file at ' .. path)
  local lines = {}
  for line in content:gmatch('[^\n]+') do
    table.insert(lines, line)
  end
  return lines
end

-- ----

test('debug_enabled starts false on module load', function()
  windower._reset()
  assert_eq(false, log.is_debug(), 'starts disabled')
end)

test('debug is a no-op while disabled: no chat, no file', function()
  fresh()
  log.debug('hidden %d', 1)
  assert_eq(0, #windower._chat, 'chat entries')
  assert(fs_is_empty(), 'no file writes')
end)

test('info and error reach chat with the addon prefix while disabled; file untouched', function()
  fresh()
  log.info('hello')
  log.error('bad thing')
  assert_eq(2, #windower._chat, 'chat entries')
  assert_eq('XIVGamepad: hello', windower._chat[1], 'info line')
  assert_eq('XIVGamepad: bad thing', windower._chat[2], 'error line')
  assert(fs_is_empty(), 'no file writes')
end)

test('set_debug(true) creates the data dir with backslash separators anchored at addon_path', function()
  fresh()
  log.set_debug(true)
  assert_eq(1, #windower._created_dirs, 'exactly one dir created')
  assert_eq(win_data_dir, windower._created_dirs[1], 'data dir path')
end)

test('set_debug(true) truncates debug.log with a timestamped session header at the files-API relative path', function()
  fresh()
  windower._fs[rel_log_path] = 'stale previous content\n'
  log.set_debug(true)
  assert_eq(true, log.is_debug(), 'debug enabled')
  local lines = file_lines(rel_log_path)
  assert_eq(1, #lines, 'header only after truncation')
  assert(lines[1]:find('XIVGamepad debug session', 1, true), 'session header text: ' .. lines[1])
  assert(lines[1]:match(ts_pattern), 'header carries a timestamp: ' .. lines[1])
  assert(not windower._fs[rel_log_path]:find('stale previous content', 1, true), 'old content gone')
end)

test('while enabled, debug/info/error all hit chat and append timestamped file lines in order', function()
  fresh()
  log.set_debug(true)
  log.debug('d1')
  log.info('i1')
  log.error('e1')
  assert_eq(3, #windower._chat, 'chat entries')
  assert_eq('XIVGamepad: d1', windower._chat[1], 'debug chat')
  assert_eq('XIVGamepad: i1', windower._chat[2], 'info chat')
  assert_eq('XIVGamepad: e1', windower._chat[3], 'error chat')
  local lines = file_lines(rel_log_path)
  assert_eq(4, #lines, 'header + three lines')
  assert(lines[2]:match('^' .. ts_pattern .. ' %[debug%] d1$'), 'debug file line: ' .. lines[2])
  assert(lines[3]:match('^' .. ts_pattern .. ' %[info%] i1$'), 'info file line: ' .. lines[3])
  assert(lines[4]:match('^' .. ts_pattern .. ' %[error%] e1$'), 'error file line: ' .. lines[4])
end)

test('re-enabling debug truncates the previous session', function()
  fresh()
  log.set_debug(true)
  log.info('first session')
  log.set_debug(false)
  log.set_debug(true)
  assert(not windower._fs[rel_log_path]:find('first session', 1, true), 'previous session gone')
  assert_eq(1, #file_lines(rel_log_path), 'header only')
end)

test('set_debug(true) while already on does not re-truncate', function()
  fresh()
  log.set_debug(true)
  log.info('keep me')
  log.set_debug(true)
  assert(windower._fs[rel_log_path]:find('keep me', 1, true), 'existing lines kept')
end)

test('after set_debug(false): info/error still chat but the file stays as-is', function()
  fresh()
  log.set_debug(true)
  log.info('logged')
  local snapshot = windower._fs[rel_log_path]
  log.set_debug(false)
  log.info('chat only')
  log.error('chat only too')
  log.debug('silent again')
  assert_eq(snapshot, windower._fs[rel_log_path], 'file unchanged')
  assert_eq(3, #windower._chat, 'info/error chatted, debug silent')
  assert_eq('XIVGamepad: chat only too', windower._chat[3], 'error chat line')
end)

test('toggle flips and returns the new state', function()
  fresh()
  assert_eq(true, log.toggle(), 'first toggle returns true')
  assert_eq(true, log.is_debug(), 'enabled after first toggle')
  assert(windower._fs[rel_log_path] ~= nil, 'toggle-on starts a session file')
  assert_eq(false, log.toggle(), 'second toggle returns false')
  assert_eq(false, log.is_debug(), 'disabled after second toggle')
end)

test('format directives apply string.format semantics', function()
  fresh()
  log.info('x %d', 5)
  assert_eq('XIVGamepad: x 5', windower._chat[1], 'formatted line')
end)

test('plain message with no directives and no varargs does not raise', function()
  fresh()
  log.info('plain')
  assert_eq('XIVGamepad: plain', windower._chat[1], 'plain line')
end)

test('literal % with no varargs passes through verbatim without raising', function()
  fresh()
  log.error('progress 50% complete')
  assert_eq('XIVGamepad: progress 50% complete', windower._chat[1], 'verbatim line')
end)

test('escaped %% with varargs formats normally', function()
  fresh()
  log.info('50%% done, %d left', 3)
  assert_eq('XIVGamepad: 50% done, 3 left', windower._chat[1], 'formatted percent')
end)

test('mismatched format arguments fall back to the raw message without raising', function()
  fresh()
  log.error('count %d', 'not a number')
  assert_eq('XIVGamepad: count %d', windower._chat[1], 'raw fallback')
end)

test('info and error use distinct chat colors; debug shares the info color', function()
  fresh()
  local colors = {}
  local original_add = windower.add_to_chat
  windower.add_to_chat = function(color, msg)
    table.insert(colors, color)
    original_add(color, msg)
  end
  local ok, err = pcall(function()
    log.info('i')
    log.error('e')
    log.set_debug(true)
    log.debug('d')
  end)
  windower.add_to_chat = original_add
  assert(ok, tostring(err))
  assert_eq(207, colors[1], 'info color')
  assert_eq(167, colors[2], 'error color')
  assert(colors[1] ~= colors[2], 'info and error colors distinct')
  assert_eq(207, colors[3], 'debug shares info color')
end)

test('init is repeat-safe: state and session file survive re-init', function()
  fresh()
  log.set_debug(true)
  log.info('before reinit')
  log.init(win_path)
  assert_eq(true, log.is_debug(), 'debug state preserved')
  assert(windower._fs[rel_log_path]:find('before reinit', 1, true), 'file not truncated')
  log.info('after reinit')
  assert(windower._fs[rel_log_path]:find('after reinit', 1, true), 'appends continue')
  assert_eq(3, #file_lines(rel_log_path), 'header + two lines')
end)

test('set_debug(true) before init defers the session start until init', function()
  windower._reset()
  package.loaded['xivgamepad.log'] = nil
  local uninit = require('xivgamepad.log')
  uninit.set_debug(true)
  assert_eq(true, uninit.is_debug(), 'enabled before init')
  uninit.info('early line')
  assert_eq('XIVGamepad: early line', windower._chat[1], 'chat still works before init')
  assert(fs_is_empty(), 'file sink deferred before init')
  assert_eq(0, #windower._created_dirs, 'no dir creation before init')
  uninit.init(win_path)
  local lines = file_lines(rel_log_path)
  assert_eq(1, #lines, 'session header written at init time')
  assert(lines[1]:find('XIVGamepad debug session', 1, true), 'header text: ' .. lines[1])
  assert_eq(win_data_dir, windower._created_dirs[1], 'data dir created at init time')
  uninit.info('post init')
  assert(windower._fs[rel_log_path]:find('post init', 1, true), 'file sink live after init')
end)

test('set_debug(false) before init cancels a pending session start', function()
  windower._reset()
  package.loaded['xivgamepad.log'] = nil
  local uninit = require('xivgamepad.log')
  uninit.set_debug(true)
  uninit.set_debug(false)
  uninit.init(win_path)
  assert(fs_is_empty(), 'no session header after cancelled pending start')
  assert_eq(0, #windower._created_dirs, 'no dir creation')
end)

-- The two tests above cached throwaway instances; restore the main one so
-- later manifest files that forget their stub still see a clean real module.
package.loaded['xivgamepad.log'] = log

test('unix-style addon_path constructs forward-slash create_dir paths', function()
  fresh(unix_path)
  log.set_debug(true)
  log.info('unix line')
  assert_eq(1, #windower._created_dirs, 'one dir created')
  assert_eq(unix_data_dir, windower._created_dirs[1], 'unix data dir')
  local lines = file_lines(rel_log_path)
  assert_eq(2, #lines, 'header + one line')
  assert(lines[2]:match('%[info%] unix line$'), 'info line in unix file: ' .. lines[2])
end)

test('created dirs never walk above addon_path', function()
  fresh()
  log.set_debug(true)
  assert(#windower._created_dirs > 0, 'a dir was created')
  local base = win_path:sub(1, -2)
  for _, dir in ipairs(windower._created_dirs) do
    assert_eq(1, dir:find(base, 1, true), 'dir anchored beneath addon_path: ' .. dir)
  end
end)

-- ----

-- Leave the cached module disabled so later manifest files inherit clean state.
log.set_debug(false)

io.write(string.format('test_log: %d passed, %d failed\n', pass, fail))
if fail > 0 then
  error(fail .. ' test(s) failed in test_log.lua')
end
