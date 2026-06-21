-- Stubs for Windower globals required by lib/settings

windower = {
  ffxi = {
    _player = { name = 'TestChar' },
    get_player = function() return windower.ffxi._player end,
  },
}

-- texts mock used by config_gui tests. Each element tracks its anchor (_x,_y)
-- and size (_width,_height) and supports a bounding-box hover hit-test.
texts = {
  new = function(str, settings)
    local el = {
      _text    = str or '',
      _visible = false,
      _x       = 0,
      _y       = 0,
      _width   = 0,
      _height  = 18,
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

-- images mock used by config_gui backdrop tests.
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

package.loaded['texts']  = texts
package.loaded['images'] = images
