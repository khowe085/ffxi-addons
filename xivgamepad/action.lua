-- Action module: binding-type registry, system-action registry, overlay-type
-- registry, overlay resolver, and execution engine. All game effects go
-- through windower.send_command; display/hotbar effects go through the
-- main-injected host. No settings reads, no windower event registrations.

local log = require('xivgamepad.log')

local action = {}

local actions       = {}
local host          = nil
local overlay_types = {}
local types         = {}

local call_host
local has_action
local has_buff
local is_scholar
local register_builtin_actions
local register_builtin_overlay_types
local register_builtin_types
local setkey_chord
local setkey_press
local target_of

function action._get_overlay_type(name)
  return action.get_overlay_type(name)
end

function action._get_type(code)
  return types[code]
end

function action.execute_binding(binding, ctx)
  if binding == nil then return end
  local def = types[binding.type]
  if def == nil then
    log.error('xivgamepad: unknown binding type: %s', tostring(binding.type))
    return
  end
  def.execute(binding, ctx)
end

function action.get_action(name)
  return actions[name]
end

function action.get_overlay_type(name)
  return overlay_types[name]
end

function action.list_actions()
  local names = {}
  for name in pairs(actions) do
    names[#names + 1] = name
  end
  table.sort(names)
  local list = {}
  for i = 1, #names do
    local def = actions[names[i]]
    list[i] = { name = names[i], description = def.description, icon = def.icon }
  end
  return list
end

function action.list_overlay_types()
  local names = {}
  for name in pairs(overlay_types) do
    names[#names + 1] = name
  end
  table.sort(names)
  return names
end

function action.register_action(name, def)
  if type(name) ~= 'string' or type(def) ~= 'table' or type(def.run) ~= 'function' then
    error('register_action requires a name string and a def table with a run function', 2)
  end
  actions[name] = def
end

function action.register_overlay_type(name, def)
  if type(name) ~= 'string' or type(def) ~= 'table'
      or type(def.check) ~= 'function' or type(def.is_available) ~= 'function' then
    error('register_overlay_type requires a name string and a def table with '
      .. 'check and is_available functions', 2)
  end
  overlay_types[name] = def
end

function action.register_type(code, def)
  if type(code) ~= 'string' or type(def) ~= 'table' or type(def.execute) ~= 'function' then
    error('register_type requires a code string and a def table with an execute function', 2)
  end
  types[code] = def
end

function action.resolve_binding(slot, player_state)
  if slot == nil then return nil end
  -- Hand-edited JSON can put anything in overlays; this runs on every HUD
  -- refresh, so malformed data must degrade to the base binding, not raise.
  local overlays = slot.overlays
  if type(overlays) == 'table' then
    for i = 1, #overlays do
      local entry = overlays[i]
      if type(entry) ~= 'table' then
        log.debug('xivgamepad: skipping malformed overlay entry: %s', tostring(entry))
      else
        local def = overlay_types[entry.overlay_type]
        if def == nil then
          log.debug('xivgamepad: unknown overlay type: %s', tostring(entry.overlay_type))
        elseif def.check(entry.condition or {}, player_state) then
          return entry
        end
      end
    end
  end
  return slot
end

function action.run_action(name_or_command, ctx, params)
  if type(name_or_command) ~= 'string' then
    log.error('xivgamepad: unknown action: %s', tostring(name_or_command))
    return
  end
  local def = actions[name_or_command]
  if def ~= nil then
    def.run(ctx, params or {})
    return
  end
  windower.send_command(name_or_command)
end

function action.set_host(new_host)
  host = new_host
end

call_host = function(method, ...)
  if host == nil or type(host[method]) ~= 'function' then
    log.error('xivgamepad: no host handler for %s', tostring(method))
    return
  end
  return host[method](...)
end

has_action = function(binding)
  if type(binding.action) == 'string' then return true end
  log.error('xivgamepad: %s binding is missing its action', tostring(binding.type))
  return false
end

has_buff = function(player_state, buff_id)
  return player_state ~= nil
    and player_state.buffs ~= nil
    and player_state.buffs[buff_id] == true
end

is_scholar = function(player_state)
  return player_state ~= nil
    and (player_state.main_job == 'SCH' or player_state.sub_job == 'SCH')
end

register_builtin_actions = function()
  local displays = {
    activate_xhb_l          = { mode = 'xhb_l',        description = 'Show XHB-L (current set, left half)' },
    activate_xhb_r          = { mode = 'xhb_r',        description = 'Show XHB-R (current set, right half)' },
    activate_wxhb_l         = { mode = 'wxhb_l',       description = 'Show WXHB-L (assigned set and half)' },
    activate_wxhb_r         = { mode = 'wxhb_r',       description = 'Show WXHB-R (assigned set and half)' },
    activate_expanded_lt_rt = { mode = 'expand_lt_rt', description = 'Show the Expanded LT-to-RT view' },
    activate_expanded_rt_lt = { mode = 'expand_rt_lt', description = 'Show the Expanded RT-to-LT view' },
  }
  for name, def in pairs(displays) do
    action.register_action(name, {
      description = def.description,
      run = function() call_host('show_display', def.mode) end,
    })
  end

  action.register_action('execute_slot', {
    description = 'Fire the addressed slot of the active display',
    run = function(ctx, params) call_host('execute_slot', params.display_mode, params.slot) end,
  })
  action.register_action('cycle_set', {
    description = 'Advance to the next set in the current pool',
    run = function() call_host('cycle_set') end,
  })
  for n = 1, 8 do
    action.register_action('switch_set_' .. n, {
      description = 'Jump directly to set ' .. n,
      run = function() call_host('switch_set', n) end,
    })
  end
  action.register_action('mode_switch', {
    description = 'Toggle shared/job mode; dismounts if mounted',
    run = function(ctx)
      local player_state = ctx and ctx.player_state
      if player_state and player_state.is_mounted then
        action.run_action('dismount', ctx)
      else
        call_host('toggle_mode')
      end
    end,
  })
  action.register_action('toggle_mode', {
    description = 'Toggle the shared/job cycling pool',
    run = function() call_host('toggle_mode') end,
  })
  action.register_action('open_binder', {
    description = 'Toggle the binder open/closed',
    run = function() call_host('open_binder') end,
  })

  -- auto_run/dismount use FFXI's own slash commands. target_previous/next
  -- have no slash-command equivalent, so they synthesize the client's
  -- default keyboard target-cycle keys (Tab / Shift+Tab); in-game
  -- verification is integration plan block 8.
  action.register_action('auto_run', {
    description = 'Toggle auto-run',
    run = function() windower.send_command('input /autorun') end,
  })
  action.register_action('dismount', {
    description = 'Dismount the current mount',
    run = function() windower.send_command('input /dismount') end,
  })
  action.register_action('target_previous', {
    description = 'Select the previous target in the cycle',
    run = function() setkey_chord('lshift', 'tab') end,
  })
  action.register_action('target_next', {
    description = 'Select the next target in the cycle',
    run = function() setkey_press('tab') end,
  })

  local synth = {
    menu_confirm = { token = 'enter',   description = 'Confirm / open chat' },
    menu_cancel  = { token = 'escape',  description = 'Cancel / back out' },
    menu_open    = { token = 'numpad-', description = 'Open the main menu' },
    menu_focus   = { token = 'numpad+', description = 'Focus the active window' },
    zoom_in      = { token = '.',       description = 'Camera zoom in' },
    zoom_out     = { token = ',',       description = 'Camera zoom out' },
  }
  for name, def in pairs(synth) do
    action.register_action(name, {
      description = def.description,
      run = function() setkey_press(def.token) end,
    })
  end

  local wrappers = {
    jump    = { command = 'input /jump',    description = 'Jump' },
    map     = { command = 'input /map',     description = 'Open the map' },
    case    = { command = 'input /case',    description = 'Open the Case' },
    satchel = { command = 'input /satchel', description = 'Open the Satchel' },
    sack    = { command = 'input /sack',    description = 'Open the Sack' },
    ward1   = { command = 'input /ward1',   description = 'Open Ward 1' },
    ward2   = { command = 'input /ward2',   description = 'Open Ward 2' },
  }
  for name, def in pairs(wrappers) do
    action.register_action(name, {
      description = def.description,
      icon        = 'item',
      run = function() windower.send_command(def.command) end,
    })
  end
  action.register_action('inventory', {
    description = 'Open Inventory',
    icon        = 'item',
    run = function() setkey_chord('lctrl', 'i') end,
  })
  action.register_action('equipment', {
    description = 'Open Equipment',
    icon        = 'item',
    run = function() setkey_chord('lctrl', 'e') end,
  })
end

register_builtin_overlay_types = function()
  action.register_overlay_type('subjob', {
    check = function(condition, player_state)
      return condition.subjob ~= nil
        and player_state ~= nil
        and player_state.sub_job == condition.subjob
    end,
    is_available = function(player_state)
      return player_state ~= nil and player_state.sub_job ~= nil
    end,
  })

  local arts = {
    light_arts     = 358,
    dark_arts      = 359,
    addendum_white = 401,
    addendum_black = 402,
  }
  for name, buff_id in pairs(arts) do
    action.register_overlay_type(name, {
      check        = function(condition, player_state) return has_buff(player_state, buff_id) end,
      is_available = is_scholar,
    })
  end
end

register_builtin_types = function()
  local named = {
    ma   = 'ma',
    ja   = 'ja',
    ws   = 'ws',
    pet  = 'pet',
    item = 'item',
  }
  for code, slash in pairs(named) do
    action.register_type(code, {
      describe = function(binding) return binding.alias or binding.action end,
      execute = function(binding)
        if not has_action(binding) then return end
        windower.send_command('input /' .. slash .. ' "' .. binding.action .. '" ' .. target_of(binding))
      end,
    })
  end

  action.register_type('a', {
    describe = function(binding) return binding.alias or 'Attack' end,
    execute = function(binding)
      windower.send_command('input /attack ' .. target_of(binding))
    end,
  })
  action.register_type('ra', {
    describe = function(binding) return binding.alias or 'Ranged Attack' end,
    execute = function(binding)
      windower.send_command('input /ra ' .. target_of(binding))
    end,
  })
  action.register_type('ta', {
    describe = function(binding) return binding.alias or 'Switch Target' end,
    execute = function(binding)
      windower.send_command('input /ta ' .. target_of(binding))
    end,
  })
  action.register_type('mount', {
    describe = function(binding) return binding.alias or binding.action end,
    execute = function(binding)
      if not has_action(binding) then return end
      windower.send_command('input /mount "' .. binding.action .. '"')
    end,
  })
  action.register_type('map', {
    describe = function() return 'View Map' end,
    execute = function()
      windower.send_command('input /map')
    end,
  })
  action.register_type('ct', {
    describe = function(binding) return binding.alias or binding.action end,
    execute = function(binding)
      if not has_action(binding) then return end
      windower.send_command(binding.action)
    end,
  })
  action.register_type('ex', {
    describe = function(binding) return binding.alias or binding.action end,
    execute = function(binding)
      if not has_action(binding) then return end
      call_host('show_display', binding.action)
    end,
  })
  action.register_type('noop', {
    describe = function() return '' end,
    execute = function() end,
  })
end

setkey_chord = function(modifier, token)
  windower.send_command('setkey ' .. modifier .. ' down')
  windower.send_command('setkey ' .. token .. ' down')
  windower.send_command('setkey ' .. token .. ' up')
  windower.send_command('setkey ' .. modifier .. ' up')
end

setkey_press = function(token)
  windower.send_command('setkey ' .. token .. ' down')
  windower.send_command('setkey ' .. token .. ' up')
end

target_of = function(binding)
  return '<' .. (binding.target or 't') .. '>'
end

register_builtin_actions()
register_builtin_overlay_types()
register_builtin_types()

return action
