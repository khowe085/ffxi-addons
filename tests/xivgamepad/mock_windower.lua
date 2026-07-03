-- Stubs for Windower globals required by the xivgamepad addon and its tests.
--
-- Shared-harness contract (.planning/xivgamepad-contracts.md): extend this file
-- ADDITIVELY ONLY (new stub methods/fields, new fixtures); never change existing
-- behavior. Resource fixtures are augmented from test files by mutating the
-- loaded tables (res.spells[n] = {...}), never by editing this file. Never stub
-- xivgamepad modules (e.g. xivgamepad.log) here — test files preload their own
-- stubs via package.loaded before requiring the module under test.

_addon = {}

local function default_info()
  return { menu_open = false, chat_open = false, zone = 100 }
end

local function default_player()
  return { name = 'TestChar', main_job = 'WAR', sub_job = 'NIN', buffs = {}, status = 0 }
end

windower = {
  ffxi = {
    -- Tests that change _player/_info must restore them (windower._reset does).
    _player = default_player(),
    get_player = function() return windower.ffxi._player end,
    _info = default_info(),
    get_info = function() return windower.ffxi._info end,
  },
  -- Realistic Windows-style absolute path so storage/log tests exercise real
  -- path construction — unix-style paths mask separator/anchoring bugs
  -- (the lib/settings blind spot). Individual tests may override it.
  addon_path = 'C:\\Program Files (x86)\\Windower4\\addons\\xivgamepad\\',
  -- Capture registered handlers so lifecycle tests can fire events that the
  -- addon only wires through register_event (e.g. 'login', 'prerender').
  _events = {},
  register_event = function(name, fn) windower._events[name] = fn end,
  _chat = {},
  add_to_chat = function(_, msg) table.insert(windower._chat, msg) end,
  _commands = {},
  send_command = function(cmd) table.insert(windower._commands, cmd) end,
  _created_dirs = {},
  create_dir = function(path) table.insert(windower._created_dirs, path) end,
  _scheduled = {},
  -- In-memory filesystem backing the files mock: path string -> content string.
  _fs = {},
}

-- Windower extends coroutine with a wall-clock one-shot scheduler.
coroutine.schedule = function(fn, delay)
  table.insert(windower._scheduled, { fn = fn, at = delay })
end

-- Drain and run the scheduled queue; entries may schedule more while running.
windower._run_scheduled = function()
  local iterations = 0
  while #windower._scheduled > 0 do
    iterations = iterations + 1
    if iterations > 10000 then
      error('_run_scheduled exceeded 10000 iterations; runaway rescheduling loop', 2)
    end
    local entry = table.remove(windower._scheduled, 1)
    entry.fn()
  end
end

-- Restore pristine mock state so test files can isolate state between tests.
windower._reset = function()
  windower._chat = {}
  windower._commands = {}
  windower._created_dirs = {}
  windower._scheduled = {}
  windower._fs = {}
  windower._events = {}
  windower.ffxi._player = default_player()
  windower.ffxi._info = default_info()
end

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
    el.text       = function(self, v) if v ~= nil then self._text = v end return self._text end
    el.pos        = function(self, x, y) self._x = x; self._y = y end
    el.pos_x      = function(self) return self._x end
    el.pos_y      = function(self) return self._y end
    el.size       = function(self, v) self._size = v end
    el.alpha      = function(self, a) self._alpha = a end
    el.bg_alpha   = function(self, a) self._bg_alpha = a end
    el.bg_visible = function(self, v) self._bg_visible = v end
    el.color      = function(self, r, g, b) self._color = { r, g, b } end
    el.draggable  = function(self, v) self._draggable = v end
    el.show       = function(self) self._visible = true end
    el.hide       = function(self) self._visible = false end
    el.visible    = function(self) return self._visible end
    el.destroy    = function(self) self._destroyed = true end
    el.hover      = function(self, x, y)
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
    el.path      = function(self, p) if p ~= nil then self._path = p end return self._path end
    el.repeat_xy = function(self, x, y) self._repeat_x = x; self._repeat_y = y end
    el.alpha     = function(self, a) self._alpha = a end
    el.color     = function(self, r, g, b) self._color = { r, g, b } end
    el.draggable = function(self, v) self._draggable = v end
    el.show      = function(self) self._visible = true end
    el.hide      = function(self) self._visible = false end
    el.visible   = function(self) return self._visible end
    el.destroy   = function(self) self._destroyed = true end
    el.hover     = function(self, x, y)
      return x >= self._x and x < self._x + self._width
         and y >= self._y and y < self._y + self._height
    end
    return el
  end,
}

-- Files mock backed by windower._fs. In the real Windower files library paths
-- are relative to the addon directory; this mock keys _fs by the exact path
-- string passed in, so tests assert the same relative paths production code
-- constructs (e.g. 'data/TestChar/shared.json').
files = {
  new = function(path)
    local f = { path = path }
    f.exists = function(self) return windower._fs[self.path] ~= nil end
    f.read   = function(self) return windower._fs[self.path] end
    f.write  = function(self, str) windower._fs[self.path] = str end
    f.append = function(self, str)
      windower._fs[self.path] = (windower._fs[self.path] or '') .. str
    end
    return f
  end,
  exists = function(path) return windower._fs[path] ~= nil end,
}

-- Minimal resources fixture, loosely modeled on Windower res tables (keyed by
-- id, 'en' names, type/skill-style fields). Tests augment by mutation.
res = {
  spells = {
    [1]   = { id = 1,   en = 'Cure',           type = 'WhiteMagic', skill = 33, prefix = '/magic',    mp_cost = 8, recast_id = 1 },
    [144] = { id = 144, en = 'Fire',           type = 'BlackMagic', skill = 36, prefix = '/magic',    mp_cost = 7, recast_id = 144 },
    [338] = { id = 338, en = 'Utsusemi: Ichi', type = 'Ninjutsu',   skill = 39, prefix = '/ninjutsu', mp_cost = 0, recast_id = 338 },
  },
  job_abilities = {
    [1] = { id = 1, en = 'Berserk', type = 'JobAbility', prefix = '/jobability', recast_id = 1 },
    [5] = { id = 5, en = 'Provoke', type = 'JobAbility', prefix = '/jobability', recast_id = 5 },
  },
  weapon_skills = {
    [32] = { id = 32, en = 'Fast Blade',      skill = 2, prefix = '/weaponskill' },
    [33] = { id = 33, en = 'Red Lotus Blade', skill = 2, prefix = '/weaponskill' },
  },
  items = {
    [4116] = { id = 4116, en = 'Hi-Potion',  category = 'Usable', targets = 1 },
    [4157] = { id = 4157, en = 'Echo Drops', category = 'Usable', targets = 1 },
  },
  buffs = {
    [358] = { id = 358, en = 'Light Arts',      enl = 'Light Arts' },
    [359] = { id = 359, en = 'Dark Arts',       enl = 'Dark Arts' },
    [401] = { id = 401, en = 'Addendum: White', enl = 'Addendum: White' },
    [402] = { id = 402, en = 'Addendum: Black', enl = 'Addendum: Black' },
  },
}

-- Bridge require names to the mocks and load the real shared library.
-- run_tests dofiles this mock first, so this runs once before any test file;
-- requiring the real lib/settings modules registers them in package.loaded
-- under the canonical names xivgamepad modules use.
require('lib.settings.settings')
require('lib.settings.config_gui')
package.loaded['texts']     = texts
package.loaded['images']    = images
package.loaded['files']     = files
package.loaded['resources'] = res

-- Additive extension (Task 2b): recast sources for the HUD's tick(). Tests
-- populate _spell_recasts (1/60ths of a second) / _ability_recasts (seconds)
-- by recast_id, or nil out the getters to exercise graceful absence. _reset
-- is wrapped (not modified) so existing behavior is untouched and the getters
-- are restored after an absence test.
windower.ffxi._spell_recasts = {}
windower.ffxi._ability_recasts = {}
local function install_recast_getters()
  windower.ffxi.get_spell_recasts = function() return windower.ffxi._spell_recasts end
  windower.ffxi.get_ability_recasts = function() return windower.ffxi._ability_recasts end
end
install_recast_getters()
local base_reset = windower._reset
windower._reset = function()
  base_reset()
  windower.ffxi._spell_recasts = {}
  windower.ffxi._ability_recasts = {}
  install_recast_getters()
end
