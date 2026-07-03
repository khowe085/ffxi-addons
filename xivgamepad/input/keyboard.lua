local log = require('xivgamepad.log')

local DIK_LCTRL = 29
local DIK_RCTRL = 157

local by_code          = {}
local callback
local ctrl_keys        = {}
local key_down         = {}
local press_resolution = {}
local raw_callback

local keyboard = {}

local ctrl_down
local resolve_press

-- Public functions (alphabetical)

function keyboard.configure(key_mapping)
  by_code = {}
  for button, entry in pairs(key_mapping or {}) do
    local slot = by_code[entry.code]
    if not slot then
      slot = {}
      by_code[entry.code] = slot
    end
    if entry.ctrl then
      slot.ctrl = button
    else
      slot.bare = button
    end
  end
end

function keyboard.is_ctrl_down()
  return ctrl_down()
end

function keyboard.on_key(dik, pressed)
  if pressed then
    if key_down[dik] then
      return
    end
    key_down[dik] = true
    if dik == DIK_LCTRL or dik == DIK_RCTRL then
      ctrl_keys[dik] = true
      return
    end
    local ctrl = ctrl_down()
    if raw_callback then
      raw_callback(dik, ctrl)
    end
    local button = resolve_press(dik, ctrl)
    if button then
      press_resolution[dik] = button
      log.debug('key %d down -> %s press', dik, button)
      if callback then
        callback(button, true)
      end
    end
  else
    if not key_down[dik] then
      return
    end
    key_down[dik] = nil
    if dik == DIK_LCTRL or dik == DIK_RCTRL then
      ctrl_keys[dik] = nil
      return
    end
    local button = press_resolution[dik]
    press_resolution[dik] = nil
    if button then
      log.debug('key %d up -> %s release', dik, button)
      if callback then
        callback(button, false)
      end
    end
  end
end

function keyboard.reset()
  ctrl_keys        = {}
  key_down         = {}
  press_resolution = {}
end

function keyboard.set_callback(fn)
  callback = fn
end

function keyboard.set_raw_callback(fn)
  raw_callback = fn
end

-- Private functions (alphabetical)

ctrl_down = function()
  return ctrl_keys[DIK_LCTRL] == true or ctrl_keys[DIK_RCTRL] == true
end

resolve_press = function(dik, ctrl)
  local slot = by_code[dik]
  if not slot then
    return nil
  end
  if ctrl and slot.ctrl then
    return slot.ctrl
  end
  return slot.bare
end

return keyboard
