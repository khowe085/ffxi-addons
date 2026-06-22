# Fix: `ec set` does not refresh the open config window body

## Problem

With the Echo config window open, running `//ec set <text>` updates the on-screen
text overlay but the config window's `Text:` read-out stays stale until the window
is closed and reopened.

## Root cause

`echo.cmd_set` (`echo/echo.lua`) has two branches. When a staging session is open
(config window showing), the in-setup branch stages the new text and refreshes the
overlay `element`, but it never refreshes the config GUI body:

```lua
if settings_lib.in_setup() then
  settings_lib.stage_set(staged_settings, 'text', text)
  refresh_display(text, staged_settings.pos_x, staged_settings.pos_y)
  -- MISSING: gui body is never re-rendered, so the "Text:" read-out is stale
else
  ...
```

The config body is built by `build_tabs(s)`, which renders `'Text:  ' .. s.text`.
The analogous mutator `echo.change_pos` already does the correct thing — after
staging it calls `gui:set_tabs(build_tabs(staged_settings))` to re-render the body.
`cmd_set` is simply missing that one call.

## Fix

In the in-setup branch of `echo.cmd_set`, after staging + `refresh_display`, refresh
the config body the same way `change_pos` does:

```lua
if settings_lib.in_setup() then
  settings_lib.stage_set(staged_settings, 'text', text)
  refresh_display(text, staged_settings.pos_x, staged_settings.pos_y)
  if gui then
    gui:set_tabs(build_tabs(staged_settings))
  end
else
  ...
```

This mirrors `change_pos` exactly (guarded `if gui then ... end`, same `build_tabs`
call), so behavior, draggability, scroll position, and click-blocking are unaffected.
Out-of-setup behavior is untouched. `cmd_clear` already routes through `cmd_set`, so
clearing while the window is open is fixed for free.

## Tests

Add to `tests/echo/test_config_gui.lua`, mirroring the existing
"overlay drag-release ... refreshes body" test:

1. **`cmd_set inside setup refreshes the config body`** — open config, `cmd_set('NewText')`,
   assert the active tab's lines contain `Text:  NewText` and the gui is still open.
2. **`cmd_clear inside setup refreshes the config body`** — open config, `cmd_set('X')`,
   `cmd_clear()`, assert the active tab shows `Text:  ` (empty) and the gui stays open.

Read the active tab body via the gui's existing test surface (the same mechanism the
overlay-drag test uses to confirm `set_tabs` was called); no new accessor unless the
existing surface can't read tab lines, in which case add a minimal test-only reader.

Existing in-setup `cmd_set` tests (stages text only, leaves live unchanged, updates
element, no vfs write) must continue to pass — the new `set_tabs` call adds to them,
it does not change staging or persistence.

## Scope / non-goals

- Single-file source change (`echo/echo.lua`), one branch, ~3 lines.
- No `lib/settings` or `config_gui` changes.
- No README change (no command/config/library surface change).

## Workflow note

Single sequential task → implement directly in this session worktree (no per-task
worktrees). Run `lua tests/echo/run_tests.lua` green before opening the PR.
