# Fix config GUI footer Save/Discard buttons

## Problem (reported)

In the config window (`lib/settings/config_gui`, exercised by `echo`):

1. The Save/Discard buttons render as a thin **blue/red strip**, and the button
   **text extends beyond** the colored strip (too tall / unaligned).
2. **Clicking the text does nothing** — only clicking the colored strip itself fires
   Save/Discard.
3. Clicking the colored strip fires the action **but the click also passes through to
   the game** — explicitly forbidden by the GUI contract ("Every mouse event over the
   open window is consumed").

## Root cause (read from `lib/settings/config_gui.lua`)

All three stem from the footer button implementation.

### Bugs 1 & 2 — visual mismatch + dead hit area

- The label elements `state.save` / `state.discard` are created with **no text
  formatting** (`txt.new('', { pos, flags })`, lines 150–151) — unlike `state.body`,
  which sets `text = { font, size }`. They render at Windower's **default font/size +
  padding**, which is taller and wider than the colored background.
- The colored backgrounds `save_bg` / `discard_bg` are sized to the **inset** button
  rect: `btn_h = ROW_HEIGHT - 2*BTN_VPAD = 18 - 6 = 12px` tall (layout, lines 481–508).
  The default-styled text overflows this 12px strip → "text extends beyond it."
- The hit-rects `state.rects.save` / `.discard` are set to that **same 12px inset strip**
  (layout, lines 536–537). The visible text that overflows the strip is **outside the
  hit-rect**, so `point_in(state.rects.save, …)` (handle_mouse, lines 221/225) misses →
  "clicking the text does nothing." (The click is still over the window, so it's silently
  swallowed and appears inert.)

### Bug 3 — click leaks to the game

A left click is a **down (mtype 1) + up (mtype 2)** pair. On a Save/Discard click:

1. **Down (mtype 1):** `handle_mouse` → over window → `point_in(save)` → `on_save()` runs.
   In `echo`, `on_save` = `setup_close_save`, which calls `gui:hide()` →
   `state.open = false`. `handle_mouse` returns `true` (down consumed). ✓
2. **Up (mtype 2):** `handle_mouse`'s first line is `if not state.open then return false end`
   (line 203). The window is now closed → returns **false** → `echo.on_mouse` returns
   `false` → **the mouse-up reaches the game.** Phantom click. ✗

The window closes on the *down*, orphaning the paired *up*. The existing test
`handle_mouse on closed window always returns false` encodes the closed-state passthrough,
but the contract violation is that a consumed down whose handler closed the window must
still consume its paired up.

## Fix

### Part A — buttons consume their paired mouse-up (Bug 3)

Minimal, targeted change in `gui:handle_mouse`. Add a `state.swallow_up` flag (init
`false` in `state`, reset to `false` in `gui:show`):

- When a left-down (mtype 1) fires `on_save`/`on_discard` and the handler **closed the
  window** (`state.open` is now false), set `state.swallow_up = true` and return `true`.
- At the very top of `handle_mouse`, **before** the `if not state.open` early-return:
  if `mtype == 2 and state.swallow_up`, clear the flag and return `true`.

This guarantees the up that pairs with a window-closing down is always consumed, while
leaving every other path unchanged:

- Drag start/end is unaffected — the dragging branch keeps precedence and we only arm
  `swallow_up` on a save/discard click that closes the window (drag never closes it).
- A fresh, never-opened gui has `swallow_up = false`, so
  `handle_mouse(2, …)` on a closed window still returns `false`
  (existing test stays green).
- Activation stays on mouse-**down**, so existing single-event click tests
  (`gui:handle_mouse(1, …)` → action fires) stay green without rewrites.

### Part B — button background, text, and hit-rect coincide (Bugs 1 & 2)

Make the colored button background, the label text, and the clickable hit-rect occupy
the **same region**, sized to contain the text:

- **Label formatting:** create `state.save` / `state.discard` with an explicit
  monospace `text = { font = BODY_FONT, size = <button font size> }`, transparent text
  background, and zero/known padding, so their rendered size is predictable and the
  colored `*_bg` image shows through behind them.
- **Button region:** grow the colored backgrounds and the hit-rects to (about) the full
  **footer row height** (`ROW_HEIGHT`) instead of the 12px inset, keeping the horizontal
  `BTN_MARGIN`/`BTN_GAP` insets. The text is centered within this region (compute the
  horizontal offset from the monospace glyph width `GLYPH_W × #label`; small fixed
  vertical inset). Background image, text, and `state.rects.save/.discard` all derive
  from one rect so they always line up — clicking anywhere on the visible button
  (text included) fires the action.

Positional invariants preserved (verified against existing tests):
`construction: footer sits within the window bottom`, `Save click fires`,
`Discard click fires`, `a gui built with no callbacks`, and
`footer buttons are inset within the window` (`save.y > anchor_y`,
`save.y + save.h <= anchor_y + height`, horizontal insets) all still hold with the
full-row button rect.

## Files to change

- `lib/settings/config_gui.lua` — `gui:handle_mouse` (Part A); `state` init + `gui:show`
  reset (Part A); button label `txt.new` formatting (Part B); `layout` button-region
  sizing for `save_bg`/`discard_bg`, the `save`/`discard` text, and
  `rects.save`/`.discard` (Part B).
- `tests/lib/settings/test_config_gui.lua` — add coverage:
  - **Bug 3:** a Save (and Discard) click whose handler closes the window consumes the
    paired mouse-up — `handle_mouse(1, …)` returns true and fires the handler,
    `handle_mouse(2, …)` on the now-closed window returns **true** (not false). A
    stray up on a never-opened gui still returns false.
  - **Bugs 1 & 2:** the Save/Discard hit-rect spans the full footer-row button height,
    and a click anywhere within the colored button region (top and bottom of the row,
    not just a 12px band) fires the action.
- `lib/settings/CLAUDE.md` — clarify the behavior contract bullet to note the paired
  mouse-up is consumed too (docs agent, if wording changes).
- `echo/README.md` — no change expected (no command/config/library changes).

## Out of scope

- No change to scrolling, tabs, dragging, custom-tab rendering, or the settings library.
- No change to `echo.lua` — the fix is entirely in the shared chrome helper.

## Test / verification plan

- `lua tests/lib/settings/run_tests.lua` and `lua tests/echo/run_tests.lua` — all green,
  including the new footer-button cases.
- The whole existing `test_config_gui.lua` suite must remain green (no regressions in
  layout, drag, scroll, tabs).

## Tasks

Part A and Part B touch the same two files (`config_gui.lua` and its test), so this is a
**single task** — splitting would create a merge conflict on the same functions for no
parallelism benefit.

### Task 1 — Footer button hit target, layout, and paired-up consumption

- **Worktree:** `.claude/worktrees/ffb-impl` on branch `feat/ffb-impl`, off
  `feat/fix-config-footer-buttons`.
- **Scope:** `lib/settings/config_gui.lua` + `tests/lib/settings/test_config_gui.lua`.
- **Deliverables:** Part A (swallow paired mouse-up) + Part B (button bg / text / hit-rect
  coincide, full-row hit target, centered formatted labels); new tests for both; whole
  existing suite stays green.
- **Done when:** `lua tests/lib/settings/run_tests.lua` and `lua tests/echo/run_tests.lua`
  both pass, reviewer issues resolved, QA green.
