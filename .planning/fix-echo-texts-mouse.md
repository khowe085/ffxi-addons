## Plan: fix-echo-texts-mouse

**Branch:** `feat/fix-echo-texts-mouse`

### Problem

Two bugs in `echo/echo.lua` cause incorrect behaviour at runtime and in tests.

**Bug 1 — Missing `texts` require**
`echo/echo.lua` calls `texts.new(...)` at line 75 but never requires the `texts` library. In Windower 4 the `texts` global is injected at runtime, so the addon works in-game by accident, but the missing explicit require means `require('texts')` fails in the test environment. The fix is adding `local texts = require('texts')` as the second line of the file (immediately after the `settings_lib` require).

**Bug 2 — Wrong mouse event type constant writes 0 to disk**
`echo/echo.lua` line 130 guards position persistence with `if mtype == 3 then`. In the Windower mouse event API `mtype == 3` is right-button-down; `mtype == 2` is left-button-up (end of drag). The guard never fires on drag release, so `staged_settings.pos_x/pos_y` are never updated from the element's live position — they remain at their default 0 and that is what gets written to disk on save.

The same wrong constant appears in `tests/echo/test_settings.lua` line 102, which calls `e.on_mouse(3, 0, 0)` to simulate a mouse-up. The test passes today only because both sides share the same bug; fixing production without fixing the test would make the test fail.

Additionally, `tests/echo/mock_windower.lua` defines `texts` as a Lua global but never registers it in `package.loaded`, so `require('texts')` (introduced by Bug 1's fix) would fail in tests. The fix is adding `package.loaded['texts'] = texts` after the existing `package.loaded` lines in that file.

### Scope

| File | Change |
|------|--------|
| `echo/echo.lua` | Add `local texts = require('texts')` after line 1; change `mtype == 3` to `mtype == 2` at line 130 |
| `tests/echo/mock_windower.lua` | Add `package.loaded['texts'] = texts` after the existing `package.loaded['../../lib/settings']` line |
| `tests/echo/test_settings.lua` | Change `e.on_mouse(3, 0, 0)` to `e.on_mouse(2, 0, 0)` at line 102; leave `e.on_mouse(3, 10, 20)` at line 109 as-is (it intentionally uses a value that is not 2 to test that non-up events are ignored) |

### Acceptance criteria

- `lua tests/echo/run_tests.lua` exits 0 with all tests passing.
- `echo/echo.lua` has an explicit `require('texts')` at the top.
- `on_mouse` correctly guards on `mtype == 2`.
- The mouse-up test in `test_settings.lua` fires `mtype == 2` and still asserts `staged.pos_x == 120`.

### Tasks

**Task 1 — Fix texts require, mouse constant, and test alignment (single worktree)**

All three files are touched by the same logical fix and must be changed atomically so tests pass throughout. No parallel decomposition is warranted.

Files:
- `echo/echo.lua` — add `local texts = require('texts')` after line 1; change `mtype == 3` to `mtype == 2` at line 130
- `tests/echo/mock_windower.lua` — add `package.loaded['texts'] = texts` after the existing package.loaded line
- `tests/echo/test_settings.lua` — change `e.on_mouse(3, 0, 0)` to `e.on_mouse(2, 0, 0)` at line 102
