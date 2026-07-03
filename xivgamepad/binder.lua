-- Binder: in-game slot-binding menu (contract: .planning/xivgamepad-contracts.md,
-- "Frontend module contracts" / binder). Main opens and closes it via toggle()
-- (the BACK-while-XHB gesture) and routes button events here while its
-- binder_mode flag is set; suppression of normal dispatch is main's job. The
-- binder never touches the gamepad/keyboard modules.
--
-- init(opts) surface -- main (Task 2a) implements and injects all of it:
--   action           the xivgamepad.action module (or equivalent iface). Used
--                    only to enumerate overlay types for the overlay menu:
--                    action.list_overlay_types() -> sorted name array, and
--                    action.get_overlay_type(name) -> def, whose
--                    def.is_available(player_state) filters the menu. Types
--                    registered at runtime appear automatically.
--   get_set          function(position) -> working-set table
--                    { slots = { [1..16] = binding or nil } } for that working
--                    position. The binder mutates the returned table and hands
--                    it back to save_set; main owns which file (shared/job)
--                    backs each position.
--   save_set         function(position, set_table) -> persist that working set.
--   get_player_state function() -> player_state (contract schema).
--   texts, images    the Windower texts/images libraries (UI deps).
--   on_close         optional function() called after the binder closes, by any
--                    path (toggle, BACK+trigger, close(), re-init) -- main
--                    clears binder_mode here.
--   ct_presets       optional array of { label = <string>, command = <string> }
--                    listed by the ct (raw command) binding type. A controller
--                    cannot type free text, so ct bindings are chosen from
--                    these presets; defaults to a small built-in list.
--
-- toggle(ctx) -- ctx: { active_set, display_mode, mode }. display_mode 'xhb_r'
-- targets the right half (slots 9..16) and assumes RT is the held trigger at
-- open; any other display_mode targets the left half (slots 1..8) and assumes
-- LT (open_binder only dispatches while XHB-L/R is active, and the open
-- gesture guarantees a trigger is held). Navigation while a trigger is held:
-- d-pad moves the selection (up/left = previous, down/right = next, clamped),
-- A confirms, B backs up one level, BACK closes. While no trigger is held
-- navigation pauses: every non-trigger button is ignored, the binder stays
-- open, and the status line shows PAUSED. Remove and Swap write immediately;
-- bind/Replace/Overlay flows write on the final Confirm (Replace drops the
-- base and all overlays by writing a fresh binding); Reorder grabs an overlay
-- with A, moves it with the d-pad, commits on the next A, and B while grabbed
-- discards the working order. The subjob overlay type captures the player's
-- current subjob as its condition. Overlay flows additionally offer the noop
-- binding type (blank the base while the condition holds), which confirms
-- directly with no action or target step.

local log = require('xivgamepad.log')
local res = require('resources')

local action_iface     = nil
local ct_presets       = nil
local ctx              = nil
local get_player_state = nil
local get_set          = nil
local half_offset      = 0
local held             = {}
local menu_stack       = {}
local on_close_cb      = nil
local open             = false
local pending          = nil
local save_set         = nil
local ui               = nil

local binding_types = {
  { code = 'ma',    label = 'Magic' },
  { code = 'ja',    label = 'Job Ability' },
  { code = 'ws',    label = 'Weapon Skill' },
  { code = 'a',     label = 'Attack' },
  { code = 'ra',    label = 'Ranged Attack' },
  { code = 'pet',   label = 'Pet Command' },
  { code = 'item',  label = 'Item' },
  { code = 'mount', label = 'Mount' },
  { code = 'ta',    label = 'Switch Target' },
  { code = 'map',   label = 'View Map' },
  { code = 'ct',    label = 'Raw Command' },
  { code = 'ex',    label = 'Display Mode' },
}

local default_ct_presets = {
  { label = 'Rest (/heal)',     command = 'input /heal' },
  { label = 'Sit (/sit)',       command = 'input /sit' },
  { label = 'Check (/check)',   command = 'input /check <t>' },
  { label = 'Lock On (/lockon)', command = 'input /lockon' },
}

local display_modes = {
  { label = 'XHB-L',          mode = 'xhb_l' },
  { label = 'XHB-R',          mode = 'xhb_r' },
  { label = 'WXHB-L',         mode = 'wxhb_l' },
  { label = 'WXHB-R',         mode = 'wxhb_r' },
  { label = 'Expanded LT-RT', mode = 'expand_lt_rt' },
  { label = 'Expanded RT-LT', mode = 'expand_rt_lt' },
}

local magic_skills = {
  { label = 'Healing',    skill = 33 },
  { label = 'Enhancing',  skill = 34 },
  { label = 'Enfeebling', skill = 35 },
  { label = 'Elemental',  skill = 36 },
  { label = 'Dark',       skill = 37 },
  { label = 'Ninjutsu',   skill = 39 },
  { label = 'Song',       skill = 40 },
  { label = 'Summoning',  skill = 38 },
  { label = 'Blue',       skill = 43 },
  { label = 'Geomancy',   skill = 44 },
  { label = 'Trust',      trust = true },
}

local overlay_type_labels = {
  subjob         = 'Subjob',
  light_arts     = 'Light Arts',
  addendum_white = 'Addendum: White',
  dark_arts      = 'Dark Arts',
  addendum_black = 'Addendum: Black',
}

local pet_ability_types = {
  PetCommand    = true,
  BloodPactRage = true,
  BloodPactWard = true,
  Monster       = true,
}

local slot_button_labels = {
  'D-Pad Up', 'D-Pad Right', 'D-Pad Down', 'D-Pad Left', 'A', 'B', 'X', 'Y',
}

-- <t>/<me>/<st>/<stnpc>/<bt>: the sensible core of FFXI's target tokens for
-- bound actions (current, self, select-any, select-NPC, battle target).
local targets = {
  { code = 't',     label = 'Current target <t>' },
  { code = 'me',    label = 'Self <me>' },
  { code = 'st',    label = 'Select target <st>' },
  { code = 'stnpc', label = 'Select NPC <stnpc>' },
  { code = 'bt',    label = 'Battle target <bt>' },
}

local trigger_buttons = { LT = true, RT = true }

local binder = {}

local advance_after_action
local advance_after_type
local append_overlay
local back_one_level
local breadcrumb
local build_action_menu
local build_confirm_menu
local build_occupied_menu
local build_overlay_type_menu
local build_reorder_menu
local build_skill_menu
local build_slot_menu
local build_swap_menu
local build_target_menu
local build_type_menu
local commit_pending
local commit_reorder
local confirm_selection
local create_ui
local describe_binding
local half_label
local hide_ui
local is_trigger_held
local list_ct_items
local list_display_modes
local list_items
local list_job_abilities
local list_mounts
local list_spells
local list_weapon_skills
local move_selection
local overlay_entry_label
local overlay_type_available
local overlay_type_label
local pending_summary
local push_menu
local remove_slot
local render
local reorder_move
local reset_to_root
local select_action
local select_overlay_type
local select_skill
local select_slot
local select_slot_op
local select_swap_target
local select_target
local show_ui
local slot_binding
local sort_by_label
local swap_slots
local top_frame
local type_label
local write_overlays
local write_slot

function binder._state()
  local frame = menu_stack[#menu_stack]
  return {
    open       = open,
    paused     = open and not is_trigger_held(),
    active_set = ctx and ctx.active_set or nil,
    half       = open and half_label() or nil,
    menu       = frame and frame.id or nil,
    index      = frame and frame.index or nil,
    items      = frame and frame.items or nil,
    grabbed    = frame and frame.grabbed or false,
    breadcrumb = breadcrumb(),
  }
end

function binder._ui()
  return ui
end

function binder.close()
  if not open then return end
  open = false
  menu_stack = {}
  pending = nil
  held = {}
  hide_ui()
  log.debug('xivgamepad: binder closed')
  if on_close_cb ~= nil then on_close_cb() end
end

function binder.init(opts)
  if type(opts) ~= 'table' then
    error('binder.init requires an opts table', 2)
  end
  local required = { 'action', 'get_set', 'save_set', 'get_player_state', 'texts', 'images' }
  for i = 1, #required do
    if opts[required[i]] == nil then
      error('binder.init requires opts.' .. required[i], 2)
    end
  end
  if type(opts.action.list_overlay_types) ~= 'function'
      or type(opts.action.get_overlay_type) ~= 'function' then
    error('binder.init requires opts.action.list_overlay_types and opts.action.get_overlay_type', 2)
  end
  if open then binder.close() end
  action_iface     = opts.action
  get_set          = opts.get_set
  save_set         = opts.save_set
  get_player_state = opts.get_player_state
  on_close_cb      = opts.on_close
  ct_presets       = opts.ct_presets or default_ct_presets
  create_ui(opts.texts, opts.images)
end

function binder.is_open()
  return open
end

function binder.on_button(name, pressed)
  if not open then return end
  if trigger_buttons[name] then
    held[name] = pressed or nil
    render()
    return
  end
  if not is_trigger_held() then return end
  if not pressed then return end
  if name == 'BACK' then
    binder.close()
  elseif name == 'DPAD_UP' or name == 'DPAD_LEFT' then
    move_selection(-1)
  elseif name == 'DPAD_DOWN' or name == 'DPAD_RIGHT' then
    move_selection(1)
  elseif name == 'A' then
    confirm_selection()
  elseif name == 'B' then
    back_one_level()
  end
end

function binder.toggle(new_ctx)
  if open then
    binder.close()
    return
  end
  if get_set == nil then
    log.error('xivgamepad: binder toggled before init')
    return
  end
  new_ctx = new_ctx or {}
  ctx = {
    active_set   = new_ctx.active_set or 1,
    display_mode = new_ctx.display_mode or 'xhb_l',
    mode         = new_ctx.mode,
  }
  half_offset = ctx.display_mode == 'xhb_r' and 8 or 0
  held = {}
  held[ctx.display_mode == 'xhb_r' and 'RT' or 'LT'] = true
  pending = nil
  open = true
  menu_stack = { build_slot_menu() }
  show_ui()
  render()
  log.debug('xivgamepad: binder opened (set %d, %s half)', ctx.active_set, half_label())
end

advance_after_action = function(code)
  if code == 'mount' or code == 'ct' or code == 'ex' then
    push_menu(build_confirm_menu())
  else
    push_menu(build_target_menu())
  end
end

advance_after_type = function(code)
  pending.type_code = code
  if code == 'ma' then
    push_menu(build_skill_menu())
  elseif code == 'a' or code == 'ra' or code == 'ta' then
    push_menu(build_target_menu())
  elseif code == 'map' or code == 'noop' then
    push_menu(build_confirm_menu())
  else
    push_menu(build_action_menu(code))
  end
end

append_overlay = function(abs_slot, entry)
  local set = get_set(ctx.active_set) or {}
  set.slots = set.slots or {}
  local slot = set.slots[abs_slot]
  if slot == nil then
    log.error('xivgamepad: binder cannot overlay an empty slot %d', abs_slot)
    return
  end
  if type(slot.overlays) ~= 'table' then slot.overlays = {} end
  slot.overlays[#slot.overlays + 1] = entry
  save_set(ctx.active_set, set)
end

back_one_level = function()
  local frame = top_frame()
  if frame == nil then return end
  if frame.id == 'reorder' and frame.grabbed then
    local fresh = build_reorder_menu(frame.slot)
    if #fresh.items > 0 then
      fresh.index = math.min(frame.index, #fresh.items)
    end
    menu_stack[#menu_stack] = fresh
    render()
    return
  end
  if #menu_stack <= 1 then return end
  table.remove(menu_stack)
  if #menu_stack == 1 then pending = nil end
  render()
end

breadcrumb = function()
  local parts = {}
  for i = 1, #menu_stack do
    parts[i] = menu_stack[i].title
  end
  return table.concat(parts, ' > ')
end

build_action_menu = function(code, skill_def)
  local items, title
  if code == 'ma' then
    items = list_spells(skill_def)
    title = skill_def.label
  elseif code == 'ja' then
    items = list_job_abilities(false)
    title = type_label(code)
  elseif code == 'pet' then
    items = list_job_abilities(true)
    title = type_label(code)
  elseif code == 'ws' then
    items = list_weapon_skills()
    title = type_label(code)
  elseif code == 'item' then
    items = list_items()
    title = type_label(code)
  elseif code == 'mount' then
    items = list_mounts()
    title = type_label(code)
  elseif code == 'ct' then
    items = list_ct_items()
    title = type_label(code)
  elseif code == 'ex' then
    items = list_display_modes()
    title = type_label(code)
  else
    items = {}
    title = type_label(code)
  end
  return { id = 'actions', title = title, items = items, index = 1 }
end

build_confirm_menu = function()
  return {
    id    = 'confirm',
    title = pending_summary(),
    items = { { label = 'Confirm' } },
    index = 1,
  }
end

build_occupied_menu = function(rel)
  return {
    id    = 'slot_ops',
    title = 'Slot ' .. rel,
    items = {
      { label = 'Overlay',          op = 'overlay' },
      { label = 'Replace',          op = 'replace' },
      { label = 'Remove',           op = 'remove' },
      { label = 'Swap',             op = 'swap' },
      { label = 'Reorder Overlays', op = 'reorder' },
    },
    index = 1,
  }
end

build_overlay_type_menu = function()
  local items = {}
  local names = action_iface.list_overlay_types()
  for i = 1, #names do
    if overlay_type_available(names[i]) then
      items[#items + 1] = { label = overlay_type_label(names[i]), name = names[i] }
    end
  end
  return { id = 'overlay_types', title = 'Overlay', items = items, index = 1 }
end

build_reorder_menu = function(abs_slot)
  local slot = slot_binding(abs_slot)
  local overlays = {}
  local items = {}
  if slot ~= nil and type(slot.overlays) == 'table' then
    for i = 1, #slot.overlays do
      overlays[i] = slot.overlays[i]
      items[i] = { label = overlay_entry_label(slot.overlays[i]) }
    end
  end
  return {
    id       = 'reorder',
    title    = 'Reorder',
    items    = items,
    index    = 1,
    slot     = abs_slot,
    overlays = overlays,
    grabbed  = false,
  }
end

build_skill_menu = function()
  return { id = 'skills', title = 'Magic', items = magic_skills, index = 1 }
end

build_slot_menu = function()
  local items = {}
  for i = 1, 8 do
    local abs_slot = half_offset + i
    items[i] = { label = slot_button_labels[i] .. ': ' .. describe_binding(slot_binding(abs_slot)) }
  end
  return { id = 'slots', title = 'Slots', items = items, index = 1 }
end

build_swap_menu = function()
  local frame = build_slot_menu()
  frame.id = 'swap'
  frame.title = 'Swap with'
  return frame
end

build_target_menu = function()
  return { id = 'targets', title = 'Target', items = targets, index = 1 }
end

-- Overlay flows additionally offer noop: an overlay that blanks the base
-- binding while its condition holds (per the plan's binding-type table).
build_type_menu = function()
  local items = binding_types
  if pending ~= nil and pending.mode == 'overlay' then
    items = {}
    for i = 1, #binding_types do
      items[i] = binding_types[i]
    end
    items[#items + 1] = { code = 'noop', label = 'Empty (noop)' }
  end
  return { id = 'types', title = 'Type', items = items, index = 1 }
end

commit_pending = function()
  if pending == nil then return end
  local binding = { type = pending.type_code }
  binding.action = pending.action
  binding.target = pending.target
  binding.alias  = pending.alias
  if pending.mode == 'overlay' then
    local entry = {
      overlay_type = pending.overlay_type,
      condition    = pending.condition or {},
    }
    entry.type   = binding.type
    entry.action = binding.action
    entry.target = binding.target
    entry.alias  = binding.alias
    append_overlay(pending.slot, entry)
    log.debug('xivgamepad: binder added %s overlay to slot %d', pending.overlay_type, pending.slot)
  else
    write_slot(pending.slot, binding)
    log.debug('xivgamepad: binder wrote %s binding to slot %d', binding.type, pending.slot)
  end
  reset_to_root(pending.rel)
end

commit_reorder = function(frame)
  write_overlays(frame.slot, frame.overlays)
  log.debug('xivgamepad: binder reordered overlays on slot %d', frame.slot)
end

confirm_selection = function()
  local frame = top_frame()
  if frame == nil or #frame.items == 0 then return end
  local item = frame.items[frame.index]
  if frame.id == 'slots' then
    select_slot(frame.index)
  elseif frame.id == 'slot_ops' then
    select_slot_op(item.op)
  elseif frame.id == 'types' then
    advance_after_type(item.code)
  elseif frame.id == 'skills' then
    select_skill(item)
  elseif frame.id == 'actions' then
    select_action(item)
  elseif frame.id == 'targets' then
    select_target(item.code)
  elseif frame.id == 'overlay_types' then
    select_overlay_type(item.name)
  elseif frame.id == 'swap' then
    select_swap_target(frame.index)
  elseif frame.id == 'confirm' then
    commit_pending()
  elseif frame.id == 'reorder' then
    if frame.grabbed then
      frame.grabbed = false
      commit_reorder(frame)
    else
      frame.grabbed = true
    end
    render()
  end
end

create_ui = function(texts_lib, images_lib)
  if ui ~= nil then return end
  ui = {
    backdrop = images_lib.new({ pos = { x = 180, y = 140 }, size = { width = 420, height = 340 } }),
    title    = texts_lib.new('', { pos = { x = 192, y = 148 } }),
    body     = texts_lib.new('', { pos = { x = 192, y = 200 } }),
    status   = texts_lib.new('', { pos = { x = 192, y = 452 } }),
  }
end

describe_binding = function(binding)
  if binding == nil then return '(empty)' end
  local label = binding.alias or binding.action or type_label(binding.type) or tostring(binding.type)
  if type(binding.overlays) == 'table' and #binding.overlays > 0 then
    label = label .. ' [+' .. #binding.overlays .. ']'
  end
  return label
end

half_label = function()
  return half_offset == 8 and 'right' or 'left'
end

hide_ui = function()
  if ui == nil then return end
  for _, element in pairs(ui) do
    element:hide()
  end
end

is_trigger_held = function()
  return held.LT == true or held.RT == true
end

list_ct_items = function()
  local items = {}
  for i = 1, #ct_presets do
    local preset = ct_presets[i]
    items[i] = { label = preset.label, action = preset.command, alias = preset.label }
  end
  return items
end

list_display_modes = function()
  local items = {}
  for i = 1, #display_modes do
    items[i] = { label = display_modes[i].label, action = display_modes[i].mode }
  end
  return items
end

list_items = function()
  local items = {}
  for _, item in pairs(res.items or {}) do
    if item.category == 'Usable' then
      items[#items + 1] = { label = item.en, action = item.en }
    end
  end
  sort_by_label(items)
  return items
end

list_job_abilities = function(pet)
  local items = {}
  for _, ability in pairs(res.job_abilities or {}) do
    local is_pet = pet_ability_types[ability.type] == true
    if is_pet == pet then
      items[#items + 1] = { label = ability.en, action = ability.en }
    end
  end
  sort_by_label(items)
  return items
end

list_mounts = function()
  local items = {}
  for _, mount in pairs(res.mounts or {}) do
    items[#items + 1] = { label = mount.en, action = mount.en }
  end
  sort_by_label(items)
  return items
end

list_spells = function(skill_def)
  local items = {}
  for _, spell in pairs(res.spells or {}) do
    local match
    if skill_def.trust then
      match = spell.type == 'Trust'
    else
      match = spell.skill == skill_def.skill and spell.type ~= 'Trust'
    end
    if match then
      items[#items + 1] = { label = spell.en, action = spell.en }
    end
  end
  sort_by_label(items)
  return items
end

list_weapon_skills = function()
  local items = {}
  for _, ws in pairs(res.weapon_skills or {}) do
    items[#items + 1] = { label = ws.en, action = ws.en }
  end
  sort_by_label(items)
  return items
end

move_selection = function(delta)
  local frame = top_frame()
  if frame == nil or #frame.items == 0 then return end
  if frame.id == 'reorder' and frame.grabbed then
    reorder_move(frame, delta)
    render()
    return
  end
  local target = frame.index + delta
  if target < 1 then target = 1 end
  if target > #frame.items then target = #frame.items end
  frame.index = target
  render()
end

overlay_entry_label = function(entry)
  return overlay_type_label(entry.overlay_type) .. ': '
    .. (entry.alias or entry.action or tostring(entry.type))
end

overlay_type_available = function(name)
  local def = action_iface.get_overlay_type(name)
  if def == nil or type(def.is_available) ~= 'function' then return false end
  return def.is_available(get_player_state()) and true or false
end

overlay_type_label = function(name)
  local known = overlay_type_labels[name]
  if known ~= nil then return known end
  local pretty = tostring(name):gsub('_', ' '):gsub('(%a)(%w*)', function(head, rest)
    return head:upper() .. rest
  end)
  return pretty
end

pending_summary = function()
  if pending == nil then return 'Confirm' end
  local parts = {}
  if pending.mode == 'overlay' and pending.overlay_type ~= nil then
    parts[#parts + 1] = pending.overlay_type .. ' overlay:'
  end
  parts[#parts + 1] = tostring(pending.type_code)
  if pending.action ~= nil then
    parts[#parts + 1] = '"' .. pending.action .. '"'
  end
  if pending.target ~= nil then
    parts[#parts + 1] = '<' .. pending.target .. '>'
  end
  return table.concat(parts, ' ')
end

push_menu = function(frame)
  menu_stack[#menu_stack + 1] = frame
  render()
end

remove_slot = function(abs_slot)
  local set = get_set(ctx.active_set) or {}
  set.slots = set.slots or {}
  set.slots[abs_slot] = nil
  save_set(ctx.active_set, set)
end

render = function()
  if not open or ui == nil then return end
  local frame = top_frame()
  ui.title:text(string.format('XIVGamepad Binder - Set %d (%s half)\n%s',
    ctx.active_set, half_label(), breadcrumb()))
  local lines = {}
  if frame ~= nil then
    for i = 1, #frame.items do
      local marker = '  '
      if i == frame.index then
        marker = frame.grabbed and '* ' or '> '
      end
      lines[#lines + 1] = marker .. frame.items[i].label
    end
  end
  if #lines == 0 then lines[1] = '  (nothing available)' end
  ui.body:text(table.concat(lines, '\n'))
  if is_trigger_held() then
    ui.status:text('D-pad: move   A: select   B: back   BACK: close')
  else
    ui.status:text('PAUSED - hold LT or RT to navigate')
  end
end

reorder_move = function(frame, delta)
  local from = frame.index
  local to = from + delta
  if to < 1 or to > #frame.overlays then return end
  frame.overlays[from], frame.overlays[to] = frame.overlays[to], frame.overlays[from]
  frame.items[from], frame.items[to] = frame.items[to], frame.items[from]
  frame.index = to
end

reset_to_root = function(sel)
  local root = build_slot_menu()
  if sel ~= nil and sel >= 1 and sel <= #root.items then
    root.index = sel
  end
  menu_stack = { root }
  pending = nil
  render()
end

select_action = function(item)
  pending.action = item.action
  pending.alias = item.alias
  advance_after_action(pending.type_code)
end

select_overlay_type = function(name)
  pending.overlay_type = name
  if name == 'subjob' then
    local player_state = get_player_state()
    pending.condition = { subjob = player_state and player_state.sub_job or nil }
  else
    pending.condition = {}
  end
  push_menu(build_type_menu())
end

select_skill = function(skill_def)
  push_menu(build_action_menu('ma', skill_def))
end

select_slot = function(rel)
  local abs_slot = half_offset + rel
  pending = { slot = abs_slot, rel = rel, mode = 'bind' }
  if slot_binding(abs_slot) == nil then
    push_menu(build_type_menu())
  else
    push_menu(build_occupied_menu(rel))
  end
end

select_slot_op = function(op)
  if op == 'overlay' then
    pending.mode = 'overlay'
    push_menu(build_overlay_type_menu())
  elseif op == 'replace' then
    pending.mode = 'replace'
    -- A backed-out Overlay flow may have left these behind; Replace must not
    -- inherit them (they would mislabel the confirm screen).
    pending.overlay_type = nil
    pending.condition = nil
    push_menu(build_type_menu())
  elseif op == 'remove' then
    remove_slot(pending.slot)
    log.debug('xivgamepad: binder removed slot %d', pending.slot)
    reset_to_root(pending.rel)
  elseif op == 'swap' then
    push_menu(build_swap_menu())
  elseif op == 'reorder' then
    push_menu(build_reorder_menu(pending.slot))
  end
end

select_swap_target = function(rel)
  local abs_slot = half_offset + rel
  swap_slots(pending.slot, abs_slot)
  log.debug('xivgamepad: binder swapped slots %d and %d', pending.slot, abs_slot)
  reset_to_root(rel)
end

select_target = function(code)
  pending.target = code
  push_menu(build_confirm_menu())
end

show_ui = function()
  if ui == nil then return end
  ui.backdrop:show()
  ui.title:show()
  ui.body:show()
  ui.status:show()
end

slot_binding = function(abs_slot)
  local set = get_set(ctx.active_set)
  local slots = set and set.slots
  return slots and slots[abs_slot] or nil
end

sort_by_label = function(items)
  table.sort(items, function(a, b) return a.label < b.label end)
end

swap_slots = function(abs_a, abs_b)
  local set = get_set(ctx.active_set) or {}
  set.slots = set.slots or {}
  set.slots[abs_a], set.slots[abs_b] = set.slots[abs_b], set.slots[abs_a]
  save_set(ctx.active_set, set)
end

top_frame = function()
  return menu_stack[#menu_stack]
end

type_label = function(code)
  for i = 1, #binding_types do
    if binding_types[i].code == code then return binding_types[i].label end
  end
  return nil
end

-- Copies the array: installing the caller's table by reference would alias
-- the reorder frame's working copy into the live set, so later grab-moves
-- would mutate the set without a save and a B-discard could silently persist.
write_overlays = function(abs_slot, overlays)
  local set = get_set(ctx.active_set) or {}
  set.slots = set.slots or {}
  local slot = set.slots[abs_slot]
  if slot == nil then return end
  local copy = {}
  for i = 1, #overlays do
    copy[i] = overlays[i]
  end
  slot.overlays = copy
  save_set(ctx.active_set, set)
end

write_slot = function(abs_slot, binding)
  local set = get_set(ctx.active_set) or {}
  set.slots = set.slots or {}
  set.slots[abs_slot] = binding
  save_set(ctx.active_set, set)
end

return binder
