-- Run all xivgamepad tests.
-- Invoke from the repository root: lua tests/xivgamepad/run_tests.lua
--
-- Fixed manifest (no filesystem discovery — io.popen/os.execute are forbidden):
-- parallel implementation tasks add test files without ever editing this runner.
-- Files not yet written are warn-skipped.

local dir = (arg and arg[0] or 'tests/xivgamepad/run_tests.lua'):match('^(.*[/\\])') or './'

local manifest = {
  'test_input.lua',
  'test_gamepad.lua',
  'test_action.lua',
  'test_storage.lua',
  'test_log.lua',
  'test_lifecycle.lua',
  'test_commands.lua',
  'test_hud.lua',
  'test_config_ui.lua',
  'test_tester.lua',
  'test_wizard.lua',
  'test_binder.lua',
}

-- Plain io.open probe: harness-only real-disk existence check, so the mock's
-- in-memory files API can never interfere. (io is allowed in test harness code
-- only, never in addon code.)
local function file_exists(path)
  local fh = io.open(path, 'r')
  if fh then
    fh:close()
    return true
  end
  return false
end

local function run(file)
  io.write('--- ' .. file:match('[^/\\]+$') .. ' ---\n')
  local ok, err = pcall(dofile, file)
  if not ok then
    io.write('ERROR: ' .. tostring(err) .. '\n')
    os.exit(1)
  end
end

dofile(dir .. 'mock_windower.lua')

local ran = 0
local skipped = 0
for _, name in ipairs(manifest) do
  if file_exists(dir .. name) then
    run(dir .. name)
    ran = ran + 1
  else
    io.write('SKIP (missing): ' .. name .. '\n')
    skipped = skipped + 1
  end
end

io.write('\n' .. ran .. ' test file(s) passed, ' .. skipped .. ' skipped.\n')
io.write('All tests passed.\n')
