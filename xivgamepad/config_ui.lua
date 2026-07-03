-- Config GUI (contract: .planning/xivgamepad-contracts.md, "Frontend module
-- contracts" / config_ui). Built on lib/settings config_gui; the four frozen
-- tabs (Sets / Display / Keys / Gestures) are rendered as clickable custom
-- tabs: each row may carry an on_click(rel_x) that delegates to a named,
-- testable mutator below. Every mutation flows through opts.on_change(key,
-- value) — staging via lib/settings stage_set stays in main, so this module
-- never writes the staged table directly. Sub-tables (sets / display /
-- gestures) are deep-copied, edited on the copy, and handed whole to
-- on_change under their top-level settings key.
--
-- Click model: rows expose click zones (pixel columns derived from the same
-- conservative 9px glyph estimate config_gui uses) that cycle or toggle the
-- value they cover; the tab header row documents each tab's zones. The Keys
-- tab's first row is the Capture / Re-learn control invoking the injected
-- launch_wizard. The Gestures tab renders two rows per gesture — [x] remove,
-- id, and cycle zones for type/button on the first row; context/action
-- cycles and - / + timing tuning on the second — plus a trailing
-- "[+ add gesture]" row appending a cyclable template entry. Custom tabs
-- taller than the body scroll with the mouse wheel (config_gui forwards
-- wheel events into the tab body).

local config_gui = require('lib.settings.config_gui')
local action_lib = require('action')
local log = require('log')

local config_ui = {}

local action_name_cache = nil
local body_el = nil
local gui = nil
local host = nil
local last_vp = nil
local scroll = {}

local BODY_W = 460
local BODY_H = 400
local ROW_H = 18
local VISIBLE_ROWS = math.floor(BODY_H / ROW_H)
local CLICK_SPLIT = math.floor(BODY_W / 2)
local TIMING_STEP = 0.05
local TIMING_MIN = 0.05
local TRANSPARENCY_STEP = 10

-- Gesture-row click zones (pixel columns; 9px per monospace glyph, matching
-- config_gui's conservative estimate). Line A: '[x] <id> type=<t> btn=<b>';
-- line B: '    ctx=<c> act=<a> - <param>=<v> +'.
local GZ_REMOVE_END = 4 * 9
local GZ_ID_END = 19 * 9
local GZ_TYPE_END = 40 * 9
local GZ_INDENT_END = 4 * 9
local GZ_CTX_END = 21 * 9
local GZ_ACT_END = 44 * 9
local GZ_TIMING_SPLIT = 428

local BUTTON_ORDER = {
  'LT', 'RT', 'LB', 'RB', 'BACK', 'START', 'A', 'B', 'X', 'Y',
  'DPAD_UP', 'DPAD_RIGHT', 'DPAD_DOWN', 'DPAD_LEFT',
  'L4', 'L5', 'R4', 'R5',
  'TRACKPAD_1', 'TRACKPAD_2', 'TRACKPAD_3', 'TRACKPAD_4',
  'TRACKPAD_5', 'TRACKPAD_6', 'TRACKPAD_7', 'TRACKPAD_8',
}

local CONTEXTS = { 'bare', 'trigger_held', 'rb_held', 'lb_held' }

local DISPLAY_MODES = { 'wxhb_l', 'wxhb_r', 'expand_lt_rt', 'expand_rt_lt' }

local GESTURE_TYPES = { 'button', 'tap', 'hold', 'double_tap', 'hold_then_hold', 'hold_then_press' }

local PRIMARY_TIMING = {
  tap             = 'max_hold',
  hold            = 'min_hold',
  double_tap      = 'max_gap',
  hold_then_hold  = 'min_hold_first',
  hold_then_press = 'min_anchor_hold',
}

local TIMING_DEFAULTS = {
  max_hold        = 0.25,
  min_hold        = 0.12,
  max_gap         = 0.33,
  min_hold_first  = 0.12,
  min_anchor_hold = 0.12,
}

local action_names
local change
local copy_of
local display_rows
local find_gesture
local gesture_rows
local keys_rows
local make_tab
local next_in_list
local refresh_tabs
local sets_rows
local staged

-- Public functions (alphabetical; _-prefixed are test-only accessors)

function config_ui._body_text_for_test()
  return body_el and body_el:text()
end

function config_ui._gui_for_test()
  return gui
end

function config_ui.add_gesture(entry)
  local s = staged()
  if s == nil or type(entry) ~= 'table' or entry.id == nil then return end
  if find_gesture(s.gestures or {}, entry.id) ~= nil then
    log.debug('add_gesture rejected duplicate id %s', tostring(entry.id))
    return
  end
  local gestures = copy_of(s.gestures or {})
  gestures[#gestures + 1] = copy_of(entry)
  change('gestures', gestures)
end

function config_ui.add_gesture_template()
  local s = staged()
  if s == nil then return end
  local gestures = s.gestures or {}
  local n = 0
  local id
  repeat
    n = n + 1
    id = 'custom_' .. n
  until find_gesture(gestures, id) == nil
  config_ui.add_gesture({ id = id, type = 'tap', button = 'A', context = 'bare',
    action = 'jump', params = { max_hold = TIMING_DEFAULTS.max_hold } })
end

function config_ui.adjust_gesture_timing(id, param, delta)
  local s = staged()
  if s == nil then return end
  local gestures = copy_of(s.gestures or {})
  local entry = find_gesture(gestures, id)
  if entry == nil then return end
  entry.params = entry.params or {}
  local value = (entry.params[param] or 0) + delta
  if value < TIMING_MIN then value = TIMING_MIN end
  entry.params[param] = math.floor(value * 100 + 0.5) / 100
  change('gestures', gestures)
end

function config_ui.adjust_transparency(which, delta)
  local s = staged()
  if s == nil then return end
  local key = 'transparency_' .. which
  local value = (s[key] or 0) + delta
  if value < 0 then value = 0 end
  if value > 100 then value = 100 end
  change(key, value)
end

function config_ui.build_tabs(s)
  s = s or {}
  return {
    make_tab('Sets', sets_rows(s)),
    make_tab('Display', display_rows(s)),
    make_tab('Keys', keys_rows(s)),
    make_tab('Gestures', gesture_rows(s)),
  }
end

function config_ui.close()
  if gui == nil then return end
  gui:set_draggable(false)
  gui:hide()
end

function config_ui.cycle_display_set(mode_key)
  local s = staged()
  local display = s and s.display
  if display == nil or display[mode_key] == nil then return end
  local copy = copy_of(display)
  copy[mode_key].set = (copy[mode_key].set or 0) % 8 + 1
  change('display', copy)
end

function config_ui.cycle_gesture_field(id, field)
  local s = staged()
  if s == nil then return end
  local gestures = copy_of(s.gestures or {})
  local entry = find_gesture(gestures, id)
  if entry == nil then return end
  if field == 'button' then
    entry.button = next_in_list(BUTTON_ORDER, entry.button)
  elseif field == 'context' then
    entry.context = next_in_list(CONTEXTS, entry.context)
  elseif field == 'type' then
    entry.type = next_in_list(GESTURE_TYPES, entry.type)
    local param = PRIMARY_TIMING[entry.type]
    if param then
      entry.params = entry.params or {}
      if entry.params[param] == nil then
        entry.params[param] = TIMING_DEFAULTS[param]
      end
    end
  elseif field == 'action' then
    -- Cycling walks the registered action list; an entry holding a raw
    -- windower command (the escape hatch) starts over at the first action.
    entry.action = next_in_list(action_names(), entry.action)
  else
    return
  end
  change('gestures', gestures)
end

function config_ui.cycle_set_source(index)
  local s = staged()
  if s == nil or s.sets == nil or s.sets[index] == nil then return end
  local sets = copy_of(s.sets)
  sets[index].source = sets[index].source == 'job' and 'shared' or 'job'
  change('sets', sets)
end

function config_ui.destroy()
  if gui then
    gui:destroy()
    gui = nil
  end
  if body_el then
    body_el:destroy()
    body_el = nil
  end
  scroll = {}
  last_vp = nil
end

function config_ui.init(opts)
  host = opts or {}
  if gui == nil and host.texts then
    gui = config_gui.new({
      texts      = host.texts,
      images     = host.images,
      title      = 'XIVGamepad',
      on_save    = function() if host.on_save then host.on_save() end end,
      on_discard = function() if host.on_discard then host.on_discard() end end,
      on_move    = function(x, y) config_ui.stage_window_pos(x, y) end,
      pos        = { x = 100, y = 100 },
      size       = { width = BODY_W, height = BODY_H },
    })
  end
  if body_el == nil and host.texts then
    body_el = host.texts.new('', {
      pos   = { x = 0, y = 0 },
      text  = { font = 'Consolas', size = 11 },
      flags = { draggable = false },
    })
    body_el:draggable(false)
    body_el:hide()
  end
end

function config_ui.is_open()
  return gui ~= nil and gui:is_open()
end

function config_ui.on_mouse(mtype, x, y, delta)
  if gui == nil then return false end
  return gui:handle_mouse(mtype, x, y, delta)
end

function config_ui.open(staged_settings)
  if gui == nil then return end
  if gui:is_open() then return end
  staged_settings = staged_settings or {}
  gui:set_pos(staged_settings.config_x or 100, staged_settings.config_y or 100)
  gui:set_draggable(true)
  gui:show(config_ui.build_tabs(staged_settings))
  log.debug('config window opened')
end

function config_ui.remove_gesture(id)
  local s = staged()
  if s == nil then return end
  local gestures = {}
  local removed = false
  for _, entry in ipairs(s.gestures or {}) do
    if entry.id == id then
      removed = true
    else
      gestures[#gestures + 1] = copy_of(entry)
    end
  end
  if not removed then return end
  change('gestures', gestures)
end

function config_ui.request_capture()
  if host and host.launch_wizard then
    host.launch_wizard()
  end
end

function config_ui.set_set_name(index, name)
  local s = staged()
  if s == nil or s.sets == nil or s.sets[index] == nil then return end
  local sets = copy_of(s.sets)
  sets[index].name = tostring(name)
  change('sets', sets)
end

function config_ui.stage_window_pos(x, y)
  if host == nil or host.on_change == nil then return end
  host.on_change('config_x', x)
  host.on_change('config_y', y)
end

function config_ui.toggle_display_half(mode_key)
  local s = staged()
  local display = s and s.display
  if display == nil or display[mode_key] == nil then return end
  local copy = copy_of(display)
  copy[mode_key].half = copy[mode_key].half == 'left' and 'right' or 'left'
  change('display', copy)
end

function config_ui.toggle_hide_empty_slots()
  local s = staged()
  if s == nil then return end
  change('hide_empty_slots', not s.hide_empty_slots)
end

function config_ui.toggle_skip_cycle(index)
  local s = staged()
  if s == nil or s.sets == nil or s.sets[index] == nil then return end
  local sets = copy_of(s.sets)
  sets[index].skip_cycle = not sets[index].skip_cycle
  change('sets', sets)
end

function config_ui.update_gesture(id, field, value)
  local s = staged()
  if s == nil then return end
  local gestures = copy_of(s.gestures or {})
  local entry = find_gesture(gestures, id)
  if entry == nil then return end
  entry[field] = value
  change('gestures', gestures)
end

-- Private functions (alphabetical)

action_names = function()
  if action_name_cache == nil then
    action_name_cache = {}
    for i, def in ipairs(action_lib.list_actions()) do
      action_name_cache[i] = def.name
    end
  end
  return action_name_cache
end

change = function(key, value)
  if host and host.on_change then
    host.on_change(key, value)
  end
  refresh_tabs()
end

copy_of = function(value)
  if type(value) ~= 'table' then return value end
  local copy = {}
  for k, v in pairs(value) do
    copy[k] = copy_of(v)
  end
  return copy
end

display_rows = function(s)
  local rows = { { text = 'Display  (click left: cycle set / value-, right: half / value+)' } }
  local display = s.display or {}
  for _, key in ipairs(DISPLAY_MODES) do
    local assign = display[key] or {}
    local mode_key = key
    rows[#rows + 1] = {
      text = string.format('%-13s set %s  half %s',
        key, tostring(assign.set or '?'), tostring(assign.half or '?')),
      on_click = function(rel_x)
        if rel_x < CLICK_SPLIT then
          config_ui.cycle_display_set(mode_key)
        else
          config_ui.toggle_display_half(mode_key)
        end
      end,
    }
  end
  rows[#rows + 1] = {
    text = 'hide_empty_slots: ' .. tostring(s.hide_empty_slots or false),
    on_click = function() config_ui.toggle_hide_empty_slots() end,
  }
  for _, which in ipairs({ 'standard', 'active', 'inactive' }) do
    local w = which
    rows[#rows + 1] = {
      text = string.format('transparency %-9s %s',
        which, tostring(s['transparency_' .. which] or 0)),
      on_click = function(rel_x)
        config_ui.adjust_transparency(w, rel_x < CLICK_SPLIT and -TRANSPARENCY_STEP or TRANSPARENCY_STEP)
      end,
    }
  end
  return rows
end

find_gesture = function(gestures, id)
  for _, entry in ipairs(gestures) do
    if entry.id == id then
      return entry
    end
  end
  return nil
end

gesture_rows = function(s)
  local rows = { { text = 'Gestures  ([x] remove; click type/btn/ctx/act to cycle; - + tune)' } }
  for _, gesture in ipairs(s.gestures or {}) do
    local id = gesture.id
    local param = PRIMARY_TIMING[gesture.type]
    rows[#rows + 1] = {
      text = string.format('[x] %-14s type=%-15s btn=%s',
        tostring(id), tostring(gesture.type), tostring(gesture.button)),
      on_click = function(rel_x)
        if rel_x < GZ_REMOVE_END then
          config_ui.remove_gesture(id)
        elseif rel_x < GZ_ID_END then
          return
        elseif rel_x < GZ_TYPE_END then
          config_ui.cycle_gesture_field(id, 'type')
        else
          config_ui.cycle_gesture_field(id, 'button')
        end
      end,
    }
    local timing = ''
    if param then
      local value = gesture.params and gesture.params[param]
      timing = string.format('- %s=%s +', param, tostring(value or '?'))
    end
    rows[#rows + 1] = {
      text = string.format('    ctx=%-12s act=%-18s %s',
        tostring(gesture.context or 'bare'), tostring(gesture.action), timing),
      on_click = function(rel_x)
        if rel_x < GZ_INDENT_END then
          return
        elseif rel_x < GZ_CTX_END then
          config_ui.cycle_gesture_field(id, 'context')
        elseif rel_x < GZ_ACT_END then
          config_ui.cycle_gesture_field(id, 'action')
        elseif param then
          config_ui.adjust_gesture_timing(id, param,
            rel_x < GZ_TIMING_SPLIT and -TIMING_STEP or TIMING_STEP)
        end
      end,
    }
  end
  rows[#rows + 1] = {
    text = '[+ add gesture]',
    on_click = function() config_ui.add_gesture_template() end,
  }
  return rows
end

keys_rows = function(s)
  local rows = { {
    text = '[ Capture / Re-learn key mapping ]',
    on_click = function() config_ui.request_capture() end,
  } }
  local mapping = s.key_mapping or {}
  for _, button in ipairs(BUTTON_ORDER) do
    local entry = mapping[button]
    if entry then
      rows[#rows + 1] = {
        text = string.format('%-12s key %s%s',
          button, tostring(entry.code), entry.ctrl and ' +Ctrl' or ''),
      }
    else
      rows[#rows + 1] = { text = string.format('%-12s (unmapped)', button) }
    end
  end
  return rows
end

make_tab = function(title, rows)
  local tab = { title = title, rows = rows }
  local max_off = math.max(0, #rows - VISIBLE_ROWS)
  local function offset()
    local off = scroll[title] or 0
    if off < 0 then off = 0 end
    if off > max_off then off = max_off end
    scroll[title] = off
    return off
  end
  tab.render = function(vp)
    if body_el == nil then return end
    last_vp = vp
    local off = offset()
    local lines = {}
    for i = off + 1, math.min(#rows, off + VISIBLE_ROWS) do
      lines[#lines + 1] = rows[i].text
    end
    body_el:pos(vp.x + 4, vp.y)
    body_el:text(table.concat(lines, '\n'))
    body_el:show()
  end
  tab.hide = function()
    if body_el then body_el:hide() end
  end
  tab.on_mouse = function(rel_x, rel_y, mtype, delta)
    if mtype == 10 then
      -- Wheel matches the helper's text-tab direction: positive delta
      -- scrolls up.
      scroll[title] = offset() + ((delta or 0) > 0 and -1 or 1)
      if last_vp then tab.render(last_vp) end
      return
    end
    if mtype ~= 1 then return end
    local row = rows[offset() + math.floor(rel_y / ROW_H) + 1]
    if row and row.on_click then
      row.on_click(rel_x)
    end
  end
  return tab
end

next_in_list = function(list, current)
  for i = 1, #list do
    if list[i] == current then
      return list[i % #list + 1]
    end
  end
  return list[1]
end

refresh_tabs = function()
  if gui and gui:is_open() then
    gui:set_tabs(config_ui.build_tabs(staged() or {}))
  end
end

sets_rows = function(s)
  local rows = { { text = 'Sets  (click left: source, right: skip cycle)' } }
  local sets = s.sets or {}
  for i = 1, 8 do
    local entry = sets[i] or {}
    local idx = i
    rows[#rows + 1] = {
      text = string.format('%d. %-18s %-6s %s',
        i, tostring(entry.name or ''), tostring(entry.source or 'job'),
        entry.skip_cycle and '[skip]' or '[cycle]'),
      on_click = function(rel_x)
        if rel_x < CLICK_SPLIT then
          config_ui.cycle_set_source(idx)
        else
          config_ui.toggle_skip_cycle(idx)
        end
      end,
    }
  end
  return rows
end

staged = function()
  if host and host.get_staged then
    return host.get_staged()
  end
  return nil
end

return config_ui
