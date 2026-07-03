-- Persistent cross-hotbar HUD (contract: .planning/xivgamepad-contracts.md,
-- "Frontend module contracts" / hud). Renders both 16-slot halves as FFXIV
-- cross clusters, applies the three transparency states, animates recast
-- clock-sweeps from tick(), and supports per-element dragging during config.
--
-- Everything arrives via init opts (settings table, addon_path, texts/images
-- libs, resolve_binding, get_player_state, on_element_move) so the module
-- never requires main or action. hud.on_mouse(mtype, x, y, delta) is a
-- contract-consistent addition: main feeds its mouse event here; it returns
-- true only while it consumes a drag interaction.
--
-- Data-driven slot decorations: a resolved binding may carry `count` (item /
-- ninja tool / stratagem badge, computed upstream), `usable = false`
-- (fade + indicator), and `cooldown` (total seconds for the sweep fraction;
-- when absent the peak observed remaining time is used).
--
-- Transparency math: settings values are 0 (opaque) .. 100 (invisible);
-- alpha = round((100 - transparency) * 255 / 100).

local log = require('xivgamepad.log')
local res = require('resources')

local hud = {}

local state = nil

local SLOT_SIZE     = 40
local CLUSTER_SPAN  = SLOT_SIZE * 3
local CLUSTER_GAP   = 16
local HALF_W        = CLUSTER_SPAN * 2 + CLUSTER_GAP
local HALF_H        = CLUSTER_SPAN
local LABEL_W       = 240
local LABEL_H       = 18
local SWEEP_STEPS   = 8
local UNUSABLE_FADE = 0.4

local ELEMENT_IDS = { 'half_left', 'half_right', 'label' }

local ELEMENT_DEFAULTS = {
  half_left  = { x = 180, y = 520 },
  half_right = { x = 460, y = 520 },
  label      = { x = 180, y = 494 },
}

local ELEMENT_SIZES = {
  half_left  = { w = HALF_W, h = HALF_H },
  half_right = { w = HALF_W, h = HALF_H },
  label      = { w = LABEL_W, h = LABEL_H },
}

-- Frozen slot indices (UP=1, RIGHT=2, DOWN=3, LEFT=4 / A=5, B=6, X=7, Y=8);
-- the visual arrangement below is the HUD's own concern. Faces mirror the
-- physical pad: Y top, B right, A bottom, X left.
local DPAD_OFFSETS = {
  { x = SLOT_SIZE, y = 0 },
  { x = SLOT_SIZE * 2, y = SLOT_SIZE },
  { x = SLOT_SIZE, y = SLOT_SIZE * 2 },
  { x = 0, y = SLOT_SIZE },
}

local FACE_OFFSETS = {
  { x = SLOT_SIZE, y = SLOT_SIZE * 2 },
  { x = SLOT_SIZE * 2, y = SLOT_SIZE },
  { x = 0, y = SLOT_SIZE },
  { x = SLOT_SIZE, y = 0 },
}

local MODE_LABELS = {
  xhb_l        = 'XHB-L',
  xhb_r        = 'XHB-R',
  wxhb_l       = 'WXHB-L',
  wxhb_r       = 'WXHB-R',
  expand_lt_rt = 'Expanded LT>RT',
  expand_rt_lt = 'Expanded RT>LT',
}

local TYPE_ICONS = {
  ma    = 'images/types/ma.png',
  ja    = 'images/types/ja.png',
  ws    = 'images/types/ws.png',
  a     = 'images/types/attack.png',
  ra    = 'images/types/ranged.png',
  pet   = 'images/types/pet.png',
  item  = 'images/types/item.png',
  mount = 'images/types/mount.png',
  ta    = 'images/types/target.png',
  map   = 'images/types/map.png',
  ct    = 'images/types/command.png',
  ex    = 'images/types/display.png',
}

local DEFAULT_TYPE_ICON = 'images/types/default.png'
local EMPTY_SLOT_ICON   = 'images/slot_empty.png'

-- Memoizes the linear English-name resource scans (res tables are static),
-- keyed 'type|action'; false marks a known miss so tick() never re-scans a
-- binding per frame.
local resource_cache = {}

local active_half
local alpha_from_transparency
local element_at
local find_resource
local icon_path
local recast_remaining
local render_all
local render_label
local render_slot
local resolved_slot
local resource_for
local slot_at
local slot_pos
local slot_transparency
local tooltip_lines

-- Public functions (alphabetical; _-prefixed are test-only accessors)

function hud._label_for_test()
  return state and state.label
end

function hud._layers_for_test(i)
  return state and state.slots[i]
end

function hud._position_for_test(id)
  local p = state and state.positions[id]
  if p == nil then return nil end
  return { x = p.x, y = p.y }
end

function hud._slot_pos_for_test(i)
  if state == nil then return nil end
  local x, y = slot_pos(i)
  return x, y
end

function hud._tooltip_for_test()
  return state and state.tooltip
end

function hud.destroy()
  if state == nil then return end
  for i = 1, 16 do
    local layers = state.slots[i]
    layers.icon:destroy()
    layers.sweep:destroy()
    layers.badge:destroy()
    layers.unusable:destroy()
  end
  state.label:destroy()
  state.tooltip:destroy()
  state = nil
end

function hud.hide()
  if state == nil then return end
  state.visible = false
  state.drag = nil
  state.tooltip:hide()
  for i = 1, 16 do
    state.slots[i].sweep:hide()
  end
  render_all()
end

function hud.init(opts)
  opts = opts or {}
  if state == nil then
    local texts_lib = opts.texts
    local images_lib = opts.images
    state = {
      slots     = {},
      positions = {},
      visible   = false,
      draggable = false,
      drag      = nil,
      view      = nil,
      display   = nil,
      peaks     = {},
    }
    state.label = texts_lib.new('', { pos = { x = 0, y = 0 }, flags = { draggable = false } })
    state.tooltip = texts_lib.new('', { pos = { x = 0, y = 0 }, flags = { draggable = false } })
    state.label:draggable(false)
    state.tooltip:draggable(false)
    for i = 1, 16 do
      state.slots[i] = {
        icon = images_lib.new({
          pos   = { x = 0, y = 0 },
          size  = { width = SLOT_SIZE, height = SLOT_SIZE },
          flags = { draggable = false },
        }),
        sweep = images_lib.new({
          pos   = { x = 0, y = 0 },
          size  = { width = SLOT_SIZE, height = SLOT_SIZE },
          flags = { draggable = false },
        }),
        badge = texts_lib.new('', { pos = { x = 0, y = 0 }, flags = { draggable = false } }),
        unusable = texts_lib.new('X', { pos = { x = 0, y = 0 }, flags = { draggable = false } }),
      }
      state.slots[i].icon:draggable(false)
      state.slots[i].sweep:draggable(false)
      state.slots[i].badge:draggable(false)
      state.slots[i].unusable:draggable(false)
    end
    log.debug('hud elements created')
  end
  state.settings         = opts.settings or {}
  state.addon_path       = opts.addon_path or ''
  state.resolve_binding  = opts.resolve_binding
  state.get_player_state = opts.get_player_state
  state.on_element_move  = opts.on_element_move
  state.drag = nil
  state.tooltip:hide()
  local saved = state.settings.hud_positions or {}
  for _, id in ipairs(ELEMENT_IDS) do
    local p = saved[id] or ELEMENT_DEFAULTS[id]
    state.positions[id] = { x = p.x, y = p.y }
  end
  render_all()
end

function hud.on_mouse(mtype, x, y, delta)
  if state == nil then return false end
  if state.drag then
    if mtype == 0 then
      local pos = state.positions[state.drag.id]
      pos.x = x - state.drag.dx
      pos.y = y - state.drag.dy
      render_all()
      return true
    end
    if mtype == 2 then
      local id = state.drag.id
      state.drag = nil
      local pos = state.positions[id]
      log.debug('hud element %s moved to %d,%d', id, pos.x, pos.y)
      if state.on_element_move then
        state.on_element_move(id, pos.x, pos.y)
      end
      return true
    end
    return true
  end
  if mtype == 1 and state.draggable and state.visible then
    local id = element_at(x, y)
    if id then
      local pos = state.positions[id]
      state.drag = { id = id, dx = x - pos.x, dy = y - pos.y }
      return true
    end
  end
  if mtype == 0 and state.visible then
    local i = slot_at(x, y)
    local binding = i and resolved_slot(i) or nil
    if binding then
      state.tooltip:text(table.concat(tooltip_lines(binding), '\n'))
      state.tooltip:pos(x + 16, y + 16)
      state.tooltip:show()
    else
      state.tooltip:hide()
    end
  end
  return false
end

function hud.refresh(view)
  if state == nil then return end
  state.view = view
  state.display = view and view.display_mode or nil
  -- Peaks are keyed by slot index; a new view can put a different binding in
  -- the same slot mid-cooldown, so stale peaks must not leak across views.
  state.peaks = {}
  render_all()
end

function hud.set_display(mode)
  if state == nil then return end
  state.display = mode
  render_all()
end

function hud.set_draggable(draggable)
  if state == nil then return end
  state.draggable = draggable and true or false
  if not state.draggable then
    state.drag = nil
  end
end

function hud.show()
  if state == nil then return end
  state.visible = true
  render_all()
end

function hud.tick()
  -- Sweeps are already hidden by hide(), so a hidden HUD skips the whole
  -- per-frame pass.
  if state == nil or state.view == nil or not state.visible then return end
  for i = 1, 16 do
    local layers = state.slots[i]
    local binding = resolved_slot(i)
    local remaining = binding and recast_remaining(binding) or 0
    if remaining > 0 then
      local peak = state.peaks[i]
      if peak == nil or remaining > peak then
        peak = remaining
        state.peaks[i] = peak
      end
      local total = binding.cooldown or peak
      local fraction = 1
      if total > 0 then
        fraction = remaining / total
      end
      if fraction > 1 then fraction = 1 end
      local step = math.ceil(fraction * SWEEP_STEPS)
      if step < 1 then step = 1 end
      local x, y = slot_pos(i)
      layers.sweep:pos(x, y)
      layers.sweep:path(state.addon_path .. string.format('images/sweep_%d.png', step))
      layers.sweep:show()
    else
      state.peaks[i] = nil
      layers.sweep:hide()
    end
  end
end

-- Private functions (alphabetical)

active_half = function(mode)
  if mode == nil then return nil end
  if mode == 'xhb_l' then return 'half_left' end
  if mode == 'xhb_r' then return 'half_right' end
  local display = state.settings.display
  local assign = display and display[mode]
  if assign and assign.half == 'left' then
    return 'half_left'
  end
  return 'half_right'
end

alpha_from_transparency = function(transparency)
  if transparency < 0 then transparency = 0 end
  if transparency > 100 then transparency = 100 end
  return math.floor((100 - transparency) * 255 / 100 + 0.5)
end

element_at = function(x, y)
  for _, id in ipairs(ELEMENT_IDS) do
    local pos = state.positions[id]
    local size = ELEMENT_SIZES[id]
    if x >= pos.x and x < pos.x + size.w and y >= pos.y and y < pos.y + size.h then
      return id
    end
  end
  return nil
end

find_resource = function(tbl, name)
  if tbl == nil or name == nil then return nil end
  for _, entry in pairs(tbl) do
    if entry.en == name then
      return entry
    end
  end
  return nil
end

icon_path = function(binding)
  return binding.icon or TYPE_ICONS[binding.type] or DEFAULT_TYPE_ICON
end

recast_remaining = function(binding)
  local ffxi = windower and windower.ffxi
  if ffxi == nil then return 0 end
  if binding.type == 'ma' then
    if type(ffxi.get_spell_recasts) ~= 'function' then return 0 end
    local spell = resource_for(binding)
    if spell == nil then return 0 end
    local recasts = ffxi.get_spell_recasts() or {}
    local raw = recasts[spell.recast_id or spell.id]
    if raw == nil or raw <= 0 then return 0 end
    -- get_spell_recasts reports 1/60ths of a second.
    return raw / 60
  end
  if binding.type == 'ja' then
    if type(ffxi.get_ability_recasts) ~= 'function' then return 0 end
    local ability = resource_for(binding)
    if ability == nil then return 0 end
    local recasts = ffxi.get_ability_recasts() or {}
    local raw = recasts[ability.recast_id or ability.id]
    if raw == nil or raw <= 0 then return 0 end
    return raw
  end
  return 0
end

render_all = function()
  render_label()
  for i = 1, 16 do
    render_slot(i)
  end
end

render_label = function()
  local text = ''
  local view = state.view
  if view then
    local name = view.set_name or ('Set ' .. tostring(view.active_set or '?'))
    text = string.format('%s [%s]', name, tostring(view.mode or '?'))
  end
  local mode_label = MODE_LABELS[state.display]
  if mode_label then
    if text ~= '' then
      text = text .. ' - ' .. mode_label
    else
      text = mode_label
    end
  end
  local pos = state.positions.label
  state.label:pos(pos.x, pos.y)
  state.label:text(text)
  if state.visible then
    state.label:show()
  else
    state.label:hide()
  end
end

render_slot = function(i)
  local layers = state.slots[i]
  local binding = resolved_slot(i)
  local x, y = slot_pos(i)
  layers.icon:pos(x, y)
  layers.sweep:pos(x, y)
  layers.badge:pos(x + SLOT_SIZE - 12, y + SLOT_SIZE - 16)
  layers.unusable:pos(x + 2, y + 2)
  local alpha = alpha_from_transparency(slot_transparency(i))
  if binding == nil then
    layers.sweep:hide()
    layers.badge:hide()
    layers.unusable:hide()
    if state.visible and not state.settings.hide_empty_slots then
      layers.icon:path(state.addon_path .. EMPTY_SLOT_ICON)
      layers.icon:alpha(alpha)
      layers.icon:show()
    else
      layers.icon:hide()
    end
    return
  end
  layers.icon:path(state.addon_path .. icon_path(binding))
  if binding.usable == false then
    layers.icon:alpha(math.floor(alpha * UNUSABLE_FADE))
    if state.visible then
      layers.unusable:show()
    else
      layers.unusable:hide()
    end
  else
    layers.icon:alpha(alpha)
    layers.unusable:hide()
  end
  if state.visible then
    layers.icon:show()
  else
    layers.icon:hide()
  end
  if binding.count ~= nil and state.visible then
    layers.badge:text(tostring(binding.count))
    layers.badge:show()
  else
    layers.badge:hide()
  end
end

-- View slots are already resolved by main, but a raw slot (carrying an
-- overlays array) is re-resolved via the injected resolver so the HUD never
-- renders a stale base binding.
resolved_slot = function(i)
  local view = state.view
  local slot = view and view.slots and view.slots[i] or nil
  if slot ~= nil and slot.overlays ~= nil and state.resolve_binding then
    local player_state = state.get_player_state and state.get_player_state() or nil
    return state.resolve_binding(slot, player_state)
  end
  return slot
end

resource_for = function(binding)
  if binding.action == nil then return nil end
  local tbl
  if binding.type == 'ma' then
    tbl = res.spells
  elseif binding.type == 'ja' then
    tbl = res.job_abilities
  else
    return nil
  end
  local key = tostring(binding.type) .. '|' .. tostring(binding.action)
  local hit = resource_cache[key]
  if hit ~= nil then
    if hit == false then return nil end
    return hit
  end
  local entry = find_resource(tbl, binding.action)
  resource_cache[key] = entry or false
  return entry
end

slot_at = function(x, y)
  for i = 1, 16 do
    local sx, sy = slot_pos(i)
    if x >= sx and x < sx + SLOT_SIZE and y >= sy and y < sy + SLOT_SIZE then
      return i
    end
  end
  return nil
end

slot_pos = function(i)
  local element_id = i <= 8 and 'half_left' or 'half_right'
  local li = i <= 8 and i or i - 8
  local dpad_on_left = element_id == 'half_left'
  local in_dpad_cluster = li <= 4
  local off = in_dpad_cluster and DPAD_OFFSETS[li] or FACE_OFFSETS[li - 4]
  local ox = 0
  if in_dpad_cluster ~= dpad_on_left then
    ox = CLUSTER_SPAN + CLUSTER_GAP
  end
  local base = state.positions[element_id]
  return base.x + ox + off.x, base.y + off.y
end

slot_transparency = function(i)
  local settings = state.settings
  local half_id = i <= 8 and 'half_left' or 'half_right'
  local active = active_half(state.display)
  if active == nil then
    return settings.transparency_standard or 0
  end
  if half_id == active then
    return settings.transparency_active or 0
  end
  return settings.transparency_inactive or 100
end

tooltip_lines = function(binding)
  local lines = {}
  lines[#lines + 1] = binding.alias or binding.action or tostring(binding.type or '')
  lines[#lines + 1] = 'Type: ' .. tostring(binding.type)
  if binding.type == 'ma' then
    local spell = resource_for(binding)
    if spell and spell.mp_cost then
      lines[#lines + 1] = 'MP: ' .. tostring(spell.mp_cost)
    end
  elseif binding.type == 'ws' then
    lines[#lines + 1] = 'TP: 1000'
  end
  local remaining = recast_remaining(binding)
  if remaining > 0 then
    lines[#lines + 1] = string.format('Recast: %.1fs', remaining)
  end
  return lines
end

return hud
