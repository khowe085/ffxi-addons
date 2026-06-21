# Fix: flashing console window on every settings save

## Problem

Running `ec set <text>` or `ec clear` (and any equivalent save in any addon) makes a
small window pop up and instantly vanish in-game.

The window is a **Windows `cmd.exe` console**, not the addon's config GUI. It is spawned
by the shared settings library, not by echo.

### Root cause

`lib/settings/settings.lua` — the default `io_provider.write_file`:

```lua
write_file = function(path, content)
  local dir = path:match('^(.*)[/\\][^/\\]+$')
  if dir then
    os.execute('mkdir -p "' .. dir .. '" 2>/dev/null')   -- spawns cmd.exe
    os.execute('md "' .. dir:gsub('/', '\\') .. '" 2>nul') -- spawns cmd.exe
  end
  local f = assert(io.open(path, 'w'), 'cannot open for writing: ' .. path)
  f:write(content)
  f:close()
end
```

Both `os.execute` calls shell out through `cmd.exe`, each flashing a console window.
This runs on **every** write, not just the first — so it fires on each `set`/`clear`.

Call chain: `echo.cmd_set` → `settings_lib.commit` → `io_provider.write_file` → `os.execute`.

This affects **all addons** that use `lib/settings`, not just echo. Existing tests never
catch it because every test swaps in a mock `io_provider`, so the real `write_file` is
never executed.

## Fix

Rewrite `write_file` in `lib/settings/settings.lua` so it:

1. **Tries to open the file directly first.** When the directory already exists (the
   common case — true for every save after the first per character), no directory
   creation runs at all, so no console window ever appears.
2. **Only creates the directory when the open fails**, then retries the open once.
3. **Uses Windower's native `windower.create_dir`** for directory creation. This is an
   in-process API and spawns **no** console window. Create parent directories
   progressively since `create_dir` is not recursive (path is
   `<addon>/data/<CharacterName>/` — `data` then `data/<CharacterName>`).

**No `os.execute` / shell-out of any kind** — both existing `os.execute` lines (`mkdir -p`
and `md`) are deleted with no replacement shell-out. Per user directive, `os.execute` must
never be called without explicit approval. The production runtime is always Windower, so
`windower.create_dir` is always present; tests mock `io_provider`, so the real `write_file`
path never runs there. If `windower.create_dir` is somehow unavailable, the existing
`assert(io.open(...))` surfaces a clear error rather than silently shelling out.

Net effect in-game: zero console windows on the cold path (native API) and zero on every
subsequent save (directory already exists, no creation attempted). Zero `os.execute` calls
remain anywhere in the codebase.

## Constraints

- Keep the injectable `io_provider` seam intact (`_set_io_provider`) so existing tests are
  unaffected.
- No behavior change to `load`, `commit`, staging, or the public API.
- Preserve the `assert(... 'cannot open for writing: ' .. path)` error contract.
- CRLF line endings; 2-space indent; existing code style.

## Tasks

- **Task 1 — lib/settings write_file rewrite + test** (lua-dev)
  - Rewrite `io_provider.write_file` per the Fix section; add an `ensure_dir` helper that
    creates directories **only** via `windower.create_dir` (progressive parents). No
    `os.execute` / `io.popen` / shell-out anywhere.
  - Add a focused test under `tests/lib/settings/` that exercises the **real** default
    `write_file` (not the mock) against a temp directory: asserts content is written, a
    missing directory is auto-created via a stubbed `windower.create_dir`, and that
    `os.execute` is never invoked (e.g. stub `os.execute` to fail the test if called).
  - Run `lua tests/lib/settings/run_tests.lua` and `lua tests/echo/run_tests.lua`.

## Out of scope

- No changes to echo or its config GUI.
- No migration of existing `data/` files.

## Verification (manual, in-game)

1. `//lua r echo`, log in.
2. `//ec set hello world` — text shows, **no** console window flash.
3. `//ec clear` — text clears, **no** console window flash.
4. First-ever save for a brand-new character still creates `data/<Char>/settings.json`.
