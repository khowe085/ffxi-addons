-- Stubs for Windower globals required by the echo addon and its tests

_addon = {}

windower = {
  ffxi = {
    -- Tests that change _player must restore it (or reset it in their own setup); fresh() resets it to TestChar.
    _player = { name = 'TestChar' },
    get_player = function() return windower.ffxi._player end,
  },
  addon_path = '/addon/',
  register_event = function() end,
  add_to_chat = function(_, msg) table.insert(windower._chat, msg) end,
  _chat = {},
}

texts = {
  new = function(str, settings)
    return {
      _visible  = false,
      text      = function(self, v) self._text = v end,
      pos       = function(self, x, y) self._x = x; self._y = y end,
      pos_x     = function(self) return self._x end,
      pos_y     = function(self) return self._y end,
      draggable = function(self, v) self._draggable = v end,
      show      = function(self) self._visible = true end,
      hide      = function(self) self._visible = false end,
      destroy   = function(self) end,
    }
  end,
}

-- Bridge echo.lua's require('../../lib/settings') to the loaded singleton.
-- run_tests dofiles this mock first, so this runs once before any test file.
local settings = require('lib.settings.settings')
package.loaded['../../lib/settings'] = settings
