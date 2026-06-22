# Fix: settings directory creation never reaches the per-character folder

## Problem

After #8 ("Fix flashing console window") replaced the `os.execute('mkdir')` shell-out with a
native `windower.create_dir` walker, the Echo addon (and every addon using `lib/settings`) stopped
persisting settings, never created its `data/<Character>/` folders, and the game intermittently
froze hard enough to require a force close when running `//ec set`, `//ec clear`, or saving from
`//ec config`.

### Root cause (reproduced)

In-game, `windower.addon_path` is an **absolute** path with backslashes and a trailing
backslash, e.g. `C:\Program Files (x86)\Windower4\addons\echo\`. `settings_path` joins it as
`addon_path .. 'data/' .. char .. '/settings.json'`, producing a **mixed-separator absolute path**.

`io_provider.write_file` opens that path; when the directory does not yet exist the open fails and
it calls `ensure_dir(parent)`. The current `ensure_dir` (settings.lua:133) rebuilds the path from
the **filesystem root**, segment by segment, and creates each accumulated prefix. Reproduced with a
realistic path, every write therefore calls `windower.create_dir` seven times:

```
1. C:
2. C:/Program Files (x86)
3. C:/Program Files (x86)/Windower4
4. C:/Program Files (x86)/Windower4/addons
5. C:/Program Files (x86)/Windower4/addons/echo
6. C:/Program Files (x86)/Windower4/addons/echo/data
7. C:/Program Files (x86)/Windower4/addons/echo/data/Mychar
```

Three defects in that one behavior:

1. **Bogus drive-root create** — `create_dir("C:")` is meaningless and is attempted first.
2. **Wrong separators** — the path is reconstructed with `/` even though the source is a Windows
   `\` path; `windower.create_dir` (a thin `CreateDirectory` wrapper) is fed `C:/Program Files
   (x86)/...`, a format it does not reliably accept.
3. **Walks into protected system directories** — it calls `create_dir` on `C:`, `C:/Program Files
   (x86)`, etc. These are not writable by a non-elevated process; the calls fail (and may block or
   surface a Win32 error), and because the chain is built wrong the genuine leaf `…\data\Mychar`
   never gets created.

Consequences, all of which the user reported:

- **No `data/<Character>/` directory** — the leaf create never succeeds.
- **Settings never written** — with the leaf dir absent, the retry `io.open` fails and
  `write_file`'s `assert` raises; nothing lands on disk. (If the user pre-creates the folder by
  hand and the write *still* fails, the remaining suspect is a write-protected Windower install
  location — see Verification — but that is environmental, not this code path.)
- **Hard freeze / force close** — `//ec set`, `//ec clear`, and `//ec config` → **Save** all funnel
  through `commit → write_file`, so each fires the seven-call walk into protected/malformed paths on
  every save. That repeated, failing system-directory I/O is the most plausible cause of the
  client hang.

The bug is entirely inside `lib/settings/settings.lua`. **Echo needs no change** — it only calls
`settings_lib.commit`. The fix benefits every addon on the library.

## Fix design (`lib/settings/settings.lua`)

The addon root (`addon_path`) **always exists** — Windower creates it. The only directory the
library ever needs is `<addon_path>data/<Character>`. So never walk above `addon_path`; create
**only** the two directories beneath the known-existing root, parent-first, using a separator
consistent with `addon_path`.

1. **Replace the root-walking `ensure_dir` with a targeted `ensure_char_dir(addon_path)`** that:
   - returns early when `windower`/`windower.create_dir` is absent (keeps mock-less tests safe, as
     today);
   - detects the separator from `addon_path` (`\` if it contains one, else `/`);
   - strips any trailing separator to get `base`, resolves the character name via
     `windower.ffxi.get_player().name`;
   - calls `windower.create_dir(base .. sep .. 'data')` then
     `windower.create_dir(base .. sep .. 'data' .. sep .. char)` — exactly two calls, parent-first,
     uniform separators, never touching `C:` or any path above `addon_path`.

2. **Move directory creation into `commit`, lazily.** `commit` knows `addon_path`; the generic
   `write_file` does not, so dir-knowledge belongs here, not in the IO provider:
   ```lua
   local path    = settings_path(addon_path)
   local content = json.encode(staged)
   local ok = pcall(io_provider.write_file, path, content)
   if not ok then
     ensure_char_dir(addon_path)            -- targeted, anchored at addon_path
     io_provider.write_file(path, content)  -- retry; let a real failure propagate
   end
   ```
   Warm (folder already present): a single `io.open`, **zero** `create_dir` calls. Cold: one failed
   open, two targeted `create_dir`s, one successful retry. No per-save walk, ever.

3. **Simplify `write_file` back to pure IO** — open, assert-with-message, write, close. It no longer
   creates directories (that is `commit`'s job now), keeping the IO provider a clean, swappable
   read/write seam.

No public API change: `load`, `open_setup`, `stage_set`, `commit`, `discard`, `in_setup`,
`logged_in` signatures are untouched. `settings_path` is unchanged (Windows treats the mixed
`\`/`/` it produces as equivalent; the created leaf and the opened file resolve to the same folder).

## Test plan (`tests/lib/settings/`)

- **`test_write_file.lua`** — `write_file` is now pure IO:
  - Keep the **warm path** test: writing into an existing dir succeeds with no `create_dir` call.
  - Remove the old **cold path** test that asserted `write_file` internally walked `create_dir`
    (that responsibility has moved to `commit`).
  - Keep the **`os.execute` regression guard** (no shell-out may ever run).
- **New regression coverage for `commit`'s directory creation** (in `test_write_file.lua` or a small
  new `test_commit_dir.lua`), using a **Windows-style fixture** `addon_path = [[C:\…\echo\]]`:
  - Stub `windower.create_dir` as a recorder and a `_set_io_provider` whose `write_file` fails the
    first time (dir missing) and succeeds after the dirs are "created".
  - Assert `create_dir` is called with **exactly** `C:\…\echo\data` then `C:\…\echo\data\<char>`
    (parent-first, backslash-uniform) and **never** with `C:`, `C:/Program Files (x86)`, or any path
    above `addon_path`. This directly pins the demonstrated regression.
  - Assert the warm case (provider write succeeds first try) makes **zero** `create_dir` calls.
- Existing `test_load.lua` / `test_staging.lua` / `test_login.lua` use a mocked IO provider and the
  `create_dir`-absent guard, so they stay green without changes. Run the full lib suite:
  `lua tests/lib/settings/run_tests.lua`.
- Echo suite is unaffected but must stay green: `lua tests/echo/run_tests.lua`.

## Constraints

- No `os.execute` / `io.popen` / shell-out anywhere (keep the regression guard).
- No public API change to `lib/settings`; no Windower event registration in the library.
- 2-space indent, snake_case, no semicolons, CRLF line endings.
- Never walk above `addon_path`; create only the addon's own `data/<char>` subtree.

## Tasks

- **Task 1 — settings.lua dir-creation rewrite + lib tests** (lua-dev)
  - Replace `ensure_dir` with `ensure_char_dir(addon_path)`; add the lazy create-on-failure retry to
    `commit`; simplify `write_file` to pure IO per the Fix design.
  - Update `tests/lib/settings/test_write_file.lua` and add the Windows-path "no walk above
    addon_path / exactly two parent-first creates" regression test; keep the `os.execute` guard.
  - Run `lua tests/lib/settings/run_tests.lua` and `lua tests/echo/run_tests.lua`.

- **Task 2 — Docs** (docs agent)
  - `lib/settings/CLAUDE.md`: note that `commit` creates only the per-character `data/<Character>`
    folder beneath `addon_path` (native separators, no shell-out) if it adds clarity.
  - No `echo/README.md` change expected (it does not document the dir internals); confirm.

## Orchestration note

Single small change confined to `lib/settings/settings.lua` + its tests; one lua-dev pass on this
branch (no separate worktrees). Pipeline: lua-dev (code + lib tests) → lua-reviewer → lua-dev
(resolve) → lua-QA (full suite) → docs → orchestrator commits/pushes/opens PR.

## Out of scope

- The config-GUI chrome (#9) — unrelated; no changes here.
- `settings_path` separator normalization — left as-is (Windows-equivalent); can be revisited only
  if QA finds a real mismatch.
- Migrating any existing `data/` files.

## Verification (manual, in-game)

1. `//lua r echo`, log in.
2. `//ec set hello` — confirm `addons/echo/data/<Character>/settings.json` is created and contains
   the text; no console flash, no freeze. Repeat `//ec clear` and `//ec set …` several times — each
   completes instantly.
3. `//ec config`, change the overlay position, **Save** — confirm the file updates and the window
   closes without a hang.
4. `//lua r echo` and confirm the saved text/position reload for that character; switch characters
   and confirm a separate `data/<OtherCharacter>/settings.json` is created.
5. If writes still fail *after* this fix, check whether Windower is installed under a write-protected
   location (e.g. `C:\Program Files`); that is an environment/permissions issue, not this code.
