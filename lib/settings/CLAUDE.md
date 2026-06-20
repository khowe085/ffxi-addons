# lib/settings — Settings Management Library

## Purpose

Provides a unified API for loading, staging, saving, and discarding per-character addon settings. All addons in this repository must use this library instead of calling the Windower `config` library directly.

## File location

Settings are stored as JSON at `<addon-root>/data/{CharacterName}/settings.json`. The library resolves the character name automatically from `windower.ffxi.get_player().name`.

## API

```lua
local settings = require('../../lib/settings')
```

### `settings.load(addon_path, defaults)`

Loads the character's `settings.json` file. Falls back to `defaults` for any missing key. Must be called from the addon's `load` event.

- `addon_path` — absolute path to the addon root (use `windower.addon_path`)
- `defaults` — table of default values

Returns the live settings table.

### `settings.open_setup(live)`

Opens a staging session. Creates a deep in-memory copy of `live` settings that GUI actions modify. Must be called when the user runs `setup`.

- `live` — the live settings table returned by `settings.load`

Returns the staged settings table.

### `settings.stage_set(staged, key, value)`

Updates a single key in the staged settings table. GUI action functions (e.g., `change_pos`) must use this instead of writing to the staged table directly, so calls remain mockable in tests.

### `settings.commit(staged, addon_path)`

Serializes the staged settings to JSON, writes them to `data/{CharacterName}/settings.json`, and returns the new live settings table. Called on `exit` (save).

### `settings.discard()`

Drops the staging session without writing anything. Called on `exit -d`.

### `settings.in_setup()`

Returns `true` if a staging session is currently open.

### `settings.logged_in()`

Returns `true` only if a character is logged in — `windower.ffxi.get_player()` is non-nil and has a non-empty `.name`. Pure read with no side effects. Use it to gate settings access from addon lifecycle events.

## Login lifecycle

`settings.load` and `settings.commit` both resolve a per-character path and therefore require a logged-in character. They assert `logged_in()` up front and raise a clear error (containing "logged in") instead of an opaque nil index when no character is present (e.g. the POL / character-select screen).

Addons must defer settings access until a character is logged in:

- Run init only when `settings.logged_in()` is true; on the `load` event, skip init if it returns false.
- Register the Windower `login` event to (re)initialize and reload settings for the current character. `login` does not re-fire on `load`, so reloading here is what keeps each character on its own `settings.json` and prevents cross-character clobber.
- Make init idempotent so repeated logins reuse existing UI elements rather than leaking new ones.

## Usage pattern in an addon

```lua
local settings_lib = require('../../lib/settings')

-- State
local live_settings
local staged_settings

-- Public functions
local function setup_open()
  staged_settings = settings_lib.open_setup(live_settings)
end

local function setup_exit_save()
  live_settings   = settings_lib.commit(staged_settings, windower.addon_path)
  staged_settings = nil
end

local function setup_exit_discard()
  settings_lib.discard()
  staged_settings = nil
end

local function change_pos(x, y)
  settings_lib.stage_set(staged_settings, 'pos_x', x)
  settings_lib.stage_set(staged_settings, 'pos_y', y)
  element:pos(x, y)
end

-- Event registrations
windower.register_event('load', function()
  local defaults = { pos_x = 0, pos_y = 0 }
  live_settings = settings_lib.load(windower.addon_path, defaults)
end)
```

## Implementation rules

- The library must not depend on any addon-specific state
- Settings are serialized as JSON; use a pure-Lua JSON library compatible with Lua 5.1
- `stage_set` must be a plain function call (not a method) so it is easy to stub in tests
- `commit` must be atomic with respect to the staged table — it must not partially write on error
- The library must not register any Windower events itself; all event wiring is done by the addon

## Testing

Tests live in `tests/lib/settings/`. The library is tested in isolation with a mocked filesystem — no Windower runtime required.

```bash
lua tests/lib/settings/run_tests.lua
```

Required test coverage:

- `load` returns defaults when no file exists
- `load` merges saved values over defaults
- `open_setup` returns a deep copy (mutations do not affect live settings)
- `stage_set` updates the staged table
- `commit` writes staged values to the correct JSON path and returns them as the new live table
- `discard` leaves live settings unchanged
- `in_setup` returns correct state before/during/after a session
