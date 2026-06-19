# CLAUDE.md

## Project Overview

Lua addon scripts for Final Fantasy XI using the **Windower 4** framework. Each addon is a self-contained directory. Shared functionality lives in `lib/` at the repository root. Tests live in `tests/`.

## Repository Structure

```
lib/
  settings/                 # Shared settings management library (required by all addons)
    settings.lua
    CLAUDE.md               # Settings library documentation and usage contract

<addon-name>/
  <addon-name>.lua          # Main entry point
  README.md                 # Addon description + full command reference
  data/                     # All runtime-written and user-editable files
    <CharacterName>/        # Per-character user settings (managed by settings library)
      settings.json

tests/
  lib/
    settings/               # Tests for the shared settings library
      run_tests.lua
      test_*.lua
  <addon-name>/             # Tests for each addon
    run_tests.lua
    mock_windower.lua
    test_*.lua
```

### Data folder rules

| What | Where |
|------|-------|
| Per-character user config (edited via `setup` GUI) | `data/{CharacterName}/` |
| Runtime state written during gameplay | `data/` |
| Anything a user or the addon can modify at runtime | `data/` (any subdirectory) |

**Never** write runtime or user-editable files to the addon root.

## Shared Libraries

### `lib/settings`

All addons **must** use `lib/settings` for configuration management. Direct use of the Windower `config` library is not allowed in addon code.

See [lib/settings/CLAUDE.md](lib/settings/CLAUDE.md) for the full usage contract, API, and implementation details.

## Windower 4 Conventions

- **Lua version**: 5.1 (Windower bundles its own interpreter)
- **Addon metadata** goes in the `_addon` table:
  ```lua
  _addon.name     = 'AddonName'
  _addon.author   = 'Author'
  _addon.version  = '1.0.0'
  _addon.commands = {'addonname', 'an'}   -- full name + short alias
  ```
- Every addon **must** have a short alias command (e.g. `htb`, `gs`, `wb`). The alias is the second entry in `_addon.commands` and is the primary way users interact with the addon.
- **Events** are registered with `windower.register_event`:
  ```lua
  windower.register_event('load', function() end)
  windower.register_event('unload', function() end)
  windower.register_event('addon command', function(...) end)
  ```
- **Common APIs**: `windower`, `texts`, `packets`, `res` (resources), `files`
- Character name is available via `windower.ffxi.get_player().name`

## Required Commands

Every addon must implement these sub-commands (dispatched from `addon command`):

| Sub-command  | Behavior |
|--------------|----------|
| `setup`      | Opens the in-game configuration GUI |
| `exit`       | Saves staged changes and closes the GUI |
| `exit -d`    | Discards staged changes and closes the GUI |
| `help`       | Prints available commands to the chat log |

Dispatch pattern:

```lua
local commands = {
  exit  = function(...) gui.close(...) end,
  help  = function() print_help() end,
  setup = function() gui.open() end,
}

windower.register_event('addon command', function(cmd, ...)
  local handler = commands[cmd]
  if handler then
    handler(...)
  else
    print_help()
  end
end)
```

## Configuration GUI (`setup`)

- Use Windower's `texts` library or an imgui-style overlay for the `setup` GUI
- GUI open/closed state is ephemeral — do not persist it
- All reads and writes go through `lib/settings` — never access `data/` directly in addon code

### Staged settings

The GUI operates on a **staging copy** of the current settings. Changes are held in memory and are **not** written to disk until the user exits setup. The settings library manages this staging lifecycle — see [lib/settings/CLAUDE.md](lib/settings/CLAUDE.md).

- `//an exit` — commits staged changes to `data/{CharacterName}/settings.xml`
- `//an exit -d` — drops the staging copy; settings unchanged on disk

### GUI actions must call testable functions

GUI callbacks must never modify state directly. Every action must delegate to a named, testable function.

```lua
-- GOOD: callback delegates to a testable function
local function change_pos(x, y)
  settings.stage_set('pos_x', x)
  settings.stage_set('pos_y', y)
  element:pos(x, y)
end

on_drag(function(x, y) change_pos(x, y) end)
```

### Repositionable UI during setup

Any addon that displays a persistent UI element **must** make that element draggable while setup is open. Dragging must be disabled when setup closes. Position changes update staged settings via `change_pos` and are only persisted on save-exit.

## Code Style

### File layout

Mirror C# conventions adapted to Lua. Each file is organized in this order:

1. **`require` statements** — first thing in the file, before anything else
2. **`_addon` metadata** — name, author, version, commands
3. **State** — all `local` variables that hold module-level state
4. **Forward declarations** — `local` stubs for private functions called by public functions defined above them (required because Lua is parsed top-to-bottom)
5. **Public functions** — functions exposed via the command dispatch table, returned module table, or GUI callbacks; sorted alphabetically within this block
6. **Private functions** — internal helpers; sorted alphabetically within this block
7. **Event registrations** — `windower.register_event(...)` calls at the bottom

### Formatting rules

- 2-space indentation
- Snake_case for variables and functions
- No semicolons
- Align `=` signs in multi-line table/variable declarations when it improves readability
- Avoid globals; localize frequently used upvalues

## Per-Addon README

Every addon directory must contain a `README.md` that includes:

1. **What the addon does** — one short paragraph
2. **Installation** — how to drop it into Windower's addon folder and load it
3. **Commands** — a table of every in-game command with its alias and description:

   ```markdown
   ## Commands

   All commands use the alias `an` (or the full name `addonname`).

   | Command         | Description                                 |
   |-----------------|---------------------------------------------|
   | `//an setup`    | Opens the configuration GUI                 |
   | `//an exit`     | Saves changes and closes the GUI            |
   | `//an exit -d`  | Discards changes and closes the GUI         |
   | `//an help`     | Prints this command list in chat            |
   ```

4. **Configuration** — description of settings stored in `data/{CharacterName}/settings.json`

Keep the per-addon README current whenever commands are added or removed.

## Testing

Tests live in `tests/` at the repository root, mirroring the source tree.

### Running tests

```bash
lua tests/<addon-name>/run_tests.lua
lua tests/lib/settings/run_tests.lua
```

### Test harness conventions

- `mock_windower.lua` — stubs for `windower`, `texts`, and other Windower globals
- `test_*.lua` — individual test files, one per logical area
- `run_tests.lua` — discovers and runs all `test_*.lua` files; exits non-zero on failure
- Tests must not write to the live `data/` directory; use in-memory stubs or a temp path
- Tests must not depend on a running game client or Windower instance
- GUI logic is tested by calling underlying functions directly — never by simulating GUI events
- Staged-settings behavior must be covered: `exit -d` must leave live settings unchanged; `exit` must persist them

### In-game reload (manual testing)

```
//lua r <addon-name>
```

## Source Control

Source is hosted on a local **Forgejo** instance.
