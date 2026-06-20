# Plan: Echo Addon

## Context

The user wants a new Windower 4 addon called **Echo** (alias `ec`) that displays a user-provided string in a persistent, draggable text overlay on screen. The text is set via an in-game command and the position is configurable via the standard setup/exit GUI flow.

---

## Files to Create

```
echo/
  echo.lua
  README.md
  data/           (empty — created at runtime by settings library)
tests/echo/
  mock_windower.lua
  run_tests.lua
  test_commands.lua
  test_settings.lua
```

---

## Settings

Stored at `echo/data/{CharacterName}/settings.json` via `lib/settings`.

```lua
local defaults = {
  text  = '',
  pos_x = 0,
  pos_y = 0,
}
```

---

## Commands

| Command            | Description                                      |
|--------------------|--------------------------------------------------|
| `//ec set <text>`  | Set and display the text; saves to disk immediately (or to staged if in setup) |
| `//ec clear`       | Clear the displayed text (delegates to `set ''`) |
| `//ec setup`       | Open the positioning GUI; enables dragging       |
| `//ec exit`        | Save staged position changes and close GUI       |
| `//ec exit -d`     | Discard staged position changes                  |
| `//ec help`        | Print all commands to chat                       |

---

## `echo.lua` Structure

Follow the file layout from CLAUDE.md:

1. `require` — `lib/settings` via `require('../../lib/settings')`
2. `_addon` metadata — name `Echo`, alias `ec`
3. State — `live_settings`, `staged_settings`, `element` (texts object)
4. Forward declarations — stubs for functions referenced before definition
5. Public functions (alphabetical) — `change_pos`, `cmd_clear`, `cmd_set`, `setup_close_discard`, `setup_close_save`, `setup_open`
6. Private functions (alphabetical) — `print_help`, `refresh_display`
7. Event registrations — `load`, `unload`, `addon command`

### Key implementation details

**`refresh_display(text, x, y)`** — updates `element:text()` and `element:pos()`. Called after any state change.

**`cmd_set(text)`** — the critical dual-mode function:
```lua
local function cmd_set(text)
  if settings_lib.in_setup() then
    settings_lib.stage_set(staged_settings, 'text', text)
  else
    live_settings.text = text
    local tmp = settings_lib.open_setup(live_settings)
    live_settings = settings_lib.commit(tmp, windower.addon_path)
  end
  refresh_display(text, ...)
end
```
When in setup, stages the change (saved on `exit`). When outside setup, opens a temporary staging session, commits immediately, and resets `_in_setup` to false.

**`change_pos(x, y)`** — called by mouse drag callback. Delegates to `settings_lib.stage_set` on both axes, then updates `element:pos()`. Only active during setup.

**`setup_open()`** — calls `settings_lib.open_setup(live_settings)`, stores result in `staged_settings`, enables `element:draggable(true)`.

**`setup_close_save(...)`** — calls `settings_lib.commit(staged_settings, ...)`, stores new `live_settings`, calls `element:draggable(false)`.

**`setup_close_discard()`** — calls `settings_lib.discard()`, sets `staged_settings = nil`, calls `element:draggable(false)`.

**Command dispatch** — standard pattern, passes `...` to `exit` handler to support `exit -d`:
```lua
local commands = {
  clear = function()    cmd_clear() end,
  exit  = function(...) gui_close(...) end,
  help  = function()    print_help() end,
  set   = function(...) cmd_set(table.concat({...}, ' ')) end,
  setup = function()    setup_open() end,
}
```

**`load` event** — calls `settings_lib.load(windower.addon_path, defaults)`, creates texts element, calls `refresh_display`.

**`unload` event** — destroys texts element.

**Mouse drag** — register `'mouse drag'` event; inside handler call `change_pos(x, y)` only if `settings_lib.in_setup()`.

---

## Test Structure

### `mock_windower.lua`

Extend the lib/settings mock to also stub `texts` and the drag event:
```lua
windower = {
  ffxi    = { get_player = function() return { name = 'TestChar' } end },
  addon_path = '/addon/',
  register_event = function() end,
}
texts = {
  new = function()
    return {
      text       = function(self, v) self._text = v end,
      pos        = function(self, x, y) self._x = x; self._y = y end,
      draggable  = function(self, v) self._draggable = v end,
      destroy    = function(self) end,
    }
  end,
}
```

### `test_commands.lua`

- `set` outside setup: text updated in live_settings and committed to VFS
- `set` inside setup: staged_settings.text updated; live_settings.text unchanged until commit
- `clear` delegates to `set ''`
- After `cmd_set`, `refresh_display` is called (verify element._text updated)

### `test_settings.lua`

- Load returns defaults when no file exists
- `setup_open` deep-copies live into staged (mutations don't affect live)
- Drag via `change_pos`: staged pos_x/pos_y updated; live unchanged
- `exit` commits staged to VFS and returns as new live settings
- `exit -d` discards; VFS unchanged; staged = nil; live unchanged

---

## Tasks

Three parallel lua-dev worktrees. Test tasks (2, 3) write against the planned API and integrate cleanly on merge; lua-QA runs the full suite after all worktrees are combined.

### Task 1 — Core implementation

**Files:**
- `echo/echo.lua` — full addon implementation (all state, functions, events, commands)

**Scope:** Everything in the `echo.lua` Structure section above. No test files.

**Acceptance:** File loads without errors; all functions and events are present and match the planned API.

---

### Task 2 — Test harness + settings lifecycle tests

**Files:**
- `tests/echo/mock_windower.lua` — Windower/texts stubs (see Mock spec in Test Structure section)
- `tests/echo/run_tests.lua` — discovers and runs all `test_*.lua` files; exits non-zero on failure
- `tests/echo/test_settings.lua` — settings lifecycle tests

**Scope:** Harness infrastructure plus the settings-layer tests. Written against the planned API; runs correctly once merged with Task 1.

**Tests to cover:**
- `load` returns defaults when no file exists
- `setup_open` deep-copies live into staged; mutations do not affect live
- `change_pos` updates staged pos_x/pos_y; live is unchanged
- `exit` commits staged to VFS and returns as new live settings
- `exit -d` discards; VFS unchanged; `staged_settings` is nil; live unchanged

---

### Task 3 — Command behavior tests

**Files:**
- `tests/echo/test_commands.lua` — command dispatch and behavior tests

**Scope:** Verifies every user-facing command. Written against the planned API; auto-discovered by Task 2's `run_tests.lua` on merge.

**Tests to cover:**
- `cmd_set` outside setup: text committed to VFS; `element._text` updated
- `cmd_set` inside setup: `staged_settings.text` updated; live unchanged until commit
- `cmd_clear` delegates to `cmd_set('')`; element shows empty string
- `help` prints a line for every command (`set`, `clear`, `setup`, `exit`, `exit -d`, `help`)

---

## Verification

```bash
lua tests/echo/run_tests.lua
```

All tests must pass. Manual in-game test:
1. `//ec set Hello World` — text appears on screen
2. `//ec setup` — drag handle enabled; drag display to new position
3. `//ec exit` — position saved; drag disabled
4. `//lua r echo` — text and position both restored from disk
5. `//ec exit -d` — position reverts to pre-setup coordinates
