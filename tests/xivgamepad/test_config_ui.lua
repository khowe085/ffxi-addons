-- Tests for xivgamepad/config_ui.lua: the four frozen tabs, on_change-only
-- staging (never direct writes), the Keys tab capture control -> launch_wizard,
-- gestures add/edit/remove/cycle/timing affordances, custom-tab wheel
-- scrolling, open/close/is_open, unconditional on_mouse delegation (incl. the
-- Save/Discard swallowed-up seam), and window-drag position staging.

local log_stub = { _lines = {} }
log_stub.debug = function(fmt, ...) table.insert(log_stub._lines, tostring(fmt)) end
log_stub.info  = log_stub.debug
log_stub.error = log_stub.debug
package.loaded['xivgamepad.log'] = log_stub

local config_ui = require('xivgamepad.config_ui')

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

local function make_staged()
  return {
    config_x = 100,
    config_y = 100,
    hide_empty_slots = false,
    transparency_standard = 0,
    transparency_active = 0,
    transparency_inactive = 100,
    sets = {
      { name = 'Set 1', source = 'job',    skip_cycle = false },
      { name = 'Set 2', source = 'job',    skip_cycle = false },
      { name = 'Set 3', source = 'job',    skip_cycle = true },
      { name = 'Set 4', source = 'job',    skip_cycle = true },
      { name = 'Set 5', source = 'job',    skip_cycle = true },
      { name = 'Set 6', source = 'shared', skip_cycle = false },
      { name = 'Set 7', source = 'shared', skip_cycle = true },
      { name = 'Set 8', source = 'shared', skip_cycle = false },
    },
    display = {
      wxhb_l       = { set = 2, half = 'left' },
      wxhb_r       = { set = 2, half = 'right' },
      expand_lt_rt = { set = 4, half = 'right' },
      expand_rt_lt = { set = 4, half = 'right' },
    },
    key_mapping = {
      LT   = { code = 2 },
      RT   = { code = 3 },
      BACK = { code = 2, ctrl = true },
    },
    gestures = {
      { id = 'auto_run', type = 'tap', button = 'LB', context = 'bare',
        action = 'auto_run', params = { max_hold = 0.25 } },
      { id = 'xhb_l', type = 'hold', button = 'LT', context = 'bare',
        action = 'activate_xhb_l', params = { min_hold = 0.12 } },
      { id = 'bare_a', type = 'button', button = 'A', context = 'bare',
        action = 'menu_confirm' },
    },
  }
end

local current
local changes
local wizard_calls
local saves
local discards

local function setup(apply)
  config_ui.destroy()
  windower._reset()
  current = make_staged()
  changes = {}
  wizard_calls = 0
  saves = 0
  discards = 0
  config_ui.init({
    texts         = texts,
    images        = images,
    get_staged    = function() return current end,
    on_save       = function()
      saves = saves + 1
      config_ui.close()
    end,
    on_discard    = function()
      discards = discards + 1
      config_ui.close()
    end,
    launch_wizard = function() wizard_calls = wizard_calls + 1 end,
    on_change     = function(key, value)
      changes[#changes + 1] = { key = key, value = value }
      if apply ~= false then current[key] = value end
    end,
  })
end

local function row_texts(tab)
  local out = {}
  for i, row in ipairs(tab.rows) do
    out[i] = row.text
  end
  return out
end

local function first_body_line()
  local text = config_ui._body_text_for_test() or ''
  return text:match('^([^\n]*)')
end

-- Window geometry at anchor (100,100): body 460x400, 4 tabs so the body
-- viewport starts at y+36; total window 478x472. Footer buttons (96px wide,
-- 36px tall) sit at y 536..572: Save spans x 374..470, Discard 476..572.
local SAVE_X, SAVE_Y = 422, 554
local DISCARD_X, DISCARD_Y = 524, 554

-- ---- Guards before init ----

test('on_mouse before init returns false without crashing', function()
  config_ui.destroy()
  assert_eq(false, config_ui.on_mouse(1, 10, 10), 'no consumption before init')
  assert_eq(false, config_ui.is_open(), 'not open before init')
  config_ui.close()
  config_ui.open({ config_x = 0, config_y = 0 })
end)

test('mutators without a staging session are safe no-ops', function()
  config_ui.destroy()
  windower._reset()
  changes = {}
  config_ui.init({
    texts = texts,
    images = images,
    get_staged = function() return nil end,
    on_change = function(key, value) changes[#changes + 1] = { key = key, value = value } end,
  })
  config_ui.cycle_set_source(1)
  config_ui.toggle_skip_cycle(1)
  config_ui.cycle_display_set('wxhb_l')
  config_ui.toggle_display_half('wxhb_l')
  config_ui.toggle_hide_empty_slots()
  config_ui.adjust_transparency('standard', 10)
  config_ui.add_gesture({ id = 'x' })
  config_ui.add_gesture_template()
  config_ui.cycle_gesture_field('x', 'button')
  config_ui.update_gesture('x', 'action', 'map')
  config_ui.remove_gesture('x')
  config_ui.adjust_gesture_timing('x', 'max_hold', 0.05)
  assert_eq(0, #changes, 'nothing staged without a session')
end)

-- ---- build_tabs ----

test('build_tabs returns the four frozen tabs', function()
  setup()
  local tabs = config_ui.build_tabs(current)
  assert_eq(4, #tabs, 'four tabs')
  assert_eq('Sets', tabs[1].title, 'tab 1')
  assert_eq('Display', tabs[2].title, 'tab 2')
  assert_eq('Keys', tabs[3].title, 'tab 3')
  assert_eq('Gestures', tabs[4].title, 'tab 4')
end)

test('Sets tab lists the 8 positions with name, source, and skip flag', function()
  setup()
  local rows = row_texts(config_ui.build_tabs(current)[1])
  assert_eq(9, #rows, 'header plus 8 set rows')
  assert_true(rows[2]:find('Set 1', 1, true) ~= nil, 'row names the set')
  assert_true(rows[2]:find('job', 1, true) ~= nil, 'row shows the source')
  assert_true(rows[2]:find('[cycle]', 1, true) ~= nil, 'row shows cycling state')
  assert_true(rows[4]:find('[skip]', 1, true) ~= nil, 'skip_cycle rendered')
  assert_true(rows[7]:find('shared', 1, true) ~= nil, 'shared source rendered')
end)

test('Display tab lists mode assignments, hide_empty_slots, transparency', function()
  setup()
  local rows = row_texts(config_ui.build_tabs(current)[2])
  assert_true(rows[2]:find('wxhb_l', 1, true) ~= nil, 'wxhb_l row present')
  assert_true(rows[2]:find('set 2', 1, true) ~= nil, 'assigned set rendered')
  assert_true(rows[2]:find('half left', 1, true) ~= nil, 'assigned half rendered')
  assert_true(rows[4]:find('expand_lt_rt', 1, true) ~= nil, 'expand_lt_rt row present')
  assert_true(rows[6]:find('hide_empty_slots: false', 1, true) ~= nil, 'hide_empty_slots row')
  assert_true(rows[7]:find('standard', 1, true) ~= nil, 'transparency standard row')
  assert_true(rows[9]:find('inactive', 1, true) ~= nil and rows[9]:find('100', 1, true) ~= nil,
    'transparency inactive value rendered')
end)

test('Keys tab exposes the capture control and the mapping rows', function()
  setup()
  local tab = config_ui.build_tabs(current)[3]
  local rows = row_texts(tab)
  assert_true(rows[1]:find('Capture', 1, true) ~= nil, 'row 1 is the capture control')
  assert_true(tab.rows[1].on_click ~= nil, 'capture control is clickable')
  assert_eq(27, #rows, 'capture row plus all 26 virtual buttons')
  assert_true(rows[2]:find('LT', 1, true) ~= nil and rows[2]:find('key 2', 1, true) ~= nil,
    'LT mapping rendered')
  local back_row
  for _, text in ipairs(rows) do
    if text:find('BACK', 1, true) then back_row = text end
  end
  assert_true(back_row:find('+Ctrl', 1, true) ~= nil, 'ctrl mapping flagged')
  local l4_row
  for _, text in ipairs(rows) do
    if text:find('L4', 1, true) then l4_row = text end
  end
  assert_true(l4_row:find('unmapped', 1, true) ~= nil, 'unmapped button flagged')
end)

test('Gestures tab renders two rows per gesture plus the add row', function()
  setup()
  local tab = config_ui.build_tabs(current)[4]
  local rows = row_texts(tab)
  assert_eq(8, #rows, 'header + 3 gestures x 2 rows + add row')
  assert_true(rows[2]:find('[x]', 1, true) ~= nil, 'line A carries the remove control')
  assert_true(rows[2]:find('auto_run', 1, true) ~= nil, 'line A names the gesture')
  assert_true(rows[2]:find('type=tap', 1, true) ~= nil, 'line A shows the type')
  assert_true(rows[2]:find('btn=LB', 1, true) ~= nil, 'line A shows the button')
  assert_true(rows[3]:find('ctx=bare', 1, true) ~= nil, 'line B shows the context')
  assert_true(rows[3]:find('act=auto_run', 1, true) ~= nil, 'line B shows the action')
  assert_true(rows[3]:find('max_hold=0.25', 1, true) ~= nil, 'line B shows the timing')
  assert_true(rows[6]:find('type=button', 1, true) ~= nil, 'button-type gesture rendered')
  assert_true(rows[7]:find('+', 1, true) == nil, 'no timing tune for the button type')
  assert_eq('[+ add gesture]', rows[8], 'trailing add row')
end)

-- ---- Mutations route through on_change ----

test('edits never write the staged table directly', function()
  setup(false)
  local sets_before = current.sets
  config_ui.cycle_set_source(1)
  assert_eq(1, #changes, 'one change reported')
  assert_eq('sets', changes[1].key, 'whole sets table staged under its key')
  assert_eq('job', current.sets[1].source, 'staged table untouched by the module')
  assert_eq(sets_before, current.sets, 'staged sub-table not replaced by the module')
  assert_eq('shared', changes[1].value[1].source, 'edited copy handed to on_change')
  assert_true(changes[1].value ~= current.sets, 'on_change receives a copy, not the live table')
end)

test('cycle_set_source toggles job/shared through on_change', function()
  setup()
  config_ui.cycle_set_source(1)
  assert_eq('shared', current.sets[1].source, 'job -> shared')
  config_ui.cycle_set_source(1)
  assert_eq('job', current.sets[1].source, 'shared -> job')
  assert_eq('Set 1', current.sets[1].name, 'other fields preserved')
end)

test('toggle_skip_cycle flips the flag', function()
  setup()
  config_ui.toggle_skip_cycle(1)
  assert_eq(true, current.sets[1].skip_cycle, 'false -> true')
  config_ui.toggle_skip_cycle(1)
  assert_eq(false, current.sets[1].skip_cycle, 'true -> false')
end)

test('set_set_name renames a position', function()
  setup()
  config_ui.set_set_name(2, 'Boss Fight')
  assert_eq('Boss Fight', current.sets[2].name, 'name staged')
  assert_eq('sets', changes[1].key, 'routed through on_change')
end)

test('cycle_display_set increments and wraps at 8', function()
  setup()
  config_ui.cycle_display_set('wxhb_l')
  assert_eq(3, current.display.wxhb_l.set, '2 -> 3')
  current.display.wxhb_l.set = 8
  config_ui.cycle_display_set('wxhb_l')
  assert_eq(1, current.display.wxhb_l.set, '8 wraps to 1')
  assert_eq('left', current.display.wxhb_l.half, 'half preserved')
end)

test('toggle_display_half flips left/right', function()
  setup()
  config_ui.toggle_display_half('wxhb_l')
  assert_eq('right', current.display.wxhb_l.half, 'left -> right')
  config_ui.toggle_display_half('wxhb_l')
  assert_eq('left', current.display.wxhb_l.half, 'right -> left')
end)

test('toggle_hide_empty_slots flips the boolean', function()
  setup()
  config_ui.toggle_hide_empty_slots()
  assert_eq(true, current.hide_empty_slots, 'false -> true')
  config_ui.toggle_hide_empty_slots()
  assert_eq(false, current.hide_empty_slots, 'true -> false')
end)

test('adjust_transparency steps and clamps to 0..100', function()
  setup()
  config_ui.adjust_transparency('active', 10)
  assert_eq(10, current.transparency_active, 'stepped up')
  config_ui.adjust_transparency('standard', -10)
  assert_eq(0, current.transparency_standard, 'clamped at 0')
  config_ui.adjust_transparency('inactive', 10)
  assert_eq(100, current.transparency_inactive, 'clamped at 100')
end)

-- ---- Wizard launch ----

test('request_capture and the Keys tab capture row invoke launch_wizard', function()
  setup()
  config_ui.request_capture()
  assert_eq(1, wizard_calls, 'direct call launches the wizard')
  local tab = config_ui.build_tabs(current)[3]
  tab.on_mouse(10, 5, 1)
  assert_eq(2, wizard_calls, 'clicking the capture row launches the wizard')
  tab.on_mouse(10, 5, 0)
  assert_eq(2, wizard_calls, 'non-click mouse events do not launch')
end)

-- ---- Gestures add / edit / remove / cycle / timing ----

test('add_gesture appends a copied entry through on_change', function()
  setup()
  local entry = { id = 'l5_inventory', type = 'tap', button = 'L5', context = 'bare',
    action = 'inventory', params = { max_hold = 0.3 } }
  config_ui.add_gesture(entry)
  assert_eq(4, #current.gestures, 'entry appended')
  assert_eq('l5_inventory', current.gestures[4].id, 'entry content staged')
  assert_true(current.gestures[4] ~= entry, 'entry deep-copied')
  config_ui.add_gesture({ type = 'tap' })
  assert_eq(4, #current.gestures, 'entry without id rejected')
end)

test('add_gesture rejects duplicate ids', function()
  setup()
  config_ui.add_gesture({ id = 'auto_run', type = 'tap', button = 'L5', action = 'inventory' })
  assert_eq(0, #changes, 'duplicate id staged nothing')
  assert_eq(3, #current.gestures, 'gesture list unchanged')
  assert_eq('LB', current.gestures[1].button, 'existing entry untouched')
end)

test('add_gesture_template appends unique cyclable template entries', function()
  setup()
  config_ui.add_gesture_template()
  config_ui.add_gesture_template()
  assert_eq(5, #current.gestures, 'two templates appended')
  assert_eq('custom_1', current.gestures[4].id, 'first generated id')
  assert_eq('custom_2', current.gestures[5].id, 'second generated id unique')
  local t = current.gestures[4]
  assert_eq('tap', t.type, 'template type')
  assert_eq('A', t.button, 'template button')
  assert_eq('bare', t.context, 'template context')
  assert_eq('jump', t.action, 'template action')
  assert_eq(0.25, t.params.max_hold, 'template timing seeded')
end)

test('cycle_gesture_field cycles button, context, type (seeding timing), action', function()
  setup()
  config_ui.cycle_gesture_field('bare_a', 'button')
  assert_eq('B', current.gestures[3].button, 'A -> B in the frozen button order')
  config_ui.cycle_gesture_field('bare_a', 'context')
  assert_eq('trigger_held', current.gestures[3].context, 'bare -> trigger_held')
  config_ui.cycle_gesture_field('bare_a', 'type')
  assert_eq('tap', current.gestures[3].type, 'button -> tap')
  assert_eq(0.25, current.gestures[3].params.max_hold, 'timing default seeded on type change')
  config_ui.cycle_gesture_field('bare_a', 'action')
  assert_eq('menu_focus', current.gestures[3].action, 'menu_confirm -> next registered action')
  local before = #changes
  config_ui.cycle_gesture_field('nope', 'button')
  config_ui.cycle_gesture_field('bare_a', 'nope')
  assert_eq(before, #changes, 'unknown id / field are no-ops')
end)

test('cycling the action of a raw-command entry restarts at the first registered action', function()
  setup()
  config_ui.update_gesture('bare_a', 'action', 'input /wave')
  config_ui.cycle_gesture_field('bare_a', 'action')
  assert_eq('activate_expanded_lt_rt', current.gestures[3].action,
    'raw command escape hatch cycles into the registry')
end)

test('update_gesture edits one field of one entry', function()
  setup()
  config_ui.update_gesture('bare_a', 'action', 'map')
  assert_eq('map', current.gestures[3].action, 'field updated')
  assert_eq('menu_confirm', make_staged().gestures[3].action, 'sanity: fixture unchanged')
  local before = #changes
  config_ui.update_gesture('nope', 'action', 'map')
  assert_eq(before, #changes, 'unknown id changes nothing')
end)

test('remove_gesture deletes by id', function()
  setup()
  config_ui.remove_gesture('auto_run')
  assert_eq(2, #current.gestures, 'entry removed')
  assert_eq('xhb_l', current.gestures[1].id, 'remaining entries keep order')
  local before = #changes
  config_ui.remove_gesture('nope')
  assert_eq(before, #changes, 'unknown id changes nothing')
end)

test('adjust_gesture_timing steps and clamps at the minimum', function()
  setup()
  config_ui.adjust_gesture_timing('auto_run', 'max_hold', 0.05)
  assert_eq(0.3, current.gestures[1].params.max_hold, 'stepped up')
  config_ui.adjust_gesture_timing('auto_run', 'max_hold', -1)
  assert_eq(0.05, current.gestures[1].params.max_hold, 'clamped at 0.05')
  config_ui.adjust_gesture_timing('bare_a', 'max_hold', 0.05)
  assert_eq(0.05, current.gestures[3].params.max_hold, 'params table created on demand')
end)

test('gesture row click zones route to the named mutators', function()
  setup()
  -- Re-fetch the tab after each edit, mirroring refresh_tabs: row closures
  -- capture the gesture's current type, so a stale tab would tune the old
  -- timing param.
  local function gtab() return config_ui.build_tabs(current)[4] end
  gtab().on_mouse(200, 20, 1)
  assert_eq('hold', current.gestures[1].type, 'type zone cycles tap -> hold')
  assert_eq(0.12, current.gestures[1].params.min_hold, 'new primary timing seeded')
  gtab().on_mouse(400, 20, 1)
  assert_eq('RB', current.gestures[1].button, 'button zone cycles LB -> RB')
  gtab().on_mouse(100, 38, 1)
  assert_eq('trigger_held', current.gestures[1].context, 'context zone cycles bare -> trigger_held')
  gtab().on_mouse(300, 38, 1)
  assert_eq('case', current.gestures[1].action, 'action zone cycles auto_run -> case')
  gtab().on_mouse(410, 38, 1)
  assert_eq(0.07, current.gestures[1].params.min_hold, 'timing minus zone steps down')
  gtab().on_mouse(440, 38, 1)
  assert_eq(0.12, current.gestures[1].params.min_hold, 'timing plus zone steps up')
  local before = #changes
  gtab().on_mouse(440, 113, 1)
  assert_eq(before, #changes, 'timing zone is inert for a type with no timing param')
  gtab().on_mouse(10, 20, 1)
  assert_eq(2, #current.gestures, 'remove zone deletes the gesture')
  assert_eq('xhb_l', current.gestures[1].id, 'first gesture removed')
  gtab().on_mouse(10, 95, 1)
  assert_eq('custom_1', current.gestures[#current.gestures].id, 'add row appends a template')
end)

test('custom tabs scroll with the mouse wheel', function()
  setup()
  local tab = config_ui.build_tabs(current)[3]
  tab.render({ x = 0, y = 0, width = 460, height = 400 })
  assert_true(first_body_line():find('Capture', 1, true) ~= nil, 'top of the list rendered first')
  tab.on_mouse(10, 10, 10, -1)
  assert_true(first_body_line():find('LT', 1, true) ~= nil, 'wheel down scrolls the rows')
  tab.on_mouse(10, 10, 10, 1)
  assert_true(first_body_line():find('Capture', 1, true) ~= nil, 'wheel up scrolls back')
  tab.on_mouse(10, 10, 10, 1)
  assert_true(first_body_line():find('Capture', 1, true) ~= nil, 'offset clamps at the top')
end)

-- ---- Open / close / mouse ----

test('open, is_open, close lifecycle; reopen while open is a no-op', function()
  setup()
  assert_eq(false, config_ui.is_open(), 'closed initially')
  config_ui.open(current)
  assert_eq(true, config_ui.is_open(), 'open after open()')
  config_ui.open(current)
  assert_eq(true, config_ui.is_open(), 'second open is a no-op')
  config_ui.close()
  assert_eq(false, config_ui.is_open(), 'closed after close()')
end)

test('on_mouse delegates unconditionally: closed window consumes nothing', function()
  setup()
  assert_eq(false, config_ui.on_mouse(1, 150, 150), 'closed window does not consume')
  config_ui.open(current)
  assert_eq(true, config_ui.on_mouse(1, 150, 300), 'click over the open window consumed')
  assert_eq(false, config_ui.on_mouse(1, 900, 900), 'click outside not consumed')
  config_ui.close()
  assert_eq(false, config_ui.on_mouse(1, 150, 300), 'consumption stops after close')
end)

test('clicking a Sets row through the window routes the edit via on_change', function()
  setup()
  config_ui.open(current)
  -- Body viewport: x=100, y=100+36 (header + tab bar). Row 2 (set 1) spans
  -- rel_y 18..36; rel_x 10 is in the left (source) zone.
  assert_eq(true, config_ui.on_mouse(1, 110, 156), 'row click consumed')
  assert_eq('sets', changes[1].key, 'edit staged via on_change')
  assert_eq('shared', current.sets[1].source, 'source cycled by the click')
end)

test('tab labels stay visible after an edit click re-renders the tabs', function()
  setup()
  config_ui.open(current)
  assert_eq(true, config_ui.on_mouse(1, 110, 156), 'row click consumed')
  local labels = config_ui._gui_for_test():_tab_labels_for_test()
  assert_eq(4, #labels, 'four tab labels present')
  for i, label in ipairs(labels) do
    assert_eq(true, label._visible, 'label ' .. i .. ' visible after refresh_tabs')
  end
end)

test('Save click through on_mouse closes the window and swallows the paired up', function()
  setup()
  config_ui.open(current)
  assert_eq(true, config_ui.on_mouse(1, SAVE_X, SAVE_Y), 'save down consumed')
  assert_eq(1, saves, 'on_save fired on the down')
  assert_eq(false, config_ui.is_open(), 'window closed by on_save')
  assert_eq(true, config_ui.on_mouse(2, SAVE_X, SAVE_Y), 'paired up swallowed, not leaked')
  assert_eq(false, config_ui.on_mouse(2, SAVE_X, SAVE_Y), 'subsequent stray up not consumed')
end)

test('Discard click through on_mouse closes the window and swallows the paired up', function()
  setup()
  config_ui.open(current)
  assert_eq(true, config_ui.on_mouse(1, DISCARD_X, DISCARD_Y), 'discard down consumed')
  assert_eq(1, discards, 'on_discard fired on the down')
  assert_eq(false, config_ui.is_open(), 'window closed by on_discard')
  assert_eq(true, config_ui.on_mouse(2, DISCARD_X, DISCARD_Y), 'paired up swallowed, not leaked')
  assert_eq(false, config_ui.on_mouse(2, DISCARD_X, DISCARD_Y), 'subsequent stray up not consumed')
end)

test('window drag stages config_x/config_y through on_change', function()
  setup()
  config_ui.open(current)
  assert_eq(true, config_ui.on_mouse(1, 105, 105), 'header down consumed')
  assert_eq(true, config_ui.on_mouse(0, 135, 145), 'drag move consumed')
  assert_eq(true, config_ui.on_mouse(2, 135, 145), 'release consumed')
  local staged_x, staged_y
  for _, c in ipairs(changes) do
    if c.key == 'config_x' then staged_x = c.value end
    if c.key == 'config_y' then staged_y = c.value end
  end
  assert_eq(130, staged_x, 'config_x staged on drag release')
  assert_eq(140, staged_y, 'config_y staged on drag release')
end)

test('stage_window_pos routes both coordinates through on_change', function()
  setup()
  config_ui.stage_window_pos(11, 22)
  assert_eq('config_x', changes[1].key, 'x key')
  assert_eq(11, changes[1].value, 'x value')
  assert_eq('config_y', changes[2].key, 'y key')
  assert_eq(22, changes[2].value, 'y value')
end)

-- ----

config_ui.destroy()
windower._reset()

io.write(string.format('test_config_ui: %d passed, %d failed\n', pass, fail))
if fail > 0 then
  error(fail .. ' test(s) failed in test_config_ui.lua')
end
