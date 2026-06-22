# CLAUDE.md

## Project Overview

Lua addon scripts for Final Fantasy XI using the **Windower 4** framework. Each addon is a self-contained directory. Shared functionality lives in `lib/`. Tests live in `tests/`.

## Repository Structure

```
lib/settings/               # Shared settings library (required by all addons)
<addon-name>/
  <addon-name>.lua          # Main entry point
  README.md
  data/                     # All runtime-written and user-editable files
    <CharacterName>/        # Per-character settings (managed by settings library)
tests/
  lib/settings/             # Settings library tests
  <addon-name>/             # Per-addon tests (run_tests.lua, mock_windower.lua, test_*.lua)
```

**Never** write runtime or user-editable files to the addon root — all go under `data/`.

## Shared Libraries

All addons **must** use `lib/settings` for configuration management. Direct use of the Windower `config` library is not allowed. See [lib/settings/CLAUDE.md](lib/settings/CLAUDE.md) for the full API.

## Windower 4 Conventions

- **Lua version**: 5.1
- **Addon metadata**: `_addon.name`, `.author`, `.version`, `.commands = {'addonname', 'an'}` — full name + short alias; alias is required and is the primary user interface
- **Events**: register via `windower.register_event('load' | 'login' | 'logout' | 'unload' | 'addon command', fn)`
- **Common APIs**: `windower`, `texts`, `packets`, `res`, `files`
- `windower.ffxi.get_player()` returns **`nil`** before login — never index it unguarded

## Login Lifecycle

Addons load from `init.txt` before login and persist across character switches. Every addon **must**:

- **Defer on `load`** — only initialize if `settings.logged_in()`; otherwise wait for `login`
- **Re-initialize on `login`** — reload settings and refresh UI; `init()` must be idempotent (reuse UI element, clear any open setup session)
- **Clean up on `logout`** — hide UI, call `settings.discard()`, abandon staging

Failing these causes a nil-index crash on load and cross-character settings clobber on switch. `echo` is the reference implementation; `tests/echo/test_lifecycle.lua` is the template lifecycle test.

## Required Commands

Every addon must implement:

| Sub-command | Aliases | Behavior |
|-------------|---------|----------|
| `config`    | `c`     | Opens the configuration GUI |
| `save`      | `s`     | Saves staged changes and closes the GUI |
| `discard`   | `d`     | Discards staged changes and closes the GUI |
| `help`      |         | Prints available commands to chat |

Unknown commands fall through to `print_help()`.

## Configuration GUI (`config`)

Every addon **must** build its config GUI on the shared `lib/settings/config_gui` helper, which
renders the window **chrome** (header, optional tab bar, footer Save/Discard buttons, right-side
scroll buttons, image backdrop, dragging, and click-blocking). The addon supplies only the **body**
content. `echo` is the reference implementation; see [lib/settings/CLAUDE.md](lib/settings/CLAUDE.md)
for the `config_gui` API.

- **Header** shows the addon name; **footer** has **Save** / **Discard** buttons wired to the
  `save` / `discard` handlers — closing via command must behave exactly like clicking the button
- **Body is a list of tabs** (always a list, even for one tab; the tab bar is hidden when there is
  only one). Each tab is either a **text tab** (`{ title, lines }`, scrolled by the helper) or a
  **custom tab** (`{ title, render, on_mouse, hide }`) that draws an interactive body into a
  provided viewport — supports image-rich, clickable GUIs
- The addon defines the **body/content area** via `size`; the chrome (header, tab bar, footer, scroll
  column) wraps it and the **total window = body + chrome**; the body **scrolls** when content
  overflows the body area (up/down buttons on the right)
- `config` while the window is open is a **no-op**
- **Mouse events over the open window must be consumed** so clicks never pass through to the game
- GUI open/closed state is ephemeral — never persist it
- All reads/writes go through `lib/settings`; never access `data/` directly
- GUI operates on a **staging copy**; changes are not written until `save` commits them (`discard` drops them)
- GUI callbacks must delegate to named, testable functions — never modify state inline
- Any persistent UI element **must** be draggable during config; dragging disabled on close; position written via `settings.stage_set`

## Code Style

File layout order: `require` → `_addon` metadata → state → forward declarations → public functions (alpha) → private functions (alpha) → event registrations.

- 2-space indentation, snake_case, no semicolons
- Align `=` in multi-line table/variable declarations when it aids readability
- Avoid globals; localize frequently used upvalues
- CRLF (`\r\n`) line endings — enforced by `.gitattributes`

## Per-Addon README

Every `README.md` must cover: what the addon does, installation, a commands table (all commands with alias and description), configuration (settings in `data/{CharacterName}/settings.json`), and a libraries table (Windower/shared libs with purpose). Keep it current when commands, libraries, or config change.

## Testing

```bash
lua tests/<addon-name>/run_tests.lua
lua tests/lib/settings/run_tests.lua
```

Harness conventions:
- `mock_windower.lua` — stubs for `windower`, `texts`, and other globals
- `test_*.lua` — one file per logical area; `run_tests.lua` discovers and runs them all, exits non-zero on failure
- No live `data/` writes; no game client dependency; GUI logic tested by calling functions directly
- Staged-settings: `discard` must leave live settings unchanged; `save` must persist them

**Required lifecycle tests** (every addon): make `windower.ffxi._player` settable and assert:
- Load before login defers without crashing
- Login initializes settings and shows UI
- Character switch reloads new character's settings; no clobber of prior character's file
- Logout hides UI, discards staging; safe before init and outside setup

Reference: `tests/echo/test_lifecycle.lua`. In-game reload: `//lua r <addon-name>`

## Source Control

GitHub (`khowe085/ffxi-addons`), default branch `main`. Use `gh` CLI. All work lands via PR — never commit directly to `main`.

This repo follows git-flow: every work branch is **squash-merged** into `main`. When `main` advances mid-flight, sync it **into** the work branch with a no-fast-forward merge (`git fetch origin && git merge --no-ff origin/main`) — **never rebase** a work branch. Rebasing rewrites history and forces force-pushes across worktrees, and the final squash flattens the intermediate merge commits anyway, so rebase buys nothing.

## Development Workflow

> **MANDATORY — NO EXCEPTIONS.** This workflow applies to every change regardless of size. Do not edit any addon source file, test, or documentation until step 2 is complete and the user has approved the plan. Skipping or shortcutting any step wastes the user's tokens and is forbidden.

**Every session runs in its own git worktree** under `.claude/worktrees/<plan-name>/` (gitignored), checked out on a session branch `feat/<plan-name>` cut from freshly-fetched `origin/main`. This is what lets multiple planning and/or implementation sessions run at once without clobbering a shared working branch — each worktree has its own HEAD, index, and working directory. **Never check out `main` in a session worktree** (a branch can be checked out in only one worktree at a time); branch off `origin/main` and leave the primary clone parked on `main` as the canonical reference. The plan (`.planning/<plan-name>.md`) and its **Tasks** section — which defines the parallel work units — are authored on the session branch. To pick up PRs merged to `main` mid-flight, sync them **into** the session branch (`git merge --no-ff origin/main`); never rebase (see Source Control). The branch exists only to become the PR, and is squash-merged.

| # | Who | Action |
|---|-----|--------|
| 1 | **Orchestrator** | `git fetch origin`; create the session worktree + branch — `git worktree add -b feat/<plan-name> .claude/worktrees/<plan-name> origin/main`. All later steps run inside it. |
| 2 | **Plan agent** | Writes `.planning/<plan-name>.md` on the session branch; **STOP and wait for user approval** |
| 3 | **Orchestrator** | Decomposes into tasks; updates **Tasks** section in plan |
| 4 | **lua-dev** (per task, parallel) | Isolated worktree off the session branch; implements feature + tests |
| 5 | **lua-reviewer** (per task worktree) | Reviews for correctness, style, test coverage |
| 6 | **lua-dev** (per task worktree) | Resolves all reviewer issues before proceeding |
| 7 | **lua-QA** | Runs full test suite; failures loop back to step 4 |
| 8 | — | Merge task work onto `feat/<plan-name>`; remove the per-task worktree (`git worktree remove`) |
| 9 | **docs agent** | Updates `README.md` for each modified addon |
| 10 | **Orchestrator** | Push `feat/<plan-name>`; open PR (squash-merge); PR description = release notes |
| 11 | **Orchestrator** | On the user's **"merged"** confirmation: `git worktree remove .claude/worktrees/<plan-name>` → `git branch -D feat/<plan-name>` → `git worktree prune` |

**Rules**: applies to all work (features and bugfixes alike); no shortcuts; no inline edits; sessions never check out `main` or rebase the work branch — sync `main` in via `--no-ff` merge only; per-task worktrees are removed after their merge and the session worktree after the user confirms the PR merged; PR opened only after lua-QA approves.
