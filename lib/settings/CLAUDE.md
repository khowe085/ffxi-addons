# lib/settings — Settings Management Library

## Purpose

Provides a unified API for loading, staging, saving, and discarding per-character addon settings. All addons in this repository must use this library instead of calling the Windower `config` library directly.

## File location

Settings are stored as JSON at `<addon-root>/data/{CharacterName}/settings.json`. The library resolves the character name automatically from `windower.ffxi.get_player().name`.

`commit` creates the per-character directory only when the first write fails (the folder is missing). It creates just the `data/` and `data/{CharacterName}/` folders beneath `addon_path` — which always exists — via `windower.create_dir` (separators matched to `addon_path`, no shell-out). It never walks above `addon_path` into system paths such as `C:\` or `Program Files`.

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

Opens a staging session. Creates a deep in-memory copy of `live` settings that GUI actions modify. Must be called when the user runs `config`.

- `live` — the live settings table returned by `settings.load`

Returns the staged settings table.

### `settings.stage_set(staged, key, value)`

Updates a single key in the staged settings table. GUI action functions (e.g., `change_pos`) must use this instead of writing to the staged table directly, so calls remain mockable in tests.

### `settings.commit(staged, addon_path)`

Serializes the staged settings to JSON, writes them to `data/{CharacterName}/settings.json`, and returns the new live settings table. Called on `save`.

### `settings.discard()`

Drops the staging session without writing anything. Called on `discard`.

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

local function setup_close_save()
  live_settings   = settings_lib.commit(staged_settings, windower.addon_path)
  staged_settings = nil
end

local function setup_close_discard()
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

## Configuration GUI helper (`config_gui`)

`lib/settings/config_gui.lua` is a sibling module that renders the reusable configuration-window
**chrome** so addons only provide body content. It holds **no addon state**, registers **no
Windower events**, and takes the `texts` (and optional `images`) libraries by **dependency
injection** — mirroring the `io_provider` swap in `settings.lua`. `settings.lua` itself stays pure
data; all UI lives here.

```lua
local config_gui = require('lib.settings.config_gui')

local gui = config_gui.new({
  texts      = texts,          -- required (injected for testability)
  images     = images,         -- optional; draws a solid window backdrop and is passed to custom tabs
  title      = _addon.name,    -- header text
  on_save    = save_fn,        -- Save button / `save` command
  on_discard = discard_fn,     -- Discard button / `discard` command
  on_move    = function(x, y) end, -- window drag-release → stage the new anchor
  pos        = { x = 0, y = 0 },        -- initial window anchor (load from settings)
  size       = { width = 320, height = 160 }, -- addon-defined BODY/content area (px); window = body + chrome
})
```

### Body tabs

`gui:show(tabs)` / `gui:set_tabs(tabs)` take a **list of tabs** (always a list, even for one — the
tab bar is hidden when there is a single tab). Each tab is either:

- **text tab** — `{ title = 'General', lines = { 'line 1', ... } }`. The helper renders and scrolls it.
- **custom tab** — `{ title = 'Magic', render = fn, on_mouse = fn, hide = fn }`. The helper calls
  `render(vp, { texts, images })` with the body viewport rect (re-called on drag and `set_tabs`),
  forwards body-relative mouse events to `on_mouse(rel_x, rel_y, mtype, delta)`, and calls `hide()`
  on tab switch / `gui:hide()`. Use this for interactive, image-rich bodies (icon grids, etc.).

### Methods

`gui:select_tab(i)` · `gui:scroll(delta)` · `gui:show(tabs)` / `gui:hide()` / `gui:is_open()` ·
`gui:set_tabs(tabs)` · `gui:set_pos(x, y)` · `gui:set_draggable(bool)` ·
`gui:handle_mouse(mtype, x, y, delta)` (delegate the addon's `mouse` event here; returns `true`
when the event is over the window so the addon blocks it from the game) · `gui:destroy()`
(on `unload`).

### Behavior contract

- The addon defines the **body/content area** via `size`; the chrome (header, optional tab bar,
  footer, right-side scroll column) wraps it, and the **total window = body + chrome**. The body
  is constant — growing the chrome (e.g. a taller footer) grows the window, never the body — and
  the body **scrolls** when content overflows the body area (up/down buttons on the right).
- The chrome draws visually distinct header and footer bands plus button-styled Save/Discard hit
  targets inset in the footer (via the injected `images`); the body is clipped to the frame and
  monospace text tabs truncate over-long lines with an ellipsis so nothing overflows the window.
- The window is draggable by its header only during config; the body is not draggable. The addon
  persists the anchor via `on_move` → `settings.stage_set`. Disable dragging on close.
- Every mouse event over the open window is consumed (returns `true`) so clicks never reach the game.
- Scrolling (text tabs) uses the right-side `▲`/`▼` buttons; they are hidden when content fits.
- Chrome hit-testing uses rects computed from the layout (not `texts:hover`, whose extents are
  glyph-based), so in-game behavior matches the tests.

## Implementation rules

- The library must not depend on any addon-specific state
- Settings are serialized as JSON; use a pure-Lua JSON library compatible with Lua 5.1
- `stage_set` must be a plain function call (not a method) so it is easy to stub in tests
- `commit` must be atomic with respect to the staged table — it must not partially write on error
- The library must not register any Windower events itself; all event wiring is done by the addon
- `config_gui` follows the same rules: no addon state, no event registration, `texts`/`images` injected

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
