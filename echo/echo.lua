local settings_lib = require('../../lib/settings')
local texts        = require('texts')

_addon.name     = 'Echo'
_addon.author   = 'Windower Addons'
_addon.version  = '1.0.0'
_addon.commands = {'echo', 'ec'}

local defaults = {
  text  = '',
  pos_x = 0,
  pos_y = 0,
}

local live_settings
local staged_settings
local element

local echo = {}

local commands
local on_load
local on_logout
local on_mouse
local print_help
local refresh_display

-- Public functions (alphabetical)

function echo.change_pos(x, y)
  settings_lib.stage_set(staged_settings, 'pos_x', x)
  settings_lib.stage_set(staged_settings, 'pos_y', y)
  element:pos(x, y)
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

function echo.gui_close(flag)
  if flag == '-d' then
    echo.setup_close_discard()
  else
    echo.setup_close_save()
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
  element:draggable(false)
  refresh_display(live_settings.text, live_settings.pos_x, live_settings.pos_y)
  element:show()
end

function echo.setup_close_discard()
  settings_lib.discard()
  staged_settings = nil
  element:draggable(false)
  refresh_display(live_settings.text, live_settings.pos_x, live_settings.pos_y)
end

function echo.setup_close_save()
  live_settings   = settings_lib.commit(staged_settings, windower.addon_path)
  staged_settings = nil
  element:draggable(false)
  refresh_display(live_settings.text, live_settings.pos_x, live_settings.pos_y)
end

function echo.setup_open()
  staged_settings = settings_lib.open_setup(live_settings)
  element:draggable(true)
end

-- Private functions (alphabetical)

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
end

-- The element is moved live by Windower's built-in draggable (toggled via
-- element:draggable(true) in setup_open). on_mouse only PERSISTS the final
-- position to staged settings on mouse-up; that is why it reads
-- element:pos_x()/pos_y() rather than the event x,y.
function echo.on_mouse(mtype, x, y)
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
  windower.add_to_chat(207, '//ec setup        - Open the positioning GUI (drag to reposition)')
  windower.add_to_chat(207, '//ec exit         - Save position changes and close setup')
  windower.add_to_chat(207, '//ec exit -d      - Discard position changes and close setup')
  windower.add_to_chat(207, '//ec help         - Show this command list')
end

function echo.refresh_display(text, x, y)
  element:text(text or '')
  element:pos(x or 0, y or 0)
end

-- Test-only accessors

function echo.get_element()
  return element
end

function echo.get_live()
  return live_settings
end

function echo.get_staged()
  return staged_settings
end

on_load         = echo.on_load
on_logout       = echo.on_logout
on_mouse        = echo.on_mouse
print_help      = echo.print_help
refresh_display = echo.refresh_display

commands = {
  clear = function() echo.cmd_clear() end,
  exit  = function(...) echo.gui_close(...) end,
  help  = function() echo.print_help() end,
  set   = function(...)
    if select('#', ...) == 0 then
      echo.print_help()
    else
      echo.cmd_set(table.concat({...}, ' '))
    end
  end,
  setup = function() echo.setup_open() end,
}

windower.register_event('load',   function() echo.on_load() end)
windower.register_event('login',  function() echo.init() end)
windower.register_event('logout', function() echo.on_logout() end)

windower.register_event('unload', function()
  if element then
    element:destroy()
  end
end)

windower.register_event('addon command', function(cmd, ...)
  echo.dispatch(cmd, ...)
end)

windower.register_event('mouse', function(mtype, x, y, delta, blocked)
  return echo.on_mouse(mtype, x, y)
end)

return echo
