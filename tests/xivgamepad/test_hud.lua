-- Tests for xivgamepad/hud.lua: init idempotence, view rendering, empty-slot
-- hiding, transparency states, display highlight/label, recast sweeps,
-- drag reporting, tooltips, hide/show, destroy.
--
-- The module under test receives everything via init opts (settings,
-- addon_path, texts/images, resolve_binding, get_player_state,
-- on_element_move); a log stub is preloaded per the contracts doc.

local log_stub = { _lines = {} }
log_stub.debug = function(fmt, ...) table.insert(log_stub._lines, tostring(fmt)) end
log_stub.info  = log_stub.debug
log_stub.error = log_stub.debug
package.loaded['log'] = log_stub

local hud = require('hud')

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

local function assert_true(v, msg)
  if not v then error(msg or 'expected true', 2) end
end

local ADDON_PATH = 'C:\\Windower\\addons\\xivgamepad\\'

-- Geometry with the fixture positions below: half_left at (100,100) puts
-- slot 1 (d-pad UP) at (140,100); half_right at (400,100) puts slot 9 (its
-- d-pad UP, d-pad cluster on the RIGHT) at (576,100) and slot 13 (its face
-- A, face cluster on the LEFT) at (440,180).

local function make_settings()
  return {
    hide_empty_slots      = false,
    transparency_standard = 20,
    transparency_active   = 0,
    transparency_inactive = 60,
    display = {
      wxhb_l       = { set = 2, half = 'left' },
      wxhb_r       = { set = 2, half = 'right' },
      expand_lt_rt = { set = 4, half = 'right' },
      expand_rt_lt = { set = 4, half = 'right' },
    },
    hud_positions = {
      half_left  = { x = 100, y = 100 },
      half_right = { x = 400, y = 100 },
      label      = { x = 100, y = 70 },
    },
  }
end

local function make_view()
  return {
    active_set   = 1,
    set_name     = 'Main',
    mode         = 'job',
    display_mode = nil,
    slots = {
      [1]  = { type = 'ma', action = 'Cure', icon = 'icons/cure.png', cooldown = 60 },
      [5]  = { type = 'ja', action = 'Provoke' },
      [9]  = { type = 'item', action = 'Hi-Potion', count = 3 },
      [13] = { type = 'ws', action = 'Fast Blade', usable = false },
    },
  }
end

local player_state = { buffs = {}, main_job = 'WAR', sub_job = 'NIN', is_mounted = false, in_event = false }

local moves
local settings

local function fresh(resolve_binding)
  windower._reset()
  hud.destroy()
  moves = {}
  settings = make_settings()
  hud.init({
    settings         = settings,
    addon_path       = ADDON_PATH,
    texts            = texts,
    images           = images,
    resolve_binding  = resolve_binding or function(slot, ps) return slot end,
    get_player_state = function() return player_state end,
    on_element_move  = function(id, x, y) table.insert(moves, { id = id, x = x, y = y }) end,
  })
end

-- ---- Guards before init ----

test('on_mouse before init returns false without crashing', function()
  hud.destroy()
  assert_eq(false, hud.on_mouse(1, 10, 10), 'no consumption before init')
  hud.tick()
  hud.refresh({ slots = {} })
  hud.set_display('xhb_l')
end)

-- ---- Init ----

test('init is idempotent: re-init reuses elements and re-reads positions', function()
  fresh()
  local icon_before = hud._layers_for_test(1).icon
  local label_before = hud._label_for_test()
  settings.hud_positions.half_left = { x = 111, y = 122 }
  hud.init({
    settings         = settings,
    addon_path       = ADDON_PATH,
    texts            = texts,
    images           = images,
    resolve_binding  = function(slot) return slot end,
    get_player_state = function() return player_state end,
    on_element_move  = function() end,
  })
  assert_eq(icon_before, hud._layers_for_test(1).icon, 'slot icon element reused')
  assert_eq(label_before, hud._label_for_test(), 'label element reused')
  assert_eq(111, hud._position_for_test('half_left').x, 'position re-read on re-init')
end)

test('missing hud_positions fall back to defaults', function()
  fresh()
  settings.hud_positions = {}
  hud.init({
    settings         = settings,
    addon_path       = ADDON_PATH,
    texts            = texts,
    images           = images,
    resolve_binding  = function(slot) return slot end,
    get_player_state = function() return player_state end,
    on_element_move  = function() end,
  })
  assert_eq(180, hud._position_for_test('half_left').x, 'default half_left x')
  assert_eq(460, hud._position_for_test('half_right').x, 'default half_right x')
end)

-- ---- Refresh / rendering ----

test('refresh renders bindings: icon paths, badge, unusable indicator', function()
  fresh()
  hud.show()
  hud.refresh(make_view())
  local slot1 = hud._layers_for_test(1)
  assert_eq(ADDON_PATH .. 'icons/cure.png', slot1.icon:path(), 'binding.icon used when present')
  assert_eq(true, slot1.icon:visible(), 'bound slot icon visible')
  local slot5 = hud._layers_for_test(5)
  assert_eq(ADDON_PATH .. 'images/types/ja.png', slot5.icon:path(), 'type default icon when binding.icon absent')
  local slot9 = hud._layers_for_test(9)
  assert_eq('3', slot9.badge:text(), 'count badge text')
  assert_eq(true, slot9.badge:visible(), 'count badge visible')
  assert_eq(false, hud._layers_for_test(1).badge:visible(), 'no badge without count')
  local slot13 = hud._layers_for_test(13)
  assert_eq(true, slot13.unusable:visible(), 'unusable indicator visible')
  assert_eq(false, slot1.unusable:visible(), 'usable slot has no indicator')
end)

test('slot geometry follows the frozen order and cluster sides', function()
  fresh()
  hud.refresh(make_view())
  local x, y = hud._slot_pos_for_test(1)
  assert_eq(140, x, 'left half d-pad UP x')
  assert_eq(100, y, 'left half d-pad UP y')
  x, y = hud._slot_pos_for_test(5)
  assert_eq(276, x, 'left half face A x (face cluster right of d-pad)')
  assert_eq(180, y, 'left half face A y (bottom of cross)')
  x, y = hud._slot_pos_for_test(9)
  assert_eq(576, x, 'right half d-pad UP x (d-pad cluster on the right)')
  x, y = hud._slot_pos_for_test(13)
  assert_eq(440, x, 'right half face A x (face cluster on the left)')
end)

test('empty slots render placeholder, hide when hide_empty_slots, keep positions', function()
  fresh()
  hud.show()
  hud.refresh(make_view())
  local slot2 = hud._layers_for_test(2)
  assert_eq(ADDON_PATH .. 'images/slot_empty.png', slot2.icon:path(), 'empty placeholder path')
  assert_eq(true, slot2.icon:visible(), 'empty slot shown while hide_empty_slots false')
  local x1 = hud._slot_pos_for_test(1)
  settings.hide_empty_slots = true
  hud.refresh(make_view())
  assert_eq(false, hud._layers_for_test(2).icon:visible(), 'empty slot hidden')
  assert_eq(true, hud._layers_for_test(1).icon:visible(), 'bound slot still shown')
  assert_eq(x1, hud._slot_pos_for_test(1), 'positions reserved (slot 1 unchanged)')
end)

-- ---- Transparency / display states ----

test('three transparency states apply per half', function()
  fresh()
  hud.show()
  hud.refresh(make_view())
  local left = hud._layers_for_test(1).icon
  local right = hud._layers_for_test(9).icon
  assert_eq(204, left._alpha, 'standard alpha (20 -> 204)')
  assert_eq(204, right._alpha, 'standard alpha on right half')
  hud.set_display('xhb_l')
  assert_eq(255, left._alpha, 'active alpha (0 -> 255)')
  assert_eq(102, right._alpha, 'inactive alpha (60 -> 102)')
  hud.set_display('xhb_r')
  assert_eq(102, left._alpha, 'left inactive when XHB-R active')
  assert_eq(255, right._alpha, 'right active when XHB-R active')
  hud.set_display(nil)
  assert_eq(204, left._alpha, 'set_display(nil) restores standard')
  assert_eq(204, right._alpha, 'set_display(nil) restores standard on right')
end)

test('wxhb/expanded active half follows the configured display half', function()
  fresh()
  hud.show()
  hud.refresh(make_view())
  hud.set_display('wxhb_l')
  assert_eq(255, hud._layers_for_test(1).icon._alpha, 'wxhb_l configured half=left is active')
  assert_eq(102, hud._layers_for_test(9).icon._alpha, 'right half inactive')
  hud.set_display('expand_lt_rt')
  assert_eq(102, hud._layers_for_test(1).icon._alpha, 'expand_lt_rt half=right: left inactive')
  assert_eq(255, hud._layers_for_test(9).icon._alpha, 'expand_lt_rt half=right: right active')
end)

test('unusable slots fade against the current transparency', function()
  fresh()
  hud.show()
  hud.refresh(make_view())
  assert_eq(81, hud._layers_for_test(13).icon._alpha, 'standard 204 * 0.4 -> 81')
  hud.set_display('xhb_r')
  assert_eq(102, hud._layers_for_test(13).icon._alpha, 'active 255 * 0.4 -> 102')
end)

test('label shows set, mode, and active display mode', function()
  fresh()
  hud.show()
  local view = make_view()
  view.display_mode = 'xhb_l'
  hud.refresh(view)
  local text = hud._label_for_test():text()
  assert_true(text:find('Main', 1, true) ~= nil, 'label names the set')
  assert_true(text:find('job', 1, true) ~= nil, 'label names the mode')
  assert_true(text:find('XHB-L', 1, true) ~= nil, 'label names the display mode')
  hud.set_display(nil)
  text = hud._label_for_test():text()
  assert_true(text:find('XHB-L', 1, true) == nil, 'display label cleared at idle')
  hud.set_display('wxhb_r')
  text = hud._label_for_test():text()
  assert_true(text:find('WXHB-R', 1, true) ~= nil, 'set_display without refresh updates the label')
end)

-- ---- Recast sweeps ----

test('tick drives the clock-sweep steps from recast data', function()
  fresh()
  hud.show()
  hud.refresh(make_view())
  local sweep1 = hud._layers_for_test(1).sweep
  windower.ffxi._spell_recasts[1] = 1800
  hud.tick()
  assert_eq(true, sweep1:visible(), 'sweep visible while recasting')
  assert_eq(ADDON_PATH .. 'images/sweep_4.png', sweep1:path(), '30s of 60s cooldown -> step 4 of 8')
  windower.ffxi._spell_recasts[1] = 0
  hud.tick()
  assert_eq(false, sweep1:visible(), 'sweep hidden when recast done')
end)

test('sweep total falls back to the peak remaining when cooldown is unset', function()
  fresh()
  hud.show()
  hud.refresh(make_view())
  local sweep5 = hud._layers_for_test(5).sweep
  windower.ffxi._ability_recasts[5] = 15
  hud.tick()
  assert_eq(ADDON_PATH .. 'images/sweep_8.png', sweep5:path(), 'first tick: full fraction -> step 8')
  windower.ffxi._ability_recasts[5] = 7.5
  hud.tick()
  assert_eq(ADDON_PATH .. 'images/sweep_4.png', sweep5:path(), 'half the peak -> step 4')
end)

test('a view switch mid-sweep resets the slot peak', function()
  fresh()
  hud.show()
  hud.refresh(make_view())
  windower.ffxi._ability_recasts[5] = 60
  hud.tick()
  assert_eq(ADDON_PATH .. 'images/sweep_8.png', hud._layers_for_test(5).sweep:path(),
    'peak 60 established for the old binding')
  local view = make_view()
  view.slots[5] = { type = 'ja', action = 'Berserk' }
  hud.refresh(view)
  windower.ffxi._ability_recasts[5] = nil
  windower.ffxi._ability_recasts[1] = 15
  hud.tick()
  assert_eq(ADDON_PATH .. 'images/sweep_8.png', hud._layers_for_test(5).sweep:path(),
    'new binding starts a fresh peak (full sweep, not 15/60)')
end)

test('tick is a no-op while the HUD is hidden', function()
  fresh()
  hud.show()
  hud.refresh(make_view())
  hud.hide()
  windower.ffxi._spell_recasts[1] = 1800
  hud.tick()
  assert_eq(false, hud._layers_for_test(1).sweep:visible(), 'no sweep drawn while hidden')
end)

test('tick degrades gracefully when recast APIs are absent', function()
  fresh()
  hud.show()
  hud.refresh(make_view())
  windower.ffxi._spell_recasts[1] = 1800
  hud.tick()
  windower.ffxi.get_spell_recasts = nil
  windower.ffxi.get_ability_recasts = nil
  hud.tick()
  assert_eq(false, hud._layers_for_test(1).sweep:visible(), 'sweep hidden without recast API')
end)

-- ---- Drag ----

test('drag moves an element and reports on_element_move on release', function()
  fresh()
  hud.show()
  hud.refresh(make_view())
  hud.set_draggable(true)
  assert_eq(true, hud.on_mouse(1, 150, 110), 'down over half_left starts a drag')
  assert_eq(true, hud.on_mouse(0, 170, 140), 'drag move consumed')
  assert_eq(120, hud._position_for_test('half_left').x, 'element x follows the drag')
  assert_eq(130, hud._position_for_test('half_left').y, 'element y follows the drag')
  assert_eq(160, hud._layers_for_test(1).icon._x, 'children reposition with the element')
  assert_eq(true, hud.on_mouse(2, 170, 140), 'release consumed')
  assert_eq(1, #moves, 'one move reported')
  assert_eq('half_left', moves[1].id, 'element id reported')
  assert_eq(120, moves[1].x, 'final x reported')
  assert_eq(130, moves[1].y, 'final y reported')
end)

test('set_draggable(false) blocks drags and cancels one in flight', function()
  fresh()
  hud.show()
  hud.refresh(make_view())
  hud.set_draggable(false)
  assert_eq(false, hud.on_mouse(1, 150, 110), 'down does not start a drag')
  assert_eq(0, #moves, 'no move reported')
  hud.set_draggable(true)
  hud.on_mouse(1, 150, 110)
  hud.set_draggable(false)
  assert_eq(false, hud.on_mouse(2, 150, 110), 'in-flight drag cancelled')
  assert_eq(0, #moves, 'cancelled drag reports nothing')
end)

test('mouse events off every element are not consumed', function()
  fresh()
  hud.show()
  hud.refresh(make_view())
  hud.set_draggable(true)
  assert_eq(false, hud.on_mouse(1, 900, 900), 'down outside not consumed')
  assert_eq(false, hud.on_mouse(2, 900, 900), 'up outside not consumed')
end)

-- ---- Tooltips ----

test('hover over a bound slot shows the tooltip; empty space hides it', function()
  fresh()
  hud.show()
  hud.refresh(make_view())
  hud.on_mouse(0, 150, 110)
  local tooltip = hud._tooltip_for_test()
  assert_eq(true, tooltip:visible(), 'tooltip shown over slot 1')
  local text = tooltip:text()
  assert_true(text:find('Cure', 1, true) ~= nil, 'tooltip names the action')
  assert_true(text:find('Type: ma', 1, true) ~= nil, 'tooltip names the type')
  assert_true(text:find('MP: 8', 1, true) ~= nil, 'tooltip shows MP from resources')
  windower.ffxi._spell_recasts[1] = 1800
  hud.on_mouse(0, 150, 110)
  assert_true(tooltip:text():find('Recast: 30.0s', 1, true) ~= nil, 'tooltip shows recast')
  hud.on_mouse(0, 900, 900)
  assert_eq(false, tooltip:visible(), 'tooltip hidden off-slot')
end)

-- ---- Resolver injection ----

test('raw slots carrying overlays are re-resolved via the injected resolver', function()
  local calls = {}
  fresh(function(slot, ps)
    table.insert(calls, { slot = slot, ps = ps })
    if slot and slot.overlays then
      return { type = 'ja', action = 'Provoke' }
    end
    return slot
  end)
  hud.show()
  local view = make_view()
  view.slots[3] = { type = 'ma', action = 'Cure', overlays = { { overlay_type = 'subjob' } } }
  hud.refresh(view)
  assert_eq(ADDON_PATH .. 'images/types/ja.png', hud._layers_for_test(3).icon:path(),
    'overlay-resolved binding rendered')
  assert_true(#calls >= 1, 'resolver invoked')
  assert_eq(player_state, calls[1].ps, 'injected player state passed to the resolver')
end)

-- ---- Show / hide / destroy ----

test('hide conceals every layer; show restores them', function()
  fresh()
  hud.show()
  hud.refresh(make_view())
  windower.ffxi._spell_recasts[1] = 1800
  hud.tick()
  hud.hide()
  assert_eq(false, hud._layers_for_test(1).icon:visible(), 'icon hidden')
  assert_eq(false, hud._layers_for_test(1).sweep:visible(), 'sweep hidden')
  assert_eq(false, hud._layers_for_test(9).badge:visible(), 'badge hidden')
  assert_eq(false, hud._layers_for_test(13).unusable:visible(), 'indicator hidden')
  assert_eq(false, hud._label_for_test():visible(), 'label hidden')
  assert_eq(false, hud._tooltip_for_test():visible(), 'tooltip hidden')
  hud.show()
  assert_eq(true, hud._layers_for_test(1).icon:visible(), 'icon restored')
  assert_eq(true, hud._label_for_test():visible(), 'label restored')
end)

test('destroy tears down elements and init rebuilds from scratch', function()
  fresh()
  local icon = hud._layers_for_test(1).icon
  hud.destroy()
  assert_eq(true, icon._destroyed, 'element destroyed')
  assert_eq(nil, hud._layers_for_test(1), 'state cleared')
  hud.destroy()
  fresh()
  assert_true(hud._layers_for_test(1) ~= nil, 'init rebuilds after destroy')
end)

-- ----

hud.destroy()
windower._reset()

io.write(string.format('test_hud: %d passed, %d failed\n', pass, fail))
if fail > 0 then
  error(fail .. ' test(s) failed in test_hud.lua')
end
