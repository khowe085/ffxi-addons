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

---

# Round 2 — button appearance refinements

After Round 1 shipped (PR #11, not yet merged), the buttons still look off. New
requirements (user feedback):

1. **Fixed width** — buttons are a fixed pixel width, not half the window each.
2. **Right-aligned** — the Save+Discard pair hugs the right edge of the footer
   (Save to the left of Discard), instead of spanning the whole width.
3. **Doubled height** — button height doubles from one row (18px) to two (36px).
4. **Text centered both horizontally AND vertically** within each button (Round 1
   centered horizontally only, with a fixed 2px vertical inset).

### Decision: `size` now describes the BODY area, not the total window

The body must be independent of chrome. So `opts.size` is reinterpreted as the
**scrollable body/content area**; the chrome (header, optional tab bar, footer, right-side
scroll-button column) is laid out **around** it, and the **total window is computed** from
body + chrome. Growing the footer grows the window downward; the body is untouched.

### Part C — sizing model (in `lib/settings/config_gui.lua`)

- Store the addon's `size` as the **body** dims: `state.body_w = size.width`,
  `state.body_h = size.height` (source of truth). Drop the assumption that
  `state.width/height` are addon-given.
- **Compute** the totals (in `layout`, since the tab bar is dynamic):
  - `top_rows = HEADER_ROWS + (has_tab_bar and TABBAR_ROWS or 0)`
  - `total_width  = body_w + BUTTON_W`  (scroll-button column is chrome, added at right)
  - `total_height = top_rows*ROW_HEIGHT + body_h + FOOTER_ROWS*ROW_HEIGHT`
  - `state.win` / `over_window` / the `bg` backdrop all use `total_width/total_height`.
- Re-base the body-dependent helpers on `body_w/body_h` so they **no longer subtract the
  footer**:
  - `body_viewport` → `{ x = anchor_x, y = anchor_y + top_rows*ROW_HEIGHT, width = body_w, height = body_h }`
  - `visible_rows`  → `floor(body_h / ROW_HEIGHT)` (independent of FOOTER_ROWS — the fix)
  - `body_cols`     → `floor((body_w - 2*BODY_PAD) / GLYPH_W)` (body_w already excludes the
    scroll column, so the old `- BUTTON_W` term goes away)
- `layout`: `body_top = top_rows*ROW_HEIGHT`; scroll buttons at `x = body_w` spanning
  `body_h`; `footer_y = top_rows*ROW_HEIGHT + body_h` (= `total_height - footer_h`);
  header/footer bands span `total_width`.

Net effect: changing `FOOTER_ROWS` (Part D) changes only `total_height`, never the body.

### Part D — button appearance (layered on Part C)

- `FOOTER_ROWS = 2` → footer 36px, `btn_h = FOOTER_ROWS * ROW_HEIGHT = 36` (doubled). This
  now adds 18px to the **window**, not subtracted from the body.
- New `BTN_W = 96` constant (fixed width; tunable). Right-aligned pair off `total_width`:
  - `discard_x = total_width - BTN_MARGIN - BTN_W`
  - `save_x    = discard_x - BTN_GAP - BTN_W`
  - both widths `= BTN_W`.
- **Center H + V:** `tx = btn_x + max(0, floor((BTN_W - GLYPH_W*#label)/2))`;
  `ty = btn_y + floor((btn_h - BTN_FONT_HEIGHT)/2)` with `BTN_FONT_HEIGHT` (~16 for size
  11) the estimated glyph height — replaces the fixed `BTN_TEXT_INSET`.
- One-shared-button-rect invariant from Round 1 preserved: colored bg, hit-rect, and
  centered label all derive from `{save_x|discard_x, btn_y, BTN_W, btn_h}`.

### Test impact (broad — `size` changes meaning, so window geometry changes everywhere)

This is the bulk of the work. Because every `gui:show({...}, size=…)` test previously read
`size` as the total window, the window bounds, footer position, and row counts all move.
Update — preferring to **read rects from `_rects_for_test()`** and derive expected bounds
from the new formulas rather than re-hard-coding magic pixels:

- `tests/lib/settings/test_config_gui.lua`:
  - **Window-bounds / consume tests** (`construction honors size`, `click outside …`,
    `set_pos …`, drag re-anchor tests): recompute the far corner / "just outside" points
    from `total_width = body_w + BUTTON_W`, `total_height = top_rows*18 + body_h + 36`.
  - **Row-count tests** (`text scrolling …`, `per-tab scroll offsets`,
    `visible_rows scales with height`): `visible_rows = floor(body_h/18)` now (e.g.
    `height=160` body ⇒ **8** rows, not 6). Rewrite comments + shown/hidden assertions.
  - **Footer click tests** (`construction: footer sits within the window bottom`,
    `Save/Discard click fires`, Round-1 full-height + swallow-up tests, `no callbacks`):
    footer is at the **new computed** `footer_y` and buttons are right-aligned fixed-width
    — source click coords from the rects.
  - Add assertions: body viewport size `== size` regardless of `FOOTER_ROWS`;
    `total_height` grows by exactly `ROW_HEIGHT` when `FOOTER_ROWS` goes 1→2 (guard the
    "footer independent of body" property); pair right-aligned
    (`discard.x + discard.w == anchor_x + total_width - BTN_MARGIN`); `save.h == 36`.
  - Scroll-button click tests: buttons now at `x = body_w` (not `width - BUTTON_W`).
- `tests/echo/test_config_gui.lua`: rewrite the `save_point`/`discard_point` helpers
  (lines 52–58) + comment (47–51) for the new geometry. With echo body `380×110`
  (the implemented value): `total_width = 398`, header 18 + body 110 + footer 36 ⇒
  `total_height = 164`; footer `[128,164)`, center y ≈ 146; Discard `[298,394)`
  center x ≈ 346, Save `[196,292)` center x ≈ 244. Other echo tests (header_point, drag)
  may shift too — verify the whole file.

### Affected docs & addon source (now in scope)

- `lib/settings/CLAUDE.md` and root `CLAUDE.md` — the contract currently says *"the addon
  defines the window size; the body scrolls within it."* Reword to: the addon defines the
  **body** area; the chrome wraps it; the window total is body + chrome; the body scrolls
  when content overflows the body area.
- `echo/echo.lua` — `size` now means the body area. Echo's body content is ~5 lines, so the
  current `470×310` would yield an oversized window. Set it to `width = 380, height = 110`
  (≈53 cols ≥ the longest ~51-char line; 6 rows ≥ 5 lines) so echo looks right under the new
  model. `echo/README.md` config wording updated only if it mentions window size (it does
  not list size today).

### Out of scope (unchanged)

- The swallow-up / paired-up fix and the one-shared-button-rect approach from Round 1
  stay; no change to staging, tabs behavior, drag mechanics, or custom-tab seam **semantics**
  (their geometry just follows the new body-based layout).

### Round-2 orchestration note

Single sequential task on the **already-open PR #11 branch**
(`feat/fix-config-footer-buttons`). To avoid the Round-1 per-task-worktree fragility (its
dir was auto-cleaned mid-flow), lua-dev implements **directly in the session worktree**;
then lua-reviewer → lua-QA → commit → push (PR #11 updates in place).

### Round 2 — Tasks

**Task R2-1 — Body-based sizing model + fixed-width/right-aligned/double-height/centered
footer buttons.** Scope: `lib/settings/config_gui.lua`, `tests/lib/settings/test_config_gui.lua`,
`tests/echo/test_config_gui.lua`, `echo/echo.lua` (size value), `lib/settings/CLAUDE.md` +
root `CLAUDE.md` (contract wording). Done when both suites are green (incl. a new
"footer height does not change the body viewport" test), reviewer issues resolved, QA green.
