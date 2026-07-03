-- Gamepad Tester diagnostic overlay (contract: .planning/xivgamepad-contracts.md,
-- "Frontend module contracts" / tester). Plain texts overlay — deliberately not
-- config_gui — showing a live virtual-button state grid and a bounded scrolling
-- gesture log. Main routes gestures here instead of to actions while test_mode
-- is set; this module only displays what it is fed.

local log = require('xivgamepad.log')

local tester = {}

local state = nil

local MAX_LOG = 10
local GRID_X = 100
local GRID_Y = 120
local LOG_GAP = 8
local ROW_H = 18

local BUTTONS = {
  'LT', 'RT', 'LB', 'RB', 'A', 'B', 'X', 'Y',
  'DPAD_UP', 'DPAD_RIGHT', 'DPAD_DOWN', 'DPAD_LEFT',
  'BACK', 'START', 'L4', 'L5', 'R4', 'R5',
  'TRACKPAD_1', 'TRACKPAD_2', 'TRACKPAD_3', 'TRACKPAD_4',
  'TRACKPAD_5', 'TRACKPAD_6', 'TRACKPAD_7', 'TRACKPAD_8',
}

local format_gesture
local render

-- Public functions (alphabetical; _-prefixed are test-only accessors)

function tester._grid_text_for_test()
  return state and state.grid_el and state.grid_el:text()
end

function tester._log_lines_for_test()
  if state == nil then return nil end
  local copy = {}
  for i, line in ipairs(state.log) do
    copy[i] = line
  end
  return copy
end

function tester._log_text_for_test()
  return state and state.log_el and state.log_el:text()
end

function tester.close()
  if state == nil then return end
  state.open = false
  state.grid_el:hide()
  state.log_el:hide()
end

function tester.destroy()
  if state == nil then return end
  state.grid_el:destroy()
  state.log_el:destroy()
  state = nil
end

function tester.init(opts)
  opts = opts or {}
  if state == nil then
    local texts_lib = opts.texts
    local grid_h = (math.ceil(#BUTTONS / 2) + 1) * ROW_H
    state = {
      open    = false,
      pressed = {},
      log     = {},
      grid_el = texts_lib.new('', {
        pos   = { x = GRID_X, y = GRID_Y },
        text  = { font = 'Consolas', size = 11 },
        flags = { draggable = false },
      }),
      log_el = texts_lib.new('', {
        pos   = { x = GRID_X, y = GRID_Y + grid_h + LOG_GAP },
        text  = { font = 'Consolas', size = 11 },
        flags = { draggable = false },
      }),
    }
    state.grid_el:draggable(false)
    state.log_el:draggable(false)
  end
end

function tester.is_open()
  return state ~= nil and state.open
end

function tester.on_button_event(name, pressed)
  if state == nil then return end
  state.pressed[name] = pressed and true or false
  if state.open then
    render()
  end
end

function tester.on_gesture(id, params)
  if state == nil then return end
  state.log[#state.log + 1] = format_gesture(id, params)
  while #state.log > MAX_LOG do
    table.remove(state.log, 1)
  end
  log.debug('tester logged gesture %s', tostring(id))
  if state.open then
    render()
  end
end

function tester.open()
  if state == nil then return end
  state.open = true
  render()
  state.grid_el:show()
  state.log_el:show()
end

-- Private functions (alphabetical)

format_gesture = function(id, params)
  local keys = {}
  for key in pairs(params or {}) do
    keys[#keys + 1] = tostring(key)
  end
  table.sort(keys)
  if #keys == 0 then
    return tostring(id)
  end
  local parts = {}
  for i, key in ipairs(keys) do
    parts[i] = key .. '=' .. tostring(params[key])
  end
  return tostring(id) .. ' (' .. table.concat(parts, ', ') .. ')'
end

render = function()
  local lines = { 'Gamepad Tester' }
  for i = 1, #BUTTONS, 2 do
    local a = BUTTONS[i]
    local b = BUTTONS[i + 1]
    local line = (state.pressed[a] and '[X]' or '[ ]') .. ' ' .. string.format('%-12s', a)
    if b then
      line = line .. ' ' .. (state.pressed[b] and '[X]' or '[ ]') .. ' ' .. b
    end
    lines[#lines + 1] = line
  end
  state.grid_el:text(table.concat(lines, '\n'))
  state.log_el:text('Gestures:\n' .. table.concat(state.log, '\n'))
end

return tester
