-- Key-Capture Wizard / Learn Mode (contract: .planning/xivgamepad-contracts.md,
-- "Frontend module contracts" / wizard). Walks the frozen capture order,
-- recording the raw DIK code Steam Input emits for each virtual button into a
-- staging copy of current_mapping. Finishing hands the completed mapping to
-- on_finish (main commits it); cancelling calls on_cancel and leaves the prior
-- mapping untouched. Prompt/status render on a plain texts overlay (not
-- config_gui) so the wizard works before any mapping exists.
--
-- on_raw_key(dik, ctrl_down, pressed) — the third argument is a
-- contract-consistent addition: the pinned two-argument call (what
-- keyboard.set_raw_callback delivers — key-DOWN edges only) is treated as
-- pressed = true; a caller that also forwards releases passes pressed = false
-- so held-trigger tracking for the d-pad steps can clear. With down-only
-- feeding, a captured trigger code marks its anchor held and it stays held —
-- physically safe because Steam only emits d-pad chord keys while LT/RT/RB is
-- actually down.
--
-- Collision rule: a captured (code, ctrl) pair owned by any OTHER button —
-- captured earlier this session or remaining in the staged mapping — is
-- rejected, naming the owning button. Re-pressing the current button's own
-- prior key simply re-confirms it.

local log = require('log')

local wizard = {}

local state = nil
local prompt_el = nil

local DIK_LCTRL = 29
local DIK_RCTRL = 157

local REQUIRED = {
  'LT', 'RT', 'LB', 'RB', 'BACK', 'START', 'A', 'B', 'X', 'Y',
  'DPAD_UP', 'DPAD_RIGHT', 'DPAD_DOWN', 'DPAD_LEFT',
}

local OPTIONAL = {
  'L4', 'L5', 'R4', 'R5',
  'TRACKPAD_1', 'TRACKPAD_2', 'TRACKPAD_3', 'TRACKPAD_4',
  'TRACKPAD_5', 'TRACKPAD_6', 'TRACKPAD_7', 'TRACKPAD_8',
}

local ORDER = {}
for _, name in ipairs(REQUIRED) do ORDER[#ORDER + 1] = name end
for _, name in ipairs(OPTIONAL) do ORDER[#ORDER + 1] = name end

-- Steam's d-pad chords fire while LT, RT, or RB is held, so any of the three
-- anchors a d-pad capture.
local TRIGGER_ANCHORS = { 'LT', 'RT', 'RB' }

local advance
local any_trigger_held
local copy_entry
local copy_mapping
local finish
local find_owner
local hide_prompt
local is_dpad
local render_prompt
local set_status
local trigger_owner

-- Public functions (alphabetical; _-prefixed are test-only accessors)

function wizard._current_button_for_test()
  return state and ORDER[state.step]
end

function wizard._prompt_text_for_test()
  return prompt_el and prompt_el:text()
end

function wizard._staged_for_test()
  return state and state.staged
end

function wizard._status_for_test()
  return state and state.status
end

function wizard.back()
  if state == nil or state.step <= 1 then return end
  state.step = state.step - 1
  local button = ORDER[state.step]
  state.session[button] = nil
  state.held[button] = nil
  if state.original[button] then
    state.staged[button] = copy_entry(state.original[button])
  else
    state.staged[button] = nil
  end
  state.status = ''
  log.debug('wizard backed up to %s', button)
  render_prompt()
end

function wizard.cancel()
  if state == nil then return end
  local on_cancel = state.on_cancel
  state = nil
  hide_prompt()
  log.debug('wizard cancelled')
  if on_cancel then on_cancel() end
end

function wizard.is_active()
  return state ~= nil
end

function wizard.on_raw_key(dik, ctrl_down, pressed)
  if state == nil then return end
  if dik == DIK_LCTRL or dik == DIK_RCTRL then return end
  if pressed == nil then pressed = true end
  local ctrl = ctrl_down and true or false
  local anchor = trigger_owner(dik, ctrl)
  if anchor then
    state.held[anchor] = pressed or nil
  end
  if not pressed then return end
  local button = ORDER[state.step]
  if is_dpad(button) then
    if anchor then
      set_status(anchor .. ' held - now press ' .. button)
      return
    end
    if not any_trigger_held() then
      set_status('Hold LT, RT, or RB, then press ' .. button)
      return
    end
  end
  local owner = find_owner(dik, ctrl, button)
  if owner then
    set_status('That key is already bound to ' .. owner
      .. ' - press a different key for ' .. button)
    return
  end
  local entry = { code = dik }
  if ctrl then entry.ctrl = true end
  state.staged[button] = entry
  state.session[button] = true
  log.debug('wizard captured %s -> code %d%s', button, dik, ctrl and ' +ctrl' or '')
  advance()
end

function wizard.skip()
  if state == nil then return end
  local button = ORDER[state.step]
  if state.step <= #REQUIRED then
    set_status(button .. ' is required and cannot be skipped')
    return
  end
  state.session[button] = nil
  log.debug('wizard skipped %s', button)
  advance()
end

function wizard.start(opts)
  opts = opts or {}
  state = {
    staged    = copy_mapping(opts.current_mapping),
    original  = copy_mapping(opts.current_mapping),
    session   = {},
    held      = {},
    step      = 1,
    status    = '',
    on_finish = opts.on_finish,
    on_cancel = opts.on_cancel,
  }
  if prompt_el == nil and opts.texts then
    prompt_el = opts.texts.new('', {
      pos   = { x = 200, y = 200 },
      text  = { font = 'Consolas', size = 12 },
      flags = { draggable = false },
    })
    prompt_el:draggable(false)
  end
  log.debug('wizard started')
  render_prompt()
end

-- Private functions (alphabetical)

advance = function()
  state.status = ''
  state.step = state.step + 1
  if state.step > #ORDER then
    finish()
    return
  end
  render_prompt()
end

any_trigger_held = function()
  for _, name in ipairs(TRIGGER_ANCHORS) do
    if state.held[name] then
      return true
    end
  end
  return false
end

copy_entry = function(entry)
  local copy = { code = entry.code }
  if entry.ctrl then copy.ctrl = true end
  return copy
end

copy_mapping = function(mapping)
  local copy = {}
  for button, entry in pairs(mapping or {}) do
    copy[button] = copy_entry(entry)
  end
  return copy
end

finish = function()
  local staged = state.staged
  local on_finish = state.on_finish
  state = nil
  hide_prompt()
  log.debug('wizard finished')
  if on_finish then on_finish(staged) end
end

find_owner = function(code, ctrl, current)
  for _, name in ipairs(ORDER) do
    if name ~= current then
      local entry = state.staged[name]
      if entry and entry.code == code and (entry.ctrl == true) == ctrl then
        return name
      end
    end
  end
  return nil
end

hide_prompt = function()
  if prompt_el then
    prompt_el:hide()
  end
end

is_dpad = function(button)
  return button ~= nil and button:find('^DPAD_') ~= nil
end

render_prompt = function()
  if prompt_el == nil then return end
  local button = ORDER[state.step]
  local lines = {
    'Key-Capture Wizard',
    string.format('Step %d/%d: press %s', state.step, #ORDER, button),
  }
  if is_dpad(button) then
    lines[#lines + 1] = 'Hold LT, RT, or RB, then press ' .. button
  end
  if state.step > #REQUIRED then
    lines[#lines + 1] = 'Optional: skip keeps the current key; back re-captures'
  end
  if state.status ~= '' then
    lines[#lines + 1] = state.status
  end
  prompt_el:text(table.concat(lines, '\n'))
  prompt_el:show()
end

set_status = function(message)
  state.status = message
  render_prompt()
end

trigger_owner = function(code, ctrl)
  for _, name in ipairs(TRIGGER_ANCHORS) do
    if state.session[name] then
      local entry = state.staged[name]
      if entry and entry.code == code and (entry.ctrl == true) == ctrl then
        return name
      end
    end
  end
  return nil
end

return wizard
