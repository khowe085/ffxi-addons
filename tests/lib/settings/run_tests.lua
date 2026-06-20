-- Run all lib/settings tests.
-- Invoke from the repository root: lua tests/lib/settings/run_tests.lua

local dir = (arg and arg[0] or 'tests/lib/settings/run_tests.lua'):match('^(.*[/\\])') or './'

local function run(file)
  io.write('--- ' .. file:match('[^/\\]+$') .. ' ---\n')
  local ok, err = pcall(dofile, file)
  if not ok then
    io.write('ERROR: ' .. tostring(err) .. '\n')
    os.exit(1)
  end
end

dofile(dir .. 'mock_windower.lua')
run(dir .. 'test_load.lua')
run(dir .. 'test_staging.lua')
run(dir .. 'test_login.lua')

io.write('\nAll tests passed.\n')
