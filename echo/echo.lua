local settings_lib = require('lib.settings.settings')
local config_gui   = require('lib.settings.config_gui')
local texts        = require('texts')
local images       = require('images')

_addon.name     = 'Echo'
_addon.author   = 'Windower Addons'
_addon.version  = '1.0.0'
_addon.commands = {'echo', 'ec'}

local defaults = {
  text     = '',
  pos_x    = 0,
  pos_y    = 0,
  config_x = 100,
  config_y = 100,
}

local live_settings
local staged_settings
local element
local gui

local echo = {}

local build_tabs
local commands
local on_load
local on_logout
local on_mouse
local print_help
local refresh_display
local stage_config_pos

-- Public functions (alphabetical)

function echo.change_pos(x, y)
  settings_lib.stage_set(staged_settings, 'pos_x', x)
  settings_lib.stage_set(staged_settings, 'pos_y', y)
  element:pos(x, y)
  if gui then
    gui:set_tabs(build_tabs(staged_settings))
  end
end

function echo.cmd_clear()
  echo.cmd_set('')
end

function echo.cmd_set(text)
  if settings_lib.in_setup() then
    settings_lib.stage_set(staged_settings, 'text', text)
    refresh_display(text, staged_settings.pos_x, staged_settings.pos_y)
  else
    live_settings.text = text
    local tmp     = settings_lib.open_setup(live_settings)
    live_settings = settings_lib.commit(tmp, windower.addon_path)
    refresh_display(live_settings.text, live_settings.pos_x, live_settings.pos_y)
  end
end

function echo.dispatch(cmd, ...)
  local handler = commands[cmd]
  if handler then
    handler(...)
  else
    echo.print_help()
  end
end

function echo.init()
  if settings_lib.in_setup() then
    settings_lib.discard()
    staged_settings = nil
  end
  live_settings = settings_lib.load(windower.addon_path, defaults)
  if not element then
    element = texts.new('', {
      pos   = { x = live_settings.pos_x, y = live_settings.pos_y },
      text  = { size = 12, font = 'Arial' },
      flags = { draggable = false },
    })
  end
  if not gui then
    gui = config_gui.new({
      texts      = texts,
      images     = images,
      title      = _addon.name,
      on_save    = echo.setup_close_save,
      on_discard = echo.setup_close_discard,
      on_move    = stage_config_pos,
      pos        = { x = live_settings.config_x, y = live_settings.config_y },
      size       = { width = 320, height = 160 },
    })
  end
  gui:set_draggable(false)
  gui:hide()
  element:draggable(false)
  refresh_display(live_settings.text, live_settings.pos_x, live_settings.pos_y)
  element:show()
end

function echo.setup_close_discard()
  settings_lib.discard()
  staged_settings = nil
  element:draggable(false)
  refresh_display(live_settings.text, live_settings.pos_x, live_settings.pos_y)
  if gui then
    gui:set_draggable(false)
    gui:hide()
  end
end

function echo.setup_close_save()
  live_settings   = settings_lib.commit(staged_settings, windower.addon_path)
  staged_settings = nil
  element:draggable(false)
  refresh_display(live_settings.text, live_settings.pos_x, live_settings.pos_y)
  if gui then
    gui:set_draggable(false)
    gui:hide()
  end
end

function echo.setup_open()
  if gui and gui:is_open() then return end
  staged_settings = settings_lib.open_setup(live_settings)
  if staged_settings.text == nil or staged_settings.text == '' then
    settings_lib.stage_set(staged_settings, 'text', 'SAMPLE TEXT')
  end
  refresh_display(staged_settings.text, staged_settings.pos_x, staged_settings.pos_y)
  element:draggable(true)
  if gui then
    gui:set_pos(staged_settings.config_x, staged_settings.config_y)
    gui:set_draggable(true)
    gui:show(build_tabs(staged_settings))
  end
end

-- Private functions (alphabetical)

function echo.build_tabs(s)
  return {
    {
      title = 'General',
      lines = {
        'Text:  ' .. tostring(s.text or ''),
        'pos_x: ' .. tostring(s.pos_x or 0),
        'pos_y: ' .. tostring(s.pos_y or 0),
        'Drag the text to set its position; drag this window\'s',
        'header to move it. Saved on Save.',
      },
    },
  }
end

function echo.on_load()
  if settings_lib.logged_in() then
    echo.init()
  end
end

function echo.on_logout()
  if settings_lib.in_setup() then
    settings_lib.discard()
    staged_settings = nil
  end
  if element then
    element:draggable(false)
    element:hide()
  end
  if gui then
    gui:set_draggable(false)
    gui:hide()
  end
end

-- The element is moved live by Windower's built-in draggable (toggled via
-- element:draggable(true) in setup_open). on_mouse first lets the config window
-- consume any event over its bounds (so clicks never reach the game); only when
-- the cursor is outside the window does it PERSIST the overlay's final position
-- to staged settings on mouse-up, reading element:pos_x()/pos_y() rather than
-- the event x,y.
function echo.on_mouse(mtype, x, y, delta)
  if gui and gui:is_open() then
    if gui:handle_mouse(mtype, x, y, delta) then
      return true
    end
  end
  if not settings_lib.in_setup() then return false end
  if mtype == 2 then
    echo.change_pos(element:pos_x(), element:pos_y())
  end
  return false
end

function echo.print_help()
  windower.add_to_chat(207, 'Echo commands:')
  windower.add_to_chat(207, '//ec set <text>   - Set and display the text')
  windower.add_to_chat(207, '//ec clear        - Clear the displayed text')
  windower.add_to_chat(207, '//ec config       - Open the config window (drag overlay/header; Save/Discard)')
  windower.add_to_chat(207, '//ec save         - Save changes and close the config window')
  windower.add_to_chat(207, '//ec discard      - Discard changes and close the config window')
  windower.add_to_chat(207, '//ec help         - Show this command list')
end

function echo.refresh_display(text, x, y)
  element:text(text or '')
  element:pos(x or 0, y or 0)
end

function echo.stage_config_pos(x, y)
  settings_lib.stage_set(staged_settings, 'config_x', x)
  settings_lib.stage_set(staged_settings, 'config_y', y)
end

-- Test-only accessors

function echo.get_element()
  return element
end

function echo.get_gui()
  return gui
end

function echo.get_live()
  return live_settings
end

function echo.get_staged()
  return staged_settings
end

build_tabs       = echo.build_tabs
on_load          = echo.on_load
on_logout        = echo.on_logout
on_mouse         = echo.on_mouse
print_help       = echo.print_help
refresh_display  = echo.refresh_display
stage_config_pos = echo.stage_config_pos

commands = {
  c       = function() echo.setup_open() end,
  clear   = function() echo.cmd_clear() end,
  config  = function() echo.setup_open() end,
  d       = function() echo.setup_close_discard() end,
  discard = function() echo.setup_close_discard() end,
  help    = function() echo.print_help() end,
  s       = function() echo.setup_close_save() end,
  save    = function() echo.setup_close_save() end,
  set     = function(...)
    if select('#', ...) == 0 then
      echo.print_help()
    else
      echo.cmd_set(table.concat({...}, ' '))
    end
  end,
}

windower.register_event('load',   function() echo.on_load() end)
windower.register_event('login',  function() echo.init() end)
windower.register_event('logout', function() echo.on_logout() end)

windower.register_event('unload', function()
  if element then
    element:destroy()
  end
  if gui then
    gui:destroy()
  end
end)

windower.register_event('addon command', function(cmd, ...)
  echo.dispatch(cmd, ...)
end)

windower.register_event('mouse', function(mtype, x, y, delta, blocked)
  return echo.on_mouse(mtype, x, y, delta)
end)

return echo
