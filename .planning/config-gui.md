# Plan: Configuration GUI (header / body / footer) for Echo + shared `config_gui` helper

## Goal

Give `echo` a minimally-viable **configuration GUI** opened with `//ec config`, and extract the
reusable window **chrome** into the settings library so every future addon supplies only its body.
A minimal config GUI becomes a requirement for all addons going forward.

The window has a **header** (addon name), a **body** (addon-supplied, a list of tabs), and a
**footer** with **Save** / **Discard** buttons that map to the existing `save` / `discard`
commands and close the window.

## Requirements (confirmed with user)

- **Shared helper:** new `lib/settings/config_gui.lua`. `settings.lua` stays pure data.
- **Open/close:** `config` while open is a **no-op**; closing via `save`/`discard` command behaves
  exactly like clicking the matching footer button.
- **Positioning:** drag the Echo text overlay to set `pos_x`/`pos_y` (persist on left-mouse-up).
  The config **window** is itself draggable (grab the header) and its anchor persists in new
  `config_x`/`config_y` settings keys via `stage_set`.
- **SAMPLE TEXT:** on open, if staged `text` is nil/empty, stage it to `'SAMPLE TEXT'`. No special
  case on save.
- **Addon-defined size:** `size = { width, height }` option (with defaults); widths and the
  right-edge scroll column derive from `width`, visible body rows from `height`.
- **Scrollable body:** fixed-height viewport with **up/down buttons on the right**; inert/hidden
  when content fits.
- **Tabs (first-class):** body is always a **list of tabs**; tab bar shown only with 2+ tabs.
- **Pluggable body:** a tab is either a **text tab** (`{title, lines}`, rendered + scrolled by
  `config_gui`) or a **custom tab** (`{title, render, on_mouse, hide}`) where the addon draws an
  interactive, possibly image-rich body into a provided viewport and receives body-relative mouse
  events. Makes Action-Picker-class GUIs buildable. Echo uses one text tab.
- **Clicks never pass through (hard requirement):** any mouse event over the open window is
  consumed (`handle_mouse` returns true → addon blocks it); only events outside fall through.

## `lib/settings/config_gui.lua` API

`config_gui.new(opts)` → controller; registers **no Windower events**, takes `texts` (and optional
`images`) by dependency injection.

```lua
opts = { texts, images?, title, on_save, on_discard, on_move, pos={x,y}, size={width,height} }

gui:show(tabs)        -- tabs = list; each tab is { title, lines } OR { title, render, on_mouse, hide }
gui:set_tabs(tabs)    -- replace content while open; re-clamp active index + per-tab scroll
gui:select_tab(i)
gui:scroll(delta)
gui:show()/hide()/is_open()
gui:set_draggable(b)
gui:handle_mouse(mtype, x, y, delta) -- returns true when consumed (over window) so addon blocks it
gui:destroy()
```

- **Layout:** background panel (full `size`, also the hit-region) + header + optional tab bar +
  body viewport + footer Save/Discard + right-side `▲`/`▼`. `layout(x,y)` tracks window rect
  `(x, y, size.width, size.height)`; `over_window(x,y)` = point-in-rect (used for blocking).
- **Body viewport** `vp = {x,y,width,height}` = window minus header/tab-bar/footer. Text tab →
  config_gui renders `lines` with scrolling; custom tab → `tab.render(vp, {texts, images})`,
  re-called on drag/`set_tabs`, with `tab.hide()` on switch-away / `gui:hide()`.
- **handle_mouse:** active drag takes precedence (move → `layout`, up → `on_move`). Else gate on
  `over_window`: chrome hits first (Save/Discard, tab labels, `▲`/`▼`, header-drag); else if over
  body viewport and active tab is custom → forward `on_mouse(x-vp.x, y-vp.y, mtype, delta)`; wheel
  over text tab → `scroll`. **Every event over the window returns true** (blocked).

## Files Affected

**Implementation**
- `lib/settings/config_gui.lua` — NEW shared chrome module
- `echo/echo.lua` — new `config_x`/`config_y` defaults; `gui` state; `build_tabs`,
  `stage_config_pos`; wire `init`/`setup_open`/`setup_close_save`/`setup_close_discard`/
  `change_pos`/`on_mouse`(+delta)/`on_logout`/`unload`/`print_help`; `get_gui()` accessor

**Tests**
- `tests/lib/settings/test_config_gui.lua` — NEW; `tests/lib/settings/run_tests.lua` register it;
  add a `texts` mock for the lib harness (incl. `:hover`)
- `tests/echo/test_config_gui.lua` — NEW; extend `test_lifecycle.lua`; `tests/echo/mock_windower.lua`
  add `:hover` + `_width/_height` to the texts mock

**Documentation**
- `CLAUDE.md` — expand **Configuration GUI** section (tabs/text-or-custom body, size, draggable,
  click-blocking; echo reference)
- `lib/settings/CLAUDE.md` — document `config_gui` API; clarify settings.lua stays pure
- `echo/README.md` — commands table + configuration section (`config_x`/`config_y`, drag, SAMPLE TEXT)
- `README.md` (top-level) — **add Echo to the Addons table** and **fix the stale Installation
  command names** (`setup`→`config`, `exit`→`save`, `exit -d`→`discard`)
- new-addon scaffold guidance (`.claude/commands/new-addon.md`) — mention wiring `config_gui`

## Tasks

| Task | Files | Agent | Notes |
|------|-------|-------|-------|
| A+B | `lib/settings/config_gui.lua`, `echo/echo.lua`, all tests + mocks | lua-dev | Combined: config_gui and echo are coupled (echo's tests need the real module), so implement together and test end-to-end. |
| Review | diff of A+B | lua-reviewer | Correctness, style, lib/settings rules, test coverage. lua-dev resolves all findings. |
| QA | full suite | lua-QA | `lua tests/lib/settings/run_tests.lua` + `lua tests/echo/run_tests.lua`. |
| C | docs files above | docs/lua-dev | After A+B/QA, for accurate wording. Includes top-level README fixes. |

## Verification

```bash
lua tests/lib/settings/run_tests.lua
lua tests/echo/run_tests.lua
```

In-game: `//lua r echo` → `//ec config` opens the window (header, body read-outs, Save/Discard).
Empty text shows `SAMPLE TEXT`. Drag the overlay → X/Y update on release. Drag the window header →
whole window moves. Second `//ec config` = no-op. **Save**/`//ec save` persists text + window
position and closes; **Discard**/`//ec discard` reverts and closes. Clicks on the window never
reach the game.
