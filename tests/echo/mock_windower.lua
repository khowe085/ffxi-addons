-- Stubs for Windower globals required by the echo addon and its tests

_addon = {}

windower = {
  ffxi = {
    -- Tests that change _player must restore it (or reset it in their own setup); fresh() resets it to TestChar.
    _player = { name = 'TestChar' },
    get_player = function() return windower.ffxi._player end,
  },
  addon_path = '/addon/',
  -- Capture registered handlers so lifecycle tests can fire events that the
  -- addon only wires through register_event (e.g. 'unload').
  _events = {},
  register_event = function(name, fn) windower._events[name] = fn end,
  add_to_chat = function(_, msg) table.insert(windower._chat, msg) end,
  _chat = {},
}

texts = {
  new = function(str, settings)
    local el = {
      _text     = str or '',
      _visible  = false,
      _x        = 0,
      _y        = 0,
      _width    = 0,
      _height   = 18,
    }
    if settings and settings.pos then
      el._x = settings.pos.x or 0
      el._y = settings.pos.y or 0
    end
    el.text      = function(self, v) if v ~= nil then self._text = v end return self._text end
    el.pos       = function(self, x, y) self._x = x; self._y = y end
    el.pos_x     = function(self) return self._x end
    el.pos_y     = function(self) return self._y end
    el.draggable = function(self, v) self._draggable = v end
    el.show      = function(self) self._visible = true end
    el.hide      = function(self) self._visible = false end
    el.destroy   = function(self) self._destroyed = true end
    el.hover     = function(self, x, y)
      return x >= self._x and x < self._x + self._width
         and y >= self._y and y < self._y + self._height
    end
    return el
  end,
}

images = {
  new = function(settings)
    local el = {
      _visible = false,
      _x       = 0,
      _y       = 0,
      _width   = 0,
      _height  = 0,
    }
    if settings and settings.pos then
      el._x = settings.pos.x or 0
      el._y = settings.pos.y or 0
    end
    if settings and settings.size then
      el._width  = settings.size.width or 0
      el._height = settings.size.height or 0
    end
    el.pos       = function(self, x, y) self._x = x; self._y = y end
    el.size      = function(self, w, h) self._width = w; self._height = h end
    el.alpha     = function(self, a) self._alpha = a end
    el.color     = function(self, r, g, b) self._color = { r, g, b } end
    el.draggable = function(self, v) self._draggable = v end
    el.show      = function(self) self._visible = true end
    el.hide      = function(self) self._visible = false end
    el.destroy   = function(self) self._destroyed = true end
    return el
  end,
}

-- Bridge echo.lua's require('../../lib/settings') to the loaded singleton.
-- run_tests dofiles this mock first, so this runs once before any test file.
local settings = require('lib.settings.settings')
package.loaded['../../lib/settings'] = settings
package.loaded['texts']              = texts
package.loaded['images']             = images
