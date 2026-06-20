-- Run all echo tests.
-- Invoke from the repository root: lua tests/echo/run_tests.lua

local dir = (arg and arg[0] or 'tests/echo/run_tests.lua'):match('^(.*[/\\])') or './'

local function run(file)
  io.write('--- ' .. file:match('[^/\\]+$') .. ' ---\n')
  local ok, err = pcall(dofile, file)
  if not ok then
    io.write('ERROR: ' .. tostring(err) .. '\n')
    os.exit(1)
  end
end

dofile(dir .. 'mock_windower.lua')
run(dir .. 'test_settings.lua')
run(dir .. 'test_commands.lua')
run(dir .. 'test_lifecycle.lua')

io.write('\nAll tests passed.\n')
