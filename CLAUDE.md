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
| Per-character user config (edited via `config` GUI) | `data/{CharacterName}/` |
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
  windower.register_event('login', function() end)    -- fires on every character entry, incl. switches
  windower.register_event('logout', function() end)
  windower.register_event('unload', function() end)
  windower.register_event('addon command', function(...) end)
  ```
- **Common APIs**: `windower`, `texts`, `packets`, `res` (resources), `files`
- Character name is available via `windower.ffxi.get_player().name` — but `get_player()` returns **`nil`** when no character is logged in (POL / character-select). Never index it unguarded; see [Login lifecycle](#login-lifecycle).

## Login lifecycle

Addons are commonly loaded from `init.txt` **before** a character is logged in, and they stay loaded across logouts and character switches. Per-character settings depend on `windower.ffxi.get_player().name`, which is `nil` until login. Every addon **must** therefore:

- **Defer settings/UI initialization until logged in.** On `load`, only initialize if a character is present (`settings.logged_in()` — see [lib/settings/CLAUDE.md](lib/settings/CLAUDE.md)). Otherwise wait for `login`.
- **(Re)initialize on `login`.** The `login` event fires on every character entry, including switching characters. Reload the current character's settings and refresh the UI so state is always scoped to the active character. `init` **must be idempotent** — reuse the existing UI element (no leaks) and clear any open setup session.
- **Clean up on `logout`.** Hide the UI and abandon any open setup session (`settings.discard()`), so a previous character's state is never shown or written under another character.

```lua
local function init()                 -- idempotent: safe to call on load and every login
  if settings.in_setup() then settings.discard(); staged = nil end
  live = settings.load(windower.addon_path, defaults)
  if not element then element = texts.new('', text_settings) end
  refresh_display()
  element:show()
end

windower.register_event('load',   function() if settings.logged_in() then init() end end)
windower.register_event('login',  function() init() end)
windower.register_event('logout', function() on_logout() end)   -- discard staging; hide UI
```

Failing to do this causes two bugs: an opaque nil-index crash when loaded before login, and cross-character settings clobber on character switch. `echo` is the reference implementation; its `tests/echo/test_lifecycle.lua` is the template lifecycle test set (see Testing).

## Required Commands

Every addon must implement these sub-commands (dispatched from `addon command`):

| Sub-command | Aliases | Behavior |
|-------------|---------|----------|
| `config`    | `c`     | Opens the in-game configuration GUI |
| `save`      | `s`     | Saves staged changes and closes the GUI |
| `discard`   | `d`     | Discards staged changes and closes the GUI |
| `help`      |         | Prints available commands to the chat log |

Dispatch pattern:

```lua
local commands = {
  c       = function() gui.open() end,
  config  = function() gui.open() end,
  d       = function() gui.close_discard() end,
  discard = function() gui.close_discard() end,
  help    = function() print_help() end,
  s       = function() gui.close_save() end,
  save    = function() gui.close_save() end,
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

## Configuration GUI (`config`)

- Use Windower's `texts` library or an imgui-style overlay for the `config` GUI
- GUI open/closed state is ephemeral — do not persist it
- All reads and writes go through `lib/settings` — never access `data/` directly in addon code

### Staged settings

The GUI operates on a **staging copy** of the current settings. Changes are held in memory and are **not** written to disk until the user exits config. The settings library manages this staging lifecycle — see [lib/settings/CLAUDE.md](lib/settings/CLAUDE.md).

- `//an save` — commits staged changes to `data/{CharacterName}/settings.json`
- `//an discard` — drops the staging copy; settings unchanged on disk

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

### Repositionable UI during config

Any addon that displays a persistent UI element **must** make that element draggable while config is open. Dragging must be disabled when config closes. Position changes update staged settings via `change_pos` and are only persisted on save.

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
- CRLF (`\r\n`) line endings for source files — enforced by `.gitattributes`

## Per-Addon README

Every addon directory must contain a `README.md` that includes:

1. **What the addon does** — one short paragraph
2. **Installation** — how to drop it into Windower's addon folder and load it
3. **Commands** — a table of every in-game command with its alias and description:

   ```markdown
   ## Commands

   All commands use the alias `an` (or the full name `addonname`).

   | Command                    | Description                                 |
   |----------------------------|---------------------------------------------|
   | `//an config` / `//an c`   | Opens the configuration GUI                 |
   | `//an save` / `//an s`     | Saves changes and closes the GUI            |
   | `//an discard` / `//an d`  | Discards changes and closes the GUI         |
   | `//an help`                | Prints this command list in chat            |
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
- Staged-settings behavior must be covered: `discard` must leave live settings unchanged; `save` must persist them

### Required login-lifecycle tests

Every addon's test suite **must** cover the [login lifecycle](#login-lifecycle). Make the mocked logged-in player settable (e.g. a `windower.ffxi._player` field that `get_player` returns; tests set it to `nil`, `{name='Alpha'}`, etc., and restore the default) and assert:

- **Loaded before login defers** — the `load` handler does not initialize and does not crash when `get_player()` is `nil`.
- **Login initializes** — the `login` handler loads the current character's settings and shows the UI.
- **Character switch reloads, no clobber** — after switching characters, the new character's settings load (not the previous one's); writes land in the new character's file; the previous character's file is left intact.
- **Logout cleans up** — the UI is hidden and any open setup session is abandoned; logout is safe before init (no element) and when not in config.

`tests/echo/test_lifecycle.lua` is the reference template — copy its structure for new addons.

### In-game reload (manual testing)

```
//lua r <addon-name>
```

## Source Control

Source is hosted on **GitHub** (`khowe085/ffxi-addons`); the default branch is `main`. Use the `gh` CLI for branches, pushes, and pull requests. All work lands on `main` through a pull request — never commit directly to `main`.

## Development Workflow

Every task follows this agent pipeline:

### Planning

Before implementation, a plan is written to `.planning/<plan-name>.md` at the repository root, and the feature branch `feat/<plan-name>` is created off `main` at the same time. The plan includes a **Tasks** section that breaks the work into discrete, independently implementable units. All work for the plan is committed to its feature branch.

### Stages

| # | Who | Action |
|---|-----|--------|
| 1 | **Plan agent** | Writes plan to `.planning/<plan-name>.md` **and creates the feature branch `feat/<plan-name>` off `main`**; plan must be approved before proceeding. |
| 2 | **Orchestrator** | Decomposes the approved plan into tasks; adds or updates the **Tasks** section in the plan file. |
| 3 | **lua-dev** (one per task, in parallel) | Each task gets its own isolated git worktree; implements the feature and writes all relevant tests. |
| 4 | **lua-reviewer** (per worktree) | Reviews the implementation for correctness, style, and test coverage. |
| 5 | **lua-dev** (per worktree) | Resolves every issue lua-reviewer raised. **Must complete before moving forward.** |
| 6 | **lua-QA** | Runs the full test suite across all worktrees. |
| 7 | — | If lua-QA finds failures, repeat from step 3. |
| 8 | — | Merge the approved task work onto the feature branch `feat/<plan-name>`. |
| 9 | **docs agent** | Writes or updates `README.md` for each modified addon based on the approved implementation. |
| 10 | **Orchestrator** | Commits the completed work to the feature branch, pushes it, and opens a PR against `main`. The PR description **is** the release notes for the change (a user-facing summary usable verbatim as a changelog entry). |

### Rules

- Plans live in `.planning/` at the repository root; each plan has a matching `feat/<plan-name>` branch created when the plan is written, and all of its work is committed there.
- The **Tasks** section of the plan defines parallel work units; each task maps to exactly one lua-dev worktree.
- lua-dev **must not** move past the review stage until lua-reviewer raises zero blocking issues.
- lua-QA is the final gate — work is not merged onto the feature branch, and no PR is opened, while tests are failing.
- The PR against `main` is opened only after lua-QA approves, and its description contains the release notes for the change.
