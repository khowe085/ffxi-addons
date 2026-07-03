-- Main entry point: lifecycle, command dispatch, module wiring, and the
-- dispatch-suspend states (contract: .planning/xivgamepad-contracts.md).
-- Owns player_state and the mode flags; frontends report into them via the
-- callbacks injected here and never own them.

local settings_lib = require('lib.settings.settings')
local texts        = require('texts')
local images       = require('images')
local log          = require('xivgamepad.log')
local keyboard     = require('xivgamepad.input.keyboard')
local gamepad      = require('xivgamepad.gamepad')
local action       = require('xivgamepad.action')
local storage      = require('xivgamepad.storage')
local hud          = require('xivgamepad.hud')
local config_ui    = require('xivgamepad.config_ui')
local tester       = require('xivgamepad.tester')
local wizard       = require('xivgamepad.wizard')
local binder       = require('xivgamepad.binder')

_addon.name     = 'XIVGamepad'
_addon.author   = 'Windower Addons'
_addon.version  = '1.0.0'
_addon.commands = {'xivgamepad', 'xg'}

local EVENT_STATUS_ID = 4
-- Windower resources status id 85 = 'Mounted' (status 4 = cutscene/event,
-- the same id xivcrossbar keys its cutscene hide on).
local MOUNT_STATUS_ID = 85
local POLL_INTERVAL   = 1

-- Bare-face menu synthesis that stays live while a menu or the chat bar is
-- open (Resolved Decision 3); everything else suspends.
local MENU_NAV_ACTIONS = {
  menu_confirm = true,
  menu_cancel  = true,
  menu_focus   = true,
  menu_open    = true,
}

-- Keys FFXI acts on that the addon reads: the Ctrl+number macro palette and
-- the paddle F-keys. bind-noop'd on load, restored on unload; the plain
-- number row is already dead and F1-F8 stay untouched.
local NOOP_BIND_KEYS = {
  '^`', '^1', '^2', '^3', '^4', '^5', '^6', '^7', '^8', '^9', '^0', '^=',
  'f9', 'f10', 'f11', 'f12',
}

local binder_mode     = false
local char_name
local current_display
local gestures_by_id  = {}
local initialized     = false
local job_sets        = {}
local learn_mode      = false
local live_settings
local player_state    = {
  buffs      = {},
  main_job   = nil,
  sub_job    = nil,
  is_mounted = false,
  in_event   = false,
}
local poll_active     = false
local shared_sets     = {}
local staged_settings
local test_mode       = false
local unloaded        = false
local wizard_teardown = false

local xivgamepad = {}

local apply_binds
local binder_opts
local binder_save_set
local build_defaults
local build_view
local close_wizard
local commands
local commit_live
local config_opts
local cycle_set
local default_key_mapping
local display_target
local execute_slot
local exit_learn_mode
local host
local hud_opts
local index_gestures
local make_ctx
local offer_wizard
local on_binder_close
local on_buff_gain
local on_buff_loss
local on_job_change
local on_status_change
local on_zone_change
local poll_tick
local rebuild_player_state
local reconcile_player_state
local resolve_gesture_action
local restore_binds
local set_content
local set_is_empty
local stage_change
local stage_hud_position
local start_learn_mode
local start_poll
local switch_set
local toggle_binder
local toggle_mode
local wizard_cancel
local wizard_finish

-- Public functions (alphabetical)

function xivgamepad.cmd_debugmode(arg)
  arg = arg and tostring(arg):lower() or nil
  local enabled
  if arg == 'on' then
    log.set_debug(true)
    enabled = true
  elseif arg == 'off' then
    log.set_debug(false)
    enabled = false
  else
    enabled = log.toggle()
  end
  log.info('debug mode %s', enabled and 'on' or 'off')
end

function xivgamepad.cmd_learn(sub)
  sub = sub and tostring(sub):lower() or nil
  if sub == 'skip' then
    wizard.skip()
  elseif sub == 'back' then
    wizard.back()
  elseif sub == 'cancel' then
    wizard.cancel()
  else
    if not initialized then return end
    start_learn_mode()
  end
end

function xivgamepad.cmd_test()
  if not initialized then return end
  if test_mode then
    test_mode = false
    tester.close()
  else
    test_mode = true
    tester.open()
  end
end

function xivgamepad.dispatch(cmd, ...)
  cmd = cmd and tostring(cmd):lower() or 'help'
  local handler = commands[cmd]
  if handler then
    handler(...)
  else
    xivgamepad.print_help()
  end
end

function xivgamepad.dispatch_gesture(id, params)
  if not initialized then return end
  params = params or {}
  if player_state.in_event then return end
  if learn_mode then return end
  if test_mode then
    tester.on_gesture(id, params)
    return
  end
  local action_name = resolve_gesture_action(id)
  if not action_name then
    log.debug('gesture %s has no action; dropped', tostring(id))
    return
  end
  if binder_mode then
    if action_name == 'open_binder' then
      toggle_binder()
    end
    return
  end
  local info = windower.ffxi.get_info() or {}
  if (info.menu_open or info.chat_open) and not MENU_NAV_ACTIONS[action_name] then
    log.debug('gesture %s suspended (menu or chat open)', tostring(id))
    return
  end
  action.run_action(action_name, make_ctx(), params)
end

function xivgamepad.init()
  if settings_lib.in_setup() then
    settings_lib.discard()
  end
  staged_settings = nil
  if initialized then
    close_wizard()
    tester.close()
    binder.close()
    config_ui.close()
  end
  test_mode   = false
  binder_mode = false
  learn_mode  = false
  keyboard.set_raw_callback(nil)

  log.init(windower.addon_path)
  live_settings = settings_lib.load(windower.addon_path, build_defaults())
  char_name     = windower.ffxi.get_player().name
  rebuild_player_state()
  shared_sets = storage.load_shared(windower.addon_path, char_name)
  job_sets    = storage.load_job(windower.addon_path, char_name)
  index_gestures()

  keyboard.reset()
  keyboard.configure(live_settings.key_mapping)
  keyboard.set_callback(function(button, pressed)
    xivgamepad.on_button(button, pressed)
  end)

  gamepad.init({ schedule = function(fn, seconds) coroutine.schedule(fn, seconds) end })
  gamepad.set_gesture_callback(function(id, params)
    xivgamepad.dispatch_gesture(id, params)
  end)
  gamepad.set_display_callback(function(mode)
    current_display = mode
    hud.set_display(mode)
    xivgamepad.refresh_hud()
  end)
  gamepad.reset()
  gamepad.set_gestures(live_settings.gestures)

  action.set_host(host)

  hud.init(hud_opts())
  hud.set_draggable(false)
  current_display = nil
  hud.set_display(nil)
  config_ui.init(config_opts())
  tester.init({ texts = texts, images = images, addon_path = windower.addon_path })
  binder.init(binder_opts())

  initialized = true
  if player_state.in_event then
    hud.hide()
  else
    hud.show()
  end
  xivgamepad.refresh_hud()
  start_poll()

  if not live_settings.key_mapping_complete then
    offer_wizard()
  end
end

function xivgamepad.on_button(button, pressed)
  if not initialized then return end
  if learn_mode then return end
  if player_state.in_event then return end
  if binder_mode then
    -- Gamepad first: the BACK-with-trigger open_binder gesture is the
    -- close-toggle path, and dispatching it before binder.on_button means the
    -- binder's own BACK fallback then sees a closed binder and no-ops --
    -- binder-first would close and immediately reopen on the same press.
    gamepad.on_button_event(button, pressed)
    binder.on_button(button, pressed)
    return
  end
  if test_mode then
    tester.on_button_event(button, pressed)
  end
  gamepad.on_button_event(button, pressed)
end

function xivgamepad.on_load()
  apply_binds()
  if settings_lib.logged_in() then
    xivgamepad.init()
  end
end

function xivgamepad.on_logout()
  if settings_lib.in_setup() then
    settings_lib.discard()
  end
  staged_settings = nil
  if initialized then
    close_wizard()
    tester.close()
    binder.close()
    config_ui.close()
    keyboard.reset()
    keyboard.set_raw_callback(nil)
    gamepad.reset()
    hud.set_draggable(false)
    hud.hide()
  end
  test_mode       = false
  binder_mode     = false
  learn_mode      = false
  current_display = nil
  initialized     = false
end

-- Unconditional delegation (echo pattern): the gui must see the mouse-up that
-- pairs with a click that closed the window, so this is never gated on state.
-- The config window wins; the HUD (element drags, slot tooltips) only sees
-- events the window did not consume.
function xivgamepad.on_mouse(mtype, x, y, delta)
  if config_ui.on_mouse(mtype, x, y, delta) then
    return true
  end
  return hud.on_mouse(mtype, x, y, delta)
end

function xivgamepad.on_unload()
  unloaded = true
  if settings_lib.in_setup() then
    settings_lib.discard()
  end
  staged_settings = nil
  if initialized then
    close_wizard()
    binder.close()
    tester.destroy()
    config_ui.destroy()
    hud.destroy()
  end
  initialized = false
  restore_binds()
end

function xivgamepad.print_help()
  log.info('XIVGamepad commands:')
  log.info('//xg config (c)      - Open the configuration window')
  log.info('//xg save (s)        - Save staged changes and close the window')
  log.info('//xg discard (d)     - Discard staged changes and close the window')
  log.info('//xg test (t)        - Toggle the gamepad tester overlay')
  log.info('//xg learn (l)       - Open the key-capture wizard (learn skip|back|cancel)')
  log.info('//xg debugmode (dbg) - Toggle debug logging (debugmode on|off)')
  log.info('//xg help            - Show this command list')
end

function xivgamepad.refresh_hud()
  if not live_settings then return end
  hud.refresh(build_view())
end

function xivgamepad.setup_close_discard()
  if settings_lib.in_setup() then
    settings_lib.discard()
  end
  staged_settings = nil
  if not initialized then return end
  config_ui.close()
  hud.set_draggable(false)
  -- Discard reverts everything since the session opened, including runtime
  -- set-state mutations mirrored by commit_live: reload live from disk so
  -- memory and disk agree without writing anything.
  if settings_lib.logged_in() then
    live_settings = settings_lib.load(windower.addon_path, build_defaults())
  end
  keyboard.configure(live_settings.key_mapping)
  gamepad.set_gestures(live_settings.gestures)
  index_gestures()
  hud.init(hud_opts())
  xivgamepad.refresh_hud()
end

function xivgamepad.setup_close_save()
  if not staged_settings then return end
  live_settings   = settings_lib.commit(staged_settings, windower.addon_path)
  staged_settings = nil
  config_ui.close()
  hud.set_draggable(false)
  keyboard.configure(live_settings.key_mapping)
  gamepad.set_gestures(live_settings.gestures)
  index_gestures()
  hud.init(hud_opts())
  xivgamepad.refresh_hud()
end

function xivgamepad.setup_open()
  if not initialized then return end
  if config_ui.is_open() then return end
  staged_settings = settings_lib.open_setup(live_settings)
  hud.set_draggable(true)
  config_ui.open(staged_settings)
end

-- Test-only accessors

function xivgamepad._get_char_name()
  return char_name
end

function xivgamepad._get_flags()
  return {
    initialized = initialized,
    test_mode   = test_mode,
    binder_mode = binder_mode,
    learn_mode  = learn_mode,
  }
end

function xivgamepad._get_live()
  return live_settings
end

function xivgamepad._get_player_state()
  return player_state
end

function xivgamepad._get_staged()
  return staged_settings
end

function xivgamepad._reconcile()
  reconcile_player_state()
end

-- Private functions (alphabetical)

apply_binds = function()
  for _, key in ipairs(NOOP_BIND_KEYS) do
    windower.send_command('bind ' .. key .. ' xivgamepad noop')
  end
end

-- Exactly the surface binder.init documents: get_set/save_set map working
-- position 1..8 onto the shared.json or job.json content behind that
-- position's source flag; on_close is the single binder-closed path (any
-- close route fires it), so binder_mode is cleared here and nowhere reloads.
binder_opts = function()
  return {
    action           = action,
    texts            = texts,
    images           = images,
    get_set          = function(position) return set_content(position) end,
    save_set         = function(position, set_table) binder_save_set(position, set_table) end,
    get_player_state = function() return player_state end,
    on_close         = function() on_binder_close() end,
  }
end

binder_save_set = function(position, set_table)
  local meta = live_settings.sets and live_settings.sets[position]
  if not meta then
    log.error('binder_save_set: unknown set position %s', tostring(position))
    return
  end
  if meta.source == 'shared' then
    shared_sets[position] = set_table
    storage.save_shared(windower.addon_path, char_name, shared_sets)
  else
    local job = player_state.main_job
    if not job then
      log.error('binder_save_set: no main job for job-sourced set %d', position)
      return
    end
    local sets = job_sets[job]
    if not sets then
      sets = {}
      job_sets[job] = sets
    end
    sets[position] = set_table
    storage.save_job(windower.addon_path, char_name, job_sets)
  end
  xivgamepad.refresh_hud()
end

build_defaults = function()
  return {
    config_x = 100,
    config_y = 100,
    current_mode = 'job',
    active_set = 1,
    key_mapping_complete = false,
    key_mapping = default_key_mapping(),
    sets = {
      { name = 'Set 1', source = 'job',    skip_cycle = false },
      { name = 'Set 2', source = 'job',    skip_cycle = false },
      { name = 'Set 3', source = 'job',    skip_cycle = true  },
      { name = 'Set 4', source = 'job',    skip_cycle = true  },
      { name = 'Set 5', source = 'job',    skip_cycle = true  },
      { name = 'Set 6', source = 'shared', skip_cycle = false },
      { name = 'Set 7', source = 'shared', skip_cycle = true  },
      { name = 'Set 8', source = 'shared', skip_cycle = false },
    },
    display = {
      wxhb_l       = { set = 2, half = 'left'  },
      wxhb_r       = { set = 2, half = 'right' },
      expand_lt_rt = { set = 4, half = 'right' },
      expand_rt_lt = { set = 4, half = 'right' },
    },
    hide_empty_slots = false,
    transparency_standard = 0,
    transparency_active = 0,
    transparency_inactive = 100,
    gestures = gamepad.default_gestures(),
    hud_positions = {},
  }
end

build_view = function()
  local display_mode = current_display
  local position = live_settings.active_set or 1
  if display_mode then
    local assigned = display_target(display_mode)
    if assigned then
      position = assigned
    end
  end
  local content = set_content(position)
  local slots = {}
  for index = 1, 16 do
    local slot = content and content.slots and content.slots[index] or nil
    slots[index] = action.resolve_binding(slot, player_state)
  end
  local meta = live_settings.sets and live_settings.sets[position]
  return {
    active_set   = position,
    set_name     = (meta and meta.name) or ('Set ' .. tostring(position)),
    mode         = live_settings.current_mode,
    display_mode = display_mode,
    slots        = slots,
  }
end

-- Forced teardown (re-init / logout / unload): cancel without the on_cancel
-- persistence a user dismissal triggers -- committing here would write the old
-- character's flag into the new character's file on a switch.
close_wizard = function()
  if wizard.is_active() then
    wizard_teardown = true
    wizard.cancel()
    wizard_teardown = false
  end
  exit_learn_mode()
end

-- Persist runtime set-state changes (active_set/current_mode). Outside a
-- config session they commit straight to disk. While one is open, the live
-- mutation is mirrored into the staged table so save preserves it; discard
-- reloads live from disk (setup_close_discard), so memory and disk converge
-- either way.
commit_live = function(keys)
  if not settings_lib.logged_in() then return end
  if settings_lib.in_setup() then
    if staged_settings then
      for _, key in ipairs(keys or {}) do
        settings_lib.stage_set(staged_settings, key, live_settings[key])
      end
    end
    return
  end
  live_settings = settings_lib.commit(live_settings, windower.addon_path)
  hud.init(hud_opts())
end

-- Exactly the surface config_ui.init documents: on_change (staging), staged
-- accessor, save/discard handlers that commit/discard AND close the window
-- (the config_gui mouse-up swallow relies on the close happening inside the
-- handler), and the wizard launcher for the Keys tab.
config_opts = function()
  return {
    texts         = texts,
    images        = images,
    on_save       = xivgamepad.setup_close_save,
    on_discard    = xivgamepad.setup_close_discard,
    launch_wizard = function() start_learn_mode() end,
    get_staged    = function() return staged_settings end,
    on_change     = function(key, value) stage_change(key, value) end,
  }
end

cycle_set = function()
  local start = live_settings.active_set or 1
  for step = 1, 8 do
    local position = ((start - 1 + step) % 8) + 1
    local meta = live_settings.sets and live_settings.sets[position]
    if meta and meta.source == live_settings.current_mode
      and not meta.skip_cycle and not set_is_empty(position) then
      if live_settings.active_set ~= position then
        live_settings.active_set = position
        commit_live({ 'active_set' })
      end
      xivgamepad.refresh_hud()
      return
    end
  end
  log.debug('cycle_set: no eligible set in the %s pool', tostring(live_settings.current_mode))
end

default_key_mapping = function()
  return {
    LT         = { code = 2 },
    RT         = { code = 3 },
    LB         = { code = 4 },
    RB         = { code = 5 },
    A          = { code = 6 },
    B          = { code = 7 },
    X          = { code = 8 },
    Y          = { code = 9 },
    DPAD_UP    = { code = 10 },
    DPAD_RIGHT = { code = 11 },
    DPAD_DOWN  = { code = 41 },
    DPAD_LEFT  = { code = 13 },
    BACK       = { code = 2,  ctrl = true },
    START      = { code = 3,  ctrl = true },
    TRACKPAD_1 = { code = 4,  ctrl = true },
    TRACKPAD_2 = { code = 5,  ctrl = true },
    TRACKPAD_3 = { code = 6,  ctrl = true },
    TRACKPAD_4 = { code = 7,  ctrl = true },
    TRACKPAD_5 = { code = 8,  ctrl = true },
    TRACKPAD_6 = { code = 9,  ctrl = true },
    TRACKPAD_7 = { code = 10, ctrl = true },
    TRACKPAD_8 = { code = 11, ctrl = true },
    L4         = { code = 67 },
    L5         = { code = 68 },
    R4         = { code = 87 },
    R5         = { code = 88 },
  }
end

display_target = function(display_mode)
  if display_mode == 'xhb_l' then
    return live_settings.active_set, 'left'
  end
  if display_mode == 'xhb_r' then
    return live_settings.active_set, 'right'
  end
  local assigned = live_settings.display and live_settings.display[display_mode]
  if assigned and assigned.set then
    return assigned.set, assigned.half
  end
  return nil, nil
end

execute_slot = function(display_mode, slot)
  local position, half = display_target(display_mode)
  if not position then
    log.debug('execute_slot: unknown display mode %s', tostring(display_mode))
    return
  end
  if type(slot) ~= 'number' or slot < 1 or slot > 8 then
    log.debug('execute_slot: invalid slot %s', tostring(slot))
    return
  end
  local index = half == 'right' and slot + 8 or slot
  local content = set_content(position)
  local slot_data = content and content.slots and content.slots[index] or nil
  local binding = action.resolve_binding(slot_data, player_state)
  if binding then
    action.execute_binding(binding, make_ctx())
  end
end

exit_learn_mode = function()
  learn_mode = false
  keyboard.set_raw_callback(nil)
end

hud_opts = function()
  return {
    settings         = live_settings,
    addon_path       = windower.addon_path,
    texts            = texts,
    images           = images,
    resolve_binding  = action.resolve_binding,
    get_player_state = function() return player_state end,
    on_element_move  = function(element_id, x, y)
      stage_hud_position(element_id, x, y)
    end,
  }
end

index_gestures = function()
  gestures_by_id = {}
  for _, entry in ipairs(live_settings.gestures or {}) do
    if entry.id then
      gestures_by_id[entry.id] = entry
    end
  end
end

make_ctx = function()
  return { player_state = player_state, addon_path = windower.addon_path }
end

offer_wizard = function()
  log.info('Key mapping not confirmed yet - opening the key-capture wizard (//xg learn reopens it)')
  start_learn_mode()
end

on_binder_close = function()
  binder_mode = false
  -- save_set already kept the in-memory content current, so closing only
  -- needs a refresh -- no disk reload (which would double-apply).
  xivgamepad.refresh_hud()
end

on_buff_gain = function(buff_id)
  if not initialized or player_state.buffs[buff_id] then return end
  player_state.buffs[buff_id] = true
  xivgamepad.refresh_hud()
end

on_buff_loss = function(buff_id)
  if not initialized or not player_state.buffs[buff_id] then return end
  player_state.buffs[buff_id] = nil
  xivgamepad.refresh_hud()
end

on_job_change = function()
  if not initialized then return end
  local player = windower.ffxi.get_player()
  if not player then return end
  player_state.main_job = player.main_job
  player_state.sub_job  = player.sub_job
  job_sets = storage.load_job(windower.addon_path, char_name)
  xivgamepad.refresh_hud()
end

on_status_change = function(status_id)
  if not initialized then return end
  local mounted = status_id == MOUNT_STATUS_ID
  local mount_changed = mounted ~= player_state.is_mounted
  player_state.is_mounted = mounted
  if status_id == EVENT_STATUS_ID then
    if not player_state.in_event then
      player_state.in_event = true
      keyboard.reset()
      gamepad.reset()
      hud.hide()
    end
    return
  end
  if player_state.in_event then
    player_state.in_event = false
    hud.show()
    xivgamepad.refresh_hud()
  elseif mount_changed then
    xivgamepad.refresh_hud()
  end
end

on_zone_change = function()
  if not initialized then return end
  keyboard.reset()
  gamepad.reset()
  reconcile_player_state()
  xivgamepad.refresh_hud()
end

poll_tick = function()
  if unloaded or not initialized or not settings_lib.logged_in() then
    poll_active = false
    return
  end
  reconcile_player_state()
  coroutine.schedule(poll_tick, POLL_INTERVAL)
end

rebuild_player_state = function()
  local player = windower.ffxi.get_player()
  if not player then return end
  local buffs = {}
  for _, buff_id in ipairs(player.buffs or {}) do
    buffs[buff_id] = true
  end
  player_state.buffs      = buffs
  player_state.main_job   = player.main_job
  player_state.sub_job    = player.sub_job
  player_state.is_mounted = player.status == MOUNT_STATUS_ID
  player_state.in_event   = player.status == EVENT_STATUS_ID
end

-- Poll-and-diff reconciliation (Resolved Decision 7): the safety net for
-- buffs already active at login/zone-in that the events miss. Refreshes only
-- when something actually changed.
reconcile_player_state = function()
  local player = windower.ffxi.get_player()
  if not player then return end
  local dirty = false
  local buffs = {}
  for _, buff_id in ipairs(player.buffs or {}) do
    buffs[buff_id] = true
    if not player_state.buffs[buff_id] then
      dirty = true
    end
  end
  for buff_id in pairs(player_state.buffs) do
    if not buffs[buff_id] then
      dirty = true
    end
  end
  local mounted = player.status == MOUNT_STATUS_ID
  local job_changed = player.main_job ~= player_state.main_job
  if job_changed or player.sub_job ~= player_state.sub_job
    or mounted ~= player_state.is_mounted then
    dirty = true
  end
  if not dirty then return end
  player_state.buffs      = buffs
  player_state.main_job   = player.main_job
  player_state.sub_job    = player.sub_job
  player_state.is_mounted = mounted
  if job_changed then
    job_sets = storage.load_job(windower.addon_path, char_name)
  end
  xivgamepad.refresh_hud()
end

resolve_gesture_action = function(id)
  local entry = gestures_by_id[id]
  if entry and entry.action then
    return entry.action
  end
  -- Reserved gesture ids the gamepad module fires directly (execute_slot,
  -- target_previous/next) still resolve when a customized gestures array
  -- omits their entries.
  if action.get_action(id) then
    return id
  end
  return nil
end

restore_binds = function()
  for _, key in ipairs(NOOP_BIND_KEYS) do
    windower.send_command('unbind ' .. key)
  end
end

set_content = function(position)
  local meta = live_settings.sets and live_settings.sets[position]
  if not meta then return nil end
  if meta.source == 'shared' then
    return shared_sets[position]
  end
  local job = player_state.main_job
  if not job then return nil end
  local sets = job_sets[job]
  return sets and sets[position] or nil
end

set_is_empty = function(position)
  local content = set_content(position)
  if not content or type(content.slots) ~= 'table' then return true end
  for index = 1, 16 do
    if content.slots[index] ~= nil then return false end
  end
  return true
end

stage_change = function(key, value)
  if not staged_settings then return end
  settings_lib.stage_set(staged_settings, key, value)
end

stage_hud_position = function(element_id, x, y)
  if not settings_lib.in_setup() or not staged_settings then return end
  local positions = {}
  for id, pos in pairs(staged_settings.hud_positions or {}) do
    positions[id] = pos
  end
  positions[element_id] = { x = x, y = y }
  settings_lib.stage_set(staged_settings, 'hud_positions', positions)
end

start_learn_mode = function()
  if wizard.is_active() then return end
  learn_mode = true
  -- keyboard.set_raw_callback delivers key-DOWN edges only (contract); the
  -- wizard's optional third `pressed` argument is deliberately not supplied.
  -- Down-only feeding leaves captured trigger anchors sticky, which is
  -- physically safe: Steam only emits d-pad chord keys while the anchor is
  -- actually held.
  keyboard.set_raw_callback(function(dik, ctrl_down)
    wizard.on_raw_key(dik, ctrl_down)
  end)
  wizard.start({
    current_mapping = live_settings.key_mapping,
    on_finish       = wizard_finish,
    on_cancel       = wizard_cancel,
    texts           = texts,
    images          = images,
    addon_path      = windower.addon_path,
  })
end

start_poll = function()
  if poll_active then return end
  poll_active = true
  coroutine.schedule(poll_tick, POLL_INTERVAL)
end

switch_set = function(n)
  if type(n) ~= 'number' or n < 1 or n > 8 or n % 1 ~= 0 then
    log.error('switch_set: invalid set position %s', tostring(n))
    return
  end
  if live_settings.active_set ~= n then
    live_settings.active_set = n
    commit_live({ 'active_set' })
  end
  xivgamepad.refresh_hud()
end

toggle_binder = function()
  binder.toggle({
    active_set   = live_settings.active_set,
    display_mode = current_display,
    mode         = live_settings.current_mode,
  })
  binder_mode = binder.is_open()
end

toggle_mode = function()
  local new_mode = live_settings.current_mode == 'job' and 'shared' or 'job'
  live_settings.current_mode = new_mode
  local first_valid, first_any
  for position = 1, 8 do
    local meta = live_settings.sets and live_settings.sets[position]
    if meta and meta.source == new_mode then
      first_any = first_any or position
      if not first_valid and not meta.skip_cycle and not set_is_empty(position) then
        first_valid = position
      end
    end
  end
  live_settings.active_set = first_valid or first_any or live_settings.active_set
  commit_live({ 'current_mode', 'active_set' })
  xivgamepad.refresh_hud()
end

wizard_cancel = function()
  -- Dismissing the first-run offer accepts the shipped mapping: set the
  -- no-repeat-nag flag but leave the mapping itself untouched.
  if not wizard_teardown
    and live_settings and not live_settings.key_mapping_complete
    and settings_lib.logged_in() and not settings_lib.in_setup() then
    live_settings.key_mapping_complete = true
    live_settings = settings_lib.commit(live_settings, windower.addon_path)
    hud.init(hud_opts())
    log.info('Keeping the current key mapping; run //xg learn to reopen the wizard')
  end
  exit_learn_mode()
end

wizard_finish = function(new_mapping)
  if settings_lib.in_setup() and staged_settings then
    settings_lib.stage_set(staged_settings, 'key_mapping', new_mapping)
    settings_lib.stage_set(staged_settings, 'key_mapping_complete', true)
  elseif settings_lib.logged_in() then
    live_settings.key_mapping = new_mapping
    live_settings.key_mapping_complete = true
    live_settings = settings_lib.commit(live_settings, windower.addon_path)
    hud.init(hud_opts())
  end
  keyboard.configure(new_mapping)
  exit_learn_mode()
end

host = {
  cycle_set        = function() cycle_set() end,
  execute_slot     = function(display_mode, slot) execute_slot(display_mode, slot) end,
  get_player_state = function() return player_state end,
  hide_display     = function()
    current_display = nil
    hud.set_display(nil)
    xivgamepad.refresh_hud()
  end,
  open_binder      = function() toggle_binder() end,
  show_display     = function(mode)
    current_display = mode
    hud.set_display(mode)
    xivgamepad.refresh_hud()
  end,
  switch_set       = function(n) switch_set(n) end,
  toggle_mode      = function() toggle_mode() end,
}

commands = {
  c         = function() xivgamepad.setup_open() end,
  config    = function() xivgamepad.setup_open() end,
  d         = function() xivgamepad.setup_close_discard() end,
  dbg       = function(arg) xivgamepad.cmd_debugmode(arg) end,
  debugmode = function(arg) xivgamepad.cmd_debugmode(arg) end,
  discard   = function() xivgamepad.setup_close_discard() end,
  help      = function() xivgamepad.print_help() end,
  l         = function(sub) xivgamepad.cmd_learn(sub) end,
  learn     = function(sub) xivgamepad.cmd_learn(sub) end,
  -- Silent target of the load-time 'bind <key> xivgamepad noop' commands.
  noop      = function() end,
  s         = function() xivgamepad.setup_close_save() end,
  save      = function() xivgamepad.setup_close_save() end,
  t         = function() xivgamepad.cmd_test() end,
  test      = function() xivgamepad.cmd_test() end,
}

windower.register_event('load', function()
  xivgamepad.on_load()
end)

windower.register_event('login', function()
  xivgamepad.init()
end)

windower.register_event('logout', function()
  xivgamepad.on_logout()
end)

windower.register_event('unload', function()
  xivgamepad.on_unload()
end)

windower.register_event('addon command', function(cmd, ...)
  xivgamepad.dispatch(cmd, ...)
end)

windower.register_event('keyboard', function(dik, pressed)
  keyboard.on_key(dik, pressed)
end)

windower.register_event('mouse', function(mtype, x, y, delta, blocked)
  return xivgamepad.on_mouse(mtype, x, y, delta)
end)

windower.register_event('prerender', function()
  if initialized then
    hud.tick()
  end
end)

windower.register_event('gain buff', function(buff_id)
  on_buff_gain(buff_id)
end)

windower.register_event('lose buff', function(buff_id)
  on_buff_loss(buff_id)
end)

windower.register_event('job change', function()
  on_job_change()
end)

windower.register_event('status change', function(status_id)
  on_status_change(status_id)
end)

windower.register_event('zone change', function()
  on_zone_change()
end)

return xivgamepad
