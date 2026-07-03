-- Stubs for Windower globals required by the xivgamepad addon and its tests.
--
-- Shared-harness contract (.planning/xivgamepad-contracts.md): extend this file
-- ADDITIVELY ONLY (new stub methods/fields, new fixtures); never change existing
-- behavior. Resource fixtures are augmented from test files by mutating the
-- loaded tables (res.spells[n] = {...}), never by editing this file. Never stub
-- xivgamepad modules (e.g. 'log') here — test files preload their own
-- stubs via package.loaded before requiring the module under test.

-- Mirror Windower's addon-dir search path ({AddonPath}?.lua): in-game, intra-
-- addon requires use flat names ('log') and slash-relative subdirectory names
-- ('input/keyboard'), NOT the addons root. run_tests runs from the repo root,
-- so prepending the addon dir makes those names resolve exactly as in-game.
package.path = 'xivgamepad/?.lua;' .. package.path

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

-- ===========================================================================
-- Additive extension (crossbar port, Wave 0). Everything below is NEW surface
-- for the xivgamepad/crossbar/ port, its adapters and their tests; nothing
-- above this line changed. windower._reset is wrapped again at the bottom
-- (never rewritten).
-- ===========================================================================

-- Key items owned by the player: array of KI ids, consumed by the mounts
-- adapter via the ported mountroulette lib. Tests set windower.ffxi._key_items.
windower.ffxi._key_items = {}
windower.ffxi.get_key_items = function() return windower.ffxi._key_items end

-- Current target for skillchain queries. Tests set windower.ffxi._target
-- (nil = no target). The real API resolves target symbols ('t', 'bt', ...);
-- this stub ignores its arguments and returns the one settable fixture.
local function default_target()
  return { id = 1234, name = 'Target Dummy' }
end
windower.ffxi._target = default_target()
windower.ffxi.get_mob_by_target = function() return windower.ffxi._target end

-- FFXI install root, used by icon extraction to locate ROM DAT files.
-- Settable; restored by _reset.
local default_ffxi_path = 'C:\\Program Files (x86)\\PlayOnline\\SquareEnix\\FINAL FANTASY XI\\'
windower.ffxi_path = default_ffxi_path

-- Windower wildcard match. SUBSET: only '*' (any run of characters, including
-- empty) is implemented -- the one form mountroulette uses ('♪raptor*' suffix
-- match). The real wc_match also supports '?' and alternation; any such
-- character here is treated as a literal. Extend if a consumer ever needs
-- more. Byte-exact comparison (case-sensitive); mountroulette lowercases both
-- sides itself.
windower.wc_match = function(str, pattern)
  local lua_pattern = pattern:gsub('[%^%$%(%)%%%.%[%]%+%-%?%*]', function(c)
    if c == '*' then return '.*' end
    return '%' .. c
  end)
  return str:match('^' .. lua_pattern .. '$') ~= nil
end

-- res fixture growth for the crossbar port. New tables plus new FIELDS on the
-- existing spell/ability/weapon-skill entries (additive -- no existing field
-- changed). resource_generator reads: spells -> en/type/skill/recast_id/
-- mp_cost/element; job_abilities -> en/type/recast_id/tp_cost/element;
-- weapon_skills -> en/skill/element; plus res.skills[id].en and
-- res.elements[id].en. Real Windower resources carry a language-dependent
-- 'name' alias alongside 'en'; the ported libs read .name, so mount/KI
-- fixtures provide both (name mirrors en).
res.mounts = {
  [1] = { id = 1, en = 'Raptor',  name = 'Raptor' },
  [2] = { id = 2, en = 'Crab',    name = 'Crab' },
  [3] = { id = 3, en = 'Chocobo', name = 'Chocobo' },
}
res.key_items = {
  [3001] = { id = 3001, en = '♪Raptor Companion',  name = '♪Raptor Companion',  category = 'Mounts' },
  [3002] = { id = 3002, en = '♪Crab Companion',    name = '♪Crab Companion',    category = 'Mounts' },
  [3003] = { id = 3003, en = '♪Chocobo Companion', name = '♪Chocobo Companion', category = 'Mounts' },
  -- The real quest KI has no ♪ prefix; mountroulette excludes it by this
  -- exact lowercase name, so the fixture must match it byte-for-byte.
  [3004] = { id = 3004, en = "trainer's whistle", name = "trainer's whistle", category = 'Mounts' },
  [3005] = { id = 3005, en = 'airship pass', name = 'airship pass', category = 'Permanent' },
}
res.skills = {
  [2]  = { id = 2,  en = 'Sword' },
  [33] = { id = 33, en = 'Healing Magic' },
  [36] = { id = 36, en = 'Elemental Magic' },
  [39] = { id = 39, en = 'Ninjutsu' },
}
res.elements = {
  [0]  = { id = 0,  en = 'Fire' },
  [1]  = { id = 1,  en = 'Ice' },
  [2]  = { id = 2,  en = 'Wind' },
  [3]  = { id = 3,  en = 'Earth' },
  [4]  = { id = 4,  en = 'Lightning' },
  [5]  = { id = 5,  en = 'Water' },
  [6]  = { id = 6,  en = 'Light' },
  [7]  = { id = 7,  en = 'Dark' },
  [15] = { id = 15, en = 'None' },
}
res.spells[1].element          = 6
res.spells[1].targets          = 63
res.spells[144].element        = 0
res.spells[144].targets        = 32
res.spells[338].element        = 15
res.spells[338].targets        = 1
res.job_abilities[1].element   = 15
res.job_abilities[1].tp_cost   = 0
res.job_abilities[1].targets   = 1
res.job_abilities[5].element   = 15
res.job_abilities[5].tp_cost   = 0
res.job_abilities[5].targets   = 32
res.weapon_skills[32].element  = 15
res.weapon_skills[32].targets  = 32
res.weapon_skills[33].element  = 0
res.weapon_skills[33].targets  = 32

-- ---------------------------------------------------------------------------
-- Windower shared-lib shims for the ported crossbar/ code (skillchains.lua,
-- mountroulette.lua). Each fakes ONLY the subset those files touch; the
-- comment on each names the real Windower lib. Registered in package.loaded
-- under the canonical require names, and -- matching the real libs -- they
-- install globals: L, S, ActionPacket, string.ucfirst, string.unpack.
-- ---------------------------------------------------------------------------

local set_mt -- forward declaration: L(set) must recognize set instances

-- lists.lua shim: L{...} builds a list; L(set) converts an S set (element
-- order unspecified, as in the real lib -- callers sort if they need order).
-- Elements live at [1..n] on the list table itself, so '#' and numeric
-- indexing behave like the real array-backed lists. Subset: append, find
-- (predicate function OR plain value -> index or nil), it (value iterator),
-- length, concat, and list + list concatenation (skillchains' chainbound).
local list_methods = {}
local list_mt = { __index = list_methods }

local function new_list(source)
  local l = setmetatable({}, list_mt)
  if source ~= nil then
    if getmetatable(source) == set_mt then
      for el in pairs(source) do l[#l + 1] = el end
    else
      for i = 1, #source do l[i] = source[i] end
    end
  end
  return l
end

list_methods.append = function(self, el)
  self[#self + 1] = el
end

list_methods.find = function(self, what)
  for i = 1, #self do
    if type(what) == 'function' then
      if what(self[i]) then return i end
    elseif self[i] == what then
      return i
    end
  end
  return nil
end

list_methods.it = function(self)
  local i = 0
  return function()
    i = i + 1
    if self[i] ~= nil then return self[i], i end
  end
end

list_methods.length = function(self)
  return #self
end

list_methods.concat = function(self, sep)
  return table.concat(self, sep or '')
end

list_mt.__add = function(a, b)
  local l = new_list(a)
  for i = 1, #b do l[#l + 1] = b[i] end
  return l
end

L = function(t) return new_list(t) end

-- sets.lua shim: S{...} builds a set. Like the real lib, elements are stored
-- as keys of the set table itself (value true) with methods reached through
-- the metatable -- so an element named after a method would shadow it,
-- exactly as in the real lib (no consumer stores such elements). Subset:
-- add, contains, union (also set + set).
local set_methods = {}
set_mt = { __index = set_methods }

local function new_set(t)
  local s = setmetatable({}, set_mt)
  if t ~= nil then
    for i = 1, #t do s[t[i]] = true end
  end
  return s
end

set_methods.add = function(self, el)
  self[el] = true
end

set_methods.contains = function(self, el)
  if el == nil then return false end
  return rawget(self, el) == true
end

set_methods.union = function(self, other)
  local s = new_set()
  for el in pairs(self) do s[el] = true end
  for el in pairs(other) do s[el] = true end
  return s
end

set_mt.__add = set_methods.union

S = function(t) return new_set(t) end

-- luau.lua shim: the real lib bulk-loads lists/sets/string helpers/etc. The
-- list/set globals are installed above; the only string helper the ported
-- skillchain code touches is ucfirst.
string.ucfirst = function(str)
  return str:sub(1, 1):upper() .. str:sub(2)
end

-- pack.lua shim: the real lib adds string.pack/string.unpack. Subset: unpack
-- only, ONE format code per call, little-endian unsigned 'H' (2 bytes) and
-- 'I' (4 bytes) -- the two reads skillchains.lua performs on incoming chunk
-- data. Returns the value and the next position (skillchains uses only the
-- value). Anything else errors loudly rather than mis-decoding.
local pack_sizes = { H = 2, I = 4 }
string.unpack = function(str, fmt, pos)
  local size = pack_sizes[fmt]
  if not size then
    error("mock string.unpack: unsupported format '" .. tostring(fmt) .. "' (subset: H, I)", 2)
  end
  pos = pos or 1
  local value = 0
  for i = size - 1, 0, -1 do
    value = value * 256 + str:byte(pos + i)
  end
  return value, pos + size
end

-- actions.lua shim: a fake ActionPacket over plain fixture tables shaped like
-- the raw windower 'action' event payload. Fixture schema and accessor
-- mapping (each accessor is a thin field read):
--   act = {
--     category = <number>,             -- get_category_string() via map below
--     actor_id = <number>,             -- get_id()
--     param    = <number>,             -- get_param(); default 1st get_spell() return
--     targets  = { {                   -- get_targets() iterator; per target:
--       id      = <number>,            --   target.id (raw field, as the real
--                                      --   lib proxies raw target fields)
--       actions = { {                  --   target:get_actions() iterator; per action:
--         message      = <number>,     --     get_message_id()
--         add_effect   = <table|nil>,  --     get_add_effect(); skillchains reads
--                                      --     .message_id and .animation off it
--         spell_param  = <number|nil>, --     get_spell() return 1 (falls back to act.param)
--         resource     = <string|nil>, --     get_spell() return 2 ('spells' |
--                                      --     'job_abilities' | 'weapon_skills' | ...)
--         action_id    = <number|nil>, --     get_spell() return 3
--         interruption = <bool|nil>,   --     get_spell() return 4
--         conclusion   = <bool|table|nil>, -- get_spell() return 5
--       } }
--     } }
--   }
-- Category map: the subset of the real lib's category strings that
-- skillchains.lua dispatches on.
local category_strings = {
  [3]  = 'weaponskill_finish',
  [4]  = 'spell_finish',
  [6]  = 'job_ability',
  [11] = 'mob_tp_finish',
  [13] = 'avatar_tp_finish',
  [14] = 'job_ability_unblinkable',
}

local function wrap_action(act, raw_action)
  return {
    get_message_id = function() return raw_action.message end,
    get_add_effect = function() return raw_action.add_effect end,
    get_spell = function()
      local param = raw_action.spell_param
      if param == nil then param = act.param end
      return param, raw_action.resource, raw_action.action_id,
             raw_action.interruption, raw_action.conclusion
    end,
  }
end

local function wrap_target(act, raw_target)
  local target = { id = raw_target.id }
  target.get_actions = function()
    local i = 0
    return function()
      i = i + 1
      local raw = (raw_target.actions or {})[i]
      if raw then return wrap_action(act, raw) end
    end
  end
  return target
end

ActionPacket = {
  _listeners = {},
  new = function(act)
    return {
      get_category_string = function()
        return category_strings[act.category] or ('unknown_category_' .. tostring(act.category))
      end,
      get_id = function() return act.actor_id end,
      get_param = function() return act.param end,
      get_targets = function()
        local i = 0
        return function()
          i = i + 1
          local raw = (act.targets or {})[i]
          if raw then return wrap_target(act, raw) end
        end
      end,
    }
  end,
  -- The real lib multiplexes the windower 'action' event to listeners. The
  -- port extracts event registration, but any residual open_listener call is
  -- recorded (not dropped) so building the module never crashes the harness
  -- and tests can assert no stray registration remains.
  open_listener = function(fn) table.insert(ActionPacket._listeners, fn) end,
}

-- Register the shims under the canonical require names. The real luau/pack
-- libs work by global/string-table side effect (performed above), so a bare
-- true marker satisfies require; lists/sets/actions also return their tables.
package.loaded['lists']   = { L = L }
package.loaded['sets']    = { S = S }
package.loaded['luau']    = true
package.loaded['pack']    = true
package.loaded['actions'] = { ActionPacket = ActionPacket }

-- In-memory io fake for the icon-extraction tests. NOT auto-installed:
-- test_icons.lua builds one over a synthetic-DAT fs map and preloads it for
-- the module under test, restoring the original afterwards:
--   local real_io = package.loaded['io']
--   package.loaded['io'] = windower._make_fake_io({
--     ['C:\\...\\ROM\\118\\106.DAT'] = dat_bytes,
--   })
--   -- require the module under test here --
--   package.loaded['io'] = real_io
-- Handles support the icon_extractor subset: open(path, 'rb') -> handle, or
-- (nil, err) when the path is absent; open(path, 'wb') truncates;
-- seek('set'|'cur'|'end', offset); read(n) (nil at EOF, short read at the
-- tail) and read('*a'); write(str) at the current position; close(). Written
-- bytes land back in fs_map so tests assert output (e.g. BMP headers)
-- without touching the disk.
windower._make_fake_io = function(fs_map)
  local function new_handle(path, writable)
    local handle = { _pos = 0, _closed = false }
    handle.seek = function(self, whence, offset)
      whence = whence or 'cur'
      offset = offset or 0
      local len = #(fs_map[path] or '')
      if whence == 'set' then
        self._pos = offset
      elseif whence == 'cur' then
        self._pos = self._pos + offset
      elseif whence == 'end' then
        self._pos = len + offset
      else
        error("fake io: bad seek whence '" .. tostring(whence) .. "'", 2)
      end
      return self._pos
    end
    handle.read = function(self, fmt)
      local content = fs_map[path] or ''
      if fmt == '*a' or fmt == '*all' then
        local rest = content:sub(self._pos + 1)
        self._pos = #content
        return rest
      end
      if type(fmt) ~= 'number' then
        error("fake io: unsupported read format '" .. tostring(fmt) .. "' (subset: n, '*a')", 2)
      end
      if self._pos >= #content then return nil end
      local chunk = content:sub(self._pos + 1, self._pos + fmt)
      self._pos = self._pos + #chunk
      return chunk
    end
    handle.write = function(self, str)
      if not writable then
        error('fake io: handle not opened for writing', 2)
      end
      local content = fs_map[path] or ''
      fs_map[path] = content:sub(1, self._pos) .. str .. content:sub(self._pos + #str + 1)
      self._pos = self._pos + #str
      return self
    end
    handle.close = function(self)
      self._closed = true
      return true
    end
    return handle
  end
  return {
    open = function(path, mode)
      mode = mode or 'r'
      if mode:find('w', 1, true) then
        fs_map[path] = ''
        return new_handle(path, true)
      end
      if fs_map[path] == nil then
        return nil, path .. ': No such file or directory'
      end
      return new_handle(path, false)
    end,
  }
end

-- Wrap _reset again (never rewrite): restore the crossbar-port fixtures.
local pre_crossbar_reset = windower._reset
windower._reset = function()
  pre_crossbar_reset()
  windower.ffxi._key_items = {}
  windower.ffxi._target = default_target()
  windower.ffxi_path = default_ffxi_path
end
