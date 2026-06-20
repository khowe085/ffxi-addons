# Plan: Login Lifecycle Hardening (lib/settings + echo)

## Problem

`lib/settings.settings_path` resolves the per-character path via
`windower.ffxi.get_player().name`. When no character is logged in (POL /
character-select screen), `get_player()` returns `nil`, so `.name` is an opaque
nil-index crash. Two concrete failures:

1. **Loaded before login** (the normal init.txt case): the addon's `load`
   event calls `settings.load()` pre-login → crash → addon left uninitialized;
   later commands then crash on `nil` state until a manual reload.
2. **Character switch** (logout A → login B): addons init only on `load`, which
   does not re-fire. In-memory settings stay char A's; the first `set` on B
   commits A's values into B's file (cross-character clobber).

## Fix

### lib/settings (shared)
- Add `settings.logged_in()` → `true` iff `windower.ffxi.get_player()` is
  non-nil with a non-empty `.name`. Pure read, no side effects.
- `settings.load` and `settings.commit` assert `logged_in()` up front with a
  clear, actionable message instead of an opaque nil index.

### Addon lifecycle contract (echo is the reference)
- Defer init until logged in: `load` event runs init **only if** `logged_in()`.
- `login` event (re)initializes — reloads the current character's settings and
  refreshes the UI. `init()` must be **idempotent** (reuse the UI element; no
  leaks on repeated logins).
- `logout` event hides the UI and abandons any open setup session.

### Convention ("include in future addons")
- Document the lifecycle contract in `lib/settings/CLAUDE.md` and the required
  lifecycle tests in root `CLAUDE.md` (Testing). Every addon must:
  defer-init-to-login, reload-per-character, hide-on-logout, and ship the four
  lifecycle tests below.

## Tasks

### Task A — lib/settings + lib tests
- `lib/settings/settings.lua`: add `M.logged_in()`; assert in `load`/`commit`.
- `tests/lib/settings/mock_windower.lua`: make the logged-in player settable
  (`windower.ffxi._player`, default `{name='TestChar'}`; `get_player` returns it).
- `tests/lib/settings/test_login.lua` (new): logged_in true/false; load & commit
  error clearly when not logged in; per-character path isolation (commit as A,
  load as B → defaults, load as A → A's data). Restore default player at end.
- `tests/lib/settings/run_tests.lua`: run `test_login.lua`.
- `lib/settings/CLAUDE.md`: document `logged_in()` + the not-logged-in contract.

### Task B — echo + echo lifecycle tests
- `echo/echo.lua`: `echo.on_load()` (guarded init), `echo.on_logout()` (discard
  staging, draggable off, hide), idempotent `echo.init()` (+ `element:show()`);
  register `login`→`init`, `logout`→`on_logout`, `load`→`on_load`.
- `tests/echo/mock_windower.lua`: settable `_player`; element `show`/`hide`
  (+`_visible`).
- `tests/echo/test_settings.lua` / `test_commands.lua`: `fresh()` resets
  `_player` to TestChar for order-independence.
- `tests/echo/test_lifecycle.lua` (new): load-before-login defers (no crash, no
  element); login initializes & loads current char; character switch reloads &
  does not clobber the other char's file; logout hides + abandons setup; init
  shows the overlay.
- `tests/echo/run_tests.lua`: run `test_lifecycle.lua`.

### Task C — convention docs (after A/B verified)
- Root `CLAUDE.md`: login/logout requirement + required lifecycle tests.
- `echo/README.md`: brief note on per-character + login behavior.
- Memory: record the lifecycle contract + that echo is the reference.

## Verification
```bash
lua tests/lib/settings/run_tests.lua
lua tests/echo/run_tests.lua
```
Both green. Manual: load at char-select (no error) → log in (text appears) →
switch characters (correct per-char text/pos) → logout (overlay hides).
