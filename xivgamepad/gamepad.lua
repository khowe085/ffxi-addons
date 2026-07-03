local log = require('log')

local DEFAULT_MAX_GAP     = 0.33
local DEFAULT_MAX_HOLD    = 0.25
local DEFAULT_MIN_HOLD    = 0.12
local DEFAULT_ANCHOR_HOLD = 0.12

local SLOT_INDEX = {
  DPAD_UP = 1, DPAD_RIGHT = 2, DPAD_DOWN = 3, DPAD_LEFT = 4,
  A = 5, B = 6, X = 7, Y = 8,
}

local DIRECT_SWITCH_ORDER = {
  'DPAD_UP', 'DPAD_RIGHT', 'DPAD_DOWN', 'DPAD_LEFT', 'A', 'B', 'X', 'Y',
}

local DISPLAY_ACTIONS = {
  activate_xhb_l          = true,
  activate_xhb_r          = true,
  activate_wxhb_l         = true,
  activate_wxhb_r         = true,
  activate_expanded_lt_rt = true,
  activate_expanded_rt_lt = true,
}

local REQUIRED_ANCHOR = {
  activate_wxhb_l         = 'LT',
  activate_wxhb_r         = 'RT',
  activate_expanded_lt_rt = 'LT',
  activate_expanded_rt_lt = 'RT',
}

local XHB_FOR_TRIGGER = { LT = 'xhb_l', RT = 'xhb_r' }

local CONTEXT_ANCHORS = {
  trigger_held = { 'LT', 'RT' },
  rb_held      = { 'RB' },
  lb_held      = { 'LB' },
}

local anchor_thresholds  = {}
local display            = { mode = nil, anchor = nil, second = nil, kind = nil }
local display_callback
local entry_index        = {}
local gesture_callback
local held               = {}
local pending_double     = {}
local pending_double_seq = 0
local pendings           = {}
local schedule
local session_seq        = 0
local target_thresholds  = {
  previous = DEFAULT_ANCHOR_HOLD,
  next     = DEFAULT_ANCHOR_HOLD,
}
local xhb_rules          = {
  LT = { id = 'xhb_l', type = 'hold', action = 'activate_xhb_l', params = { min_hold = DEFAULT_MIN_HOLD } },
  RT = { id = 'xhb_r', type = 'hold', action = 'activate_xhb_r', params = { min_hold = DEFAULT_MIN_HOLD } },
}

local gamepad = {}

local arm_double_second
local arm_hold
local arm_pending
local arm_tap
local compute_context
local dispatch_entry
local engage_display
local fire_gesture
local handle_press
local handle_release
local mark_modifiers
local maybe_fallback
local params_for
local qualifying_anchor
local release_display
local schedule_thresholds
local set_display
local try_engage

-- Public functions (alphabetical)

function gamepad.default_gestures()
  local function entry(id, gesture_type, button, context, action, params)
    return {
      id = id, type = gesture_type, button = button,
      context = context, action = action, params = params,
    }
  end
  local defaults = {
    entry('xhb_l', 'hold', 'LT', 'bare', 'activate_xhb_l', { min_hold = DEFAULT_MIN_HOLD }),
    entry('xhb_r', 'hold', 'RT', 'bare', 'activate_xhb_r', { min_hold = DEFAULT_MIN_HOLD }),
    entry('wxhb_l_paddle', 'hold_then_hold', 'L4', 'trigger_held', 'activate_wxhb_l',
      { min_hold_first = DEFAULT_MIN_HOLD, min_hold_second = DEFAULT_MIN_HOLD }),
    entry('wxhb_r_paddle', 'hold_then_hold', 'R4', 'trigger_held', 'activate_wxhb_r',
      { min_hold_first = DEFAULT_MIN_HOLD, min_hold_second = DEFAULT_MIN_HOLD }),
    entry('wxhb_l_tap', 'double_tap', 'LT', 'bare', 'activate_wxhb_l',
      { max_gap = DEFAULT_MAX_GAP, min_hold = DEFAULT_MIN_HOLD }),
    entry('wxhb_r_tap', 'double_tap', 'RT', 'bare', 'activate_wxhb_r',
      { max_gap = DEFAULT_MAX_GAP, min_hold = DEFAULT_MIN_HOLD }),
    entry('expand_lt_rt', 'hold_then_hold', 'RT', 'trigger_held', 'activate_expanded_lt_rt',
      { min_hold_first = DEFAULT_MIN_HOLD, min_hold_second = DEFAULT_MIN_HOLD }),
    entry('expand_rt_lt', 'hold_then_hold', 'LT', 'trigger_held', 'activate_expanded_rt_lt',
      { min_hold_first = DEFAULT_MIN_HOLD, min_hold_second = DEFAULT_MIN_HOLD }),
    entry('auto_run', 'tap', 'LB', 'bare', 'auto_run', { max_hold = DEFAULT_MAX_HOLD }),
    entry('cycle_set', 'tap', 'RB', 'bare', 'cycle_set', { max_hold = DEFAULT_MAX_HOLD }),
    entry('mode_switch', 'hold_then_press', 'RB', 'lb_held', 'mode_switch',
      { min_anchor_hold = DEFAULT_ANCHOR_HOLD }),
    entry('target_previous', 'hold_then_press', 'LB', 'trigger_held', 'target_previous',
      { min_anchor_hold = DEFAULT_ANCHOR_HOLD }),
    entry('target_next', 'hold_then_press', 'RB', 'trigger_held', 'target_next',
      { min_anchor_hold = DEFAULT_ANCHOR_HOLD }),
  }
  for n, button in ipairs(DIRECT_SWITCH_ORDER) do
    defaults[#defaults + 1] = entry('direct_switch_' .. n, 'button', button, 'rb_held',
      'switch_set_' .. n, {})
  end
  defaults[#defaults + 1] = entry('execute_slot', 'button', nil, 'trigger_held', 'execute_slot', {})
  defaults[#defaults + 1] = entry('open_binder', 'button', 'BACK', 'trigger_held', 'open_binder', {})
  defaults[#defaults + 1] = entry('bare_a', 'button', 'A', 'bare', 'menu_confirm', {})
  defaults[#defaults + 1] = entry('bare_b', 'button', 'B', 'bare', 'menu_cancel', {})
  defaults[#defaults + 1] = entry('bare_x', 'button', 'X', 'bare', 'map', {})
  defaults[#defaults + 1] = entry('bare_y', 'button', 'Y', 'bare', 'jump', {})
  defaults[#defaults + 1] = entry('bare_start', 'button', 'START', 'bare', 'menu_open', {})
  defaults[#defaults + 1] = entry('bare_back', 'button', 'BACK', 'bare', 'menu_focus', {})
  return defaults
end

function gamepad.get_display_mode()
  return display.mode
end

function gamepad.init(opts)
  if not opts or type(opts.schedule) ~= 'function' then
    log.error('gamepad.init requires a schedule function')
    schedule = nil
    return
  end
  schedule = opts.schedule
end

function gamepad.on_button_event(name, pressed)
  if not schedule then
    log.error('gamepad.on_button_event before init; event dropped')
    return
  end
  if pressed then
    handle_press(name)
  else
    handle_release(name)
  end
end

function gamepad.reset()
  held           = {}
  pendings       = {}
  pending_double = {}
  if display.mode ~= nil then
    set_display(nil, nil, nil, nil)
  else
    display.anchor = nil
    display.second = nil
    display.kind   = nil
  end
end

function gamepad.set_display_callback(fn)
  display_callback = fn
end

function gamepad.set_gesture_callback(fn)
  gesture_callback = fn
end

function gamepad.set_gestures(gestures)
  entry_index       = {}
  anchor_thresholds = {}
  target_thresholds = {
    previous = DEFAULT_ANCHOR_HOLD,
    next     = DEFAULT_ANCHOR_HOLD,
  }
  xhb_rules         = {
    LT = { id = 'xhb_l', type = 'hold', action = 'activate_xhb_l', params = { min_hold = DEFAULT_MIN_HOLD } },
    RT = { id = 'xhb_r', type = 'hold', action = 'activate_xhb_r', params = { min_hold = DEFAULT_MIN_HOLD } },
  }
  local function add_threshold(button, value)
    local set = anchor_thresholds[button]
    if not set then
      set = {}
      anchor_thresholds[button] = set
    end
    set[value] = true
  end
  for _, entry in ipairs(gestures or {}) do
    local reserved = entry.context == 'trigger_held' and entry.button ~= nil
      and (SLOT_INDEX[entry.button] ~= nil or entry.button == 'LB' or entry.button == 'RB')
    local xhb_trigger
    if entry.type == 'hold'
      and ((entry.button == 'LT' and entry.action == 'activate_xhb_l')
        or (entry.button == 'RT' and entry.action == 'activate_xhb_r')) then
      xhb_trigger = entry.button
    end
    if reserved then
      if entry.type == 'hold_then_press' then
        local threshold = (entry.params and entry.params.min_anchor_hold) or DEFAULT_ANCHOR_HOLD
        if entry.button == 'LB' then
          target_thresholds.previous = threshold
        elseif entry.button == 'RB' then
          target_thresholds.next = threshold
        end
      end
    elseif xhb_trigger then
      xhb_rules[xhb_trigger].params.min_hold =
        (entry.params and entry.params.min_hold) or DEFAULT_MIN_HOLD
    elseif entry.button then
      local by_context = entry_index[entry.button]
      if not by_context then
        by_context = {}
        entry_index[entry.button] = by_context
      end
      local list = by_context[entry.context]
      if not list then
        list = {}
        by_context[entry.context] = list
      end
      list[#list + 1] = entry
    end
    local anchors = CONTEXT_ANCHORS[entry.context]
    if anchors then
      local threshold
      if entry.type == 'hold_then_hold' then
        threshold = (entry.params and entry.params.min_hold_first) or DEFAULT_MIN_HOLD
      elseif entry.type == 'hold_then_press' then
        threshold = (entry.params and entry.params.min_anchor_hold) or DEFAULT_ANCHOR_HOLD
      end
      if threshold then
        for _, anchor in ipairs(anchors) do
          add_threshold(anchor, threshold)
        end
      end
    end
  end
  add_threshold('LT', target_thresholds.previous)
  add_threshold('LT', target_thresholds.next)
  add_threshold('RT', target_thresholds.previous)
  add_threshold('RT', target_thresholds.next)
end

-- Private functions (alphabetical)

arm_double_second = function(session, entry)
  local min_hold = (entry.params and entry.params.min_hold) or DEFAULT_MIN_HOLD
  local button   = session.button
  local id       = session.id
  schedule(function()
    local s = held[button]
    if s and s.id == id and not s.double_engaged then
      s.double_engaged = true
      dispatch_entry(entry, button, nil, 'double')
    end
  end, min_hold)
end

arm_hold = function(session, entry)
  local min_hold = (entry.params and entry.params.min_hold) or DEFAULT_MIN_HOLD
  local button   = session.button
  local id       = session.id
  schedule(function()
    local s = held[button]
    if s and s.id == id then
      s.hold_engaged = true
      dispatch_entry(entry, button, nil, 'hold')
    end
  end, min_hold)
end

arm_pending = function(session, entry, ctx)
  local anchors = {}
  for _, candidate in ipairs(CONTEXT_ANCHORS[ctx] or {}) do
    if candidate ~= session.button and held[candidate] then
      anchors[candidate] = held[candidate].id
    end
  end
  local pending = {
    entry      = entry,
    button     = session.button,
    session_id = session.id,
    ctx        = ctx,
    anchors    = anchors,
    min_first  = (entry.params and entry.params.min_hold_first) or DEFAULT_MIN_HOLD,
    b_elapsed  = false,
    engaged    = false,
  }
  pendings[#pendings + 1] = pending
  local min_second = (entry.params and entry.params.min_hold_second) or DEFAULT_MIN_HOLD
  schedule(function()
    pending.b_elapsed = true
    try_engage(pending)
  end, min_second)
end

arm_tap = function(session, entry)
  if session.tap then
    return
  end
  local max_hold = (entry.params and entry.params.max_hold) or DEFAULT_MAX_HOLD
  local button   = session.button
  local id       = session.id
  session.tap = { entry = entry, expired = false }
  schedule(function()
    local s = held[button]
    if s and s.id == id and s.tap then
      s.tap.expired = true
    end
  end, max_hold)
end

compute_context = function()
  if held.LT or held.RT then
    return 'trigger_held'
  end
  if held.RB then
    return 'rb_held'
  end
  if held.LB then
    return 'lb_held'
  end
  return 'bare'
end

dispatch_entry = function(entry, anchor, second, kind)
  if entry.action == 'open_binder'
    and display.mode ~= 'xhb_l' and display.mode ~= 'xhb_r' then
    return
  end
  if DISPLAY_ACTIONS[entry.action] then
    engage_display(entry.action, anchor, second, kind)
  else
    fire_gesture(entry.id, params_for(entry.action))
  end
end

engage_display = function(action, anchor, second, kind)
  if action == 'activate_xhb_l' then
    set_display('xhb_l', anchor or 'LT', nil, nil)
  elseif action == 'activate_xhb_r' then
    set_display('xhb_r', anchor or 'RT', nil, nil)
  elseif action == 'activate_wxhb_l' or action == 'activate_wxhb_r' then
    local required = REQUIRED_ANCHOR[action]
    if anchor ~= required then
      return
    end
    if display.mode ~= nil and display.mode ~= XHB_FOR_TRIGGER[required] then
      return
    end
    local mode = action == 'activate_wxhb_l' and 'wxhb_l' or 'wxhb_r'
    if kind == 'double' then
      set_display(mode, required, nil, 'double')
    else
      set_display(mode, required, second, 'paddle')
    end
  elseif action == 'activate_expanded_lt_rt' or action == 'activate_expanded_rt_lt' then
    local required = REQUIRED_ANCHOR[action]
    if anchor ~= required then
      return
    end
    local other = required == 'LT' and 'RT' or 'LT'
    if not held[required] or not held[other] then
      return
    end
    local mode = action == 'activate_expanded_lt_rt' and 'expand_lt_rt' or 'expand_rt_lt'
    set_display(mode, required, other, nil)
  end
end

fire_gesture = function(id, params)
  log.debug('gesture %s fired', id)
  if gesture_callback then
    gesture_callback(id, params or {})
  end
end

handle_press = function(button)
  if held[button] then
    return
  end
  local ctx = compute_context()
  session_seq = session_seq + 1
  local session = { id = session_seq, button = button, passed = {}, used = false }
  held[button] = session
  mark_modifiers(ctx, button)
  schedule_thresholds(button, session)
  log.debug('press %s in context %s', button, ctx)
  if ctx == 'trigger_held' then
    local slot = SLOT_INDEX[button]
    if slot then
      if display.mode then
        fire_gesture('execute_slot', { display_mode = display.mode, slot = slot })
      end
      return
    end
    if button == 'LB' or button == 'RB' then
      local which = button == 'LB' and 'previous' or 'next'
      local anchor = qualifying_anchor(ctx, target_thresholds[which], nil, button)
      if anchor then
        fire_gesture('target_' .. which, {})
      end
      return
    end
  end
  local double_pending = pending_double[button]
  if double_pending and double_pending.entry.context == ctx then
    pending_double[button] = nil
    session.suppress_hold = true
    session.double_entry = double_pending.entry
    arm_double_second(session, double_pending.entry)
  end
  if XHB_FOR_TRIGGER[button] then
    if ctx == 'trigger_held' then
      local id = session.id
      schedule(function()
        local s = held[button]
        if s and s.id == id then
          s.xhb_ready = true
          maybe_fallback(button)
        end
      end, xhb_rules[button].params.min_hold)
    elseif not session.suppress_hold then
      arm_hold(session, xhb_rules[button])
    end
  end
  local list = entry_index[button] and entry_index[button][ctx]
  if not list then
    return
  end
  for _, entry in ipairs(list) do
    if entry.type == 'button' then
      dispatch_entry(entry, button, nil, nil)
    elseif entry.type == 'tap' then
      arm_tap(session, entry)
    elseif entry.type == 'hold' then
      if not session.suppress_hold then
        arm_hold(session, entry)
      end
    elseif entry.type == 'double_tap' then
      if not session.double_entry then
        session.double_eligible = entry
      end
    elseif entry.type == 'hold_then_hold' then
      arm_pending(session, entry, ctx)
    elseif entry.type == 'hold_then_press' then
      local threshold = (entry.params and entry.params.min_anchor_hold) or DEFAULT_ANCHOR_HOLD
      local anchor = qualifying_anchor(ctx, threshold, nil, button)
      if anchor then
        dispatch_entry(entry, anchor, nil, nil)
      end
    end
  end
end

handle_release = function(button)
  local session = held[button]
  if not session then
    return
  end
  held[button] = nil
  log.debug('release %s', button)
  release_display(button)
  if XHB_FOR_TRIGGER[button] then
    maybe_fallback(button == 'LT' and 'RT' or 'LT')
  end
  if session.tap and not session.tap.expired and not session.used
    and not session.hold_engaged and not session.double_engaged then
    dispatch_entry(session.tap.entry, button, nil, nil)
  end
  local double_entry = session.double_eligible or session.double_entry
  if double_entry and not session.double_engaged then
    pending_double_seq = pending_double_seq + 1
    local token = pending_double_seq
    pending_double[button] = { entry = double_entry, token = token }
    local max_gap = (double_entry.params and double_entry.params.max_gap) or DEFAULT_MAX_GAP
    schedule(function()
      local pd = pending_double[button]
      if pd and pd.token == token then
        pending_double[button] = nil
      end
    end, max_gap)
  end
  for i = #pendings, 1, -1 do
    local pending = pendings[i]
    local owner = held[pending.button]
    if pending.engaged or pending.button == button
      or not owner or owner.id ~= pending.session_id then
      table.remove(pendings, i)
    end
  end
end

mark_modifiers = function(ctx, button)
  local anchors = CONTEXT_ANCHORS[ctx]
  if not anchors then
    return
  end
  for _, anchor in ipairs(anchors) do
    if anchor ~= button and held[anchor] then
      held[anchor].used = true
    end
  end
end

maybe_fallback = function(trigger)
  local session = held[trigger]
  if not session or not session.xhb_ready then
    return
  end
  local other = trigger == 'LT' and 'RT' or 'LT'
  if held[other] or display.mode ~= nil then
    return
  end
  engage_display(trigger == 'LT' and 'activate_xhb_l' or 'activate_xhb_r', trigger, nil, nil)
end

params_for = function(action)
  local set = action and action:match('^switch_set_(%d+)$')
  if set then
    return { set = tonumber(set) }
  end
  return {}
end

qualifying_anchor = function(ctx, threshold, preferred, exclude)
  local anchors = CONTEXT_ANCHORS[ctx]
  if not anchors then
    return nil
  end
  if preferred and preferred ~= exclude then
    local s = held[preferred]
    if s and s.passed[threshold] then
      return preferred
    end
  end
  for _, anchor in ipairs(anchors) do
    if anchor ~= exclude then
      local s = held[anchor]
      if s and s.passed[threshold] then
        return anchor
      end
    end
  end
  return nil
end

release_display = function(button)
  local mode = display.mode
  if not mode then
    return
  end
  if mode == 'xhb_l' or mode == 'xhb_r' then
    if button == display.anchor then
      set_display(nil, nil, nil, nil)
    end
  elseif mode == 'wxhb_l' or mode == 'wxhb_r' then
    if button == display.anchor then
      set_display(nil, nil, nil, nil)
    elseif display.kind == 'paddle' and button == display.second then
      set_display(XHB_FOR_TRIGGER[display.anchor], display.anchor, nil, nil)
    end
  elseif mode == 'expand_lt_rt' or mode == 'expand_rt_lt' then
    if button == display.second then
      set_display(XHB_FOR_TRIGGER[display.anchor], display.anchor, nil, nil)
    elseif button == display.anchor then
      local other = display.second
      set_display(XHB_FOR_TRIGGER[other], other, nil, nil)
    end
  end
end

schedule_thresholds = function(button, session)
  local thresholds = anchor_thresholds[button]
  if not thresholds then
    return
  end
  local id = session.id
  for threshold in pairs(thresholds) do
    schedule(function()
      local s = held[button]
      if s and s.id == id then
        s.passed[threshold] = true
        for _, pending in ipairs(pendings) do
          try_engage(pending)
        end
      end
    end, threshold)
  end
end

set_display = function(mode, anchor, second, kind)
  local changed = display.mode ~= mode
  display.mode   = mode
  display.anchor = anchor
  display.second = second
  display.kind   = kind
  if changed then
    log.debug('display -> %s', tostring(mode))
    if display_callback then
      display_callback(mode)
    end
  end
end

try_engage = function(pending)
  if pending.engaged or not pending.b_elapsed then
    return
  end
  local session = held[pending.button]
  if not session or session.id ~= pending.session_id then
    return
  end
  local function qualified(candidate)
    local expected = pending.anchors[candidate]
    if not expected then
      return false
    end
    local s = held[candidate]
    return s ~= nil and s.id == expected and s.passed[pending.min_first] == true
  end
  local anchor
  local preferred = REQUIRED_ANCHOR[pending.entry.action]
  if preferred and qualified(preferred) then
    anchor = preferred
  else
    for _, candidate in ipairs(CONTEXT_ANCHORS[pending.ctx] or {}) do
      if candidate ~= pending.button and qualified(candidate) then
        anchor = candidate
        break
      end
    end
  end
  if not anchor then
    return
  end
  pending.engaged = true
  dispatch_entry(pending.entry, anchor, pending.button, 'paddle')
end

return gamepad
