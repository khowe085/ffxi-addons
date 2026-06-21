# Fix: Echo config-GUI chrome — overflow, drag, and button polish

## Problem

Five related defects in the Echo configuration window. All but the sizing change live in
the shared chrome helper `lib/settings/config_gui.lua`; Echo only supplies body content and
its window size.

| # | Reported symptom | Root cause |
|---|------------------|------------|
| 1 | Echo's body extends past the frame the settings library draws | `texts` elements size to content and cannot be pixel-clipped, and Windower exposes no public text-width measure and no reliable way to mask text with an image (texts draw above images). The body is only row-limited vertically — nothing bounds it horizontally, so Echo's long help lines run off the right edge, and the 320×160 window is too small for its content. |
| 2 | Save/Discard render 1–3 px outside the window perimeter | Footer buttons are positioned flush to the window edges (`x=0`, bottom row, right edge = exactly `width`). The default `texts` padding/stroke bleeds a few pixels past the backdrop. |
| 3 | Header / Save / Discard hit boxes are invisible → mis-clicks | The header and footer buttons have no drawn boundary; the user can't see where the clickable regions are. |
| 4 | Dragging the **body** moves the background, which then snaps back | The backdrop image is created with `flags = { draggable = false }`, but Windower's images honor native dragging unless `:draggable(false)` is also called on the element. So a body drag natively moves the `bg` image; on mouse-up outside the window Echo calls `change_pos → set_tabs → layout`, which re-pins `bg` to the anchor — the visible "snap back". |
| 5 | Buttons don't look like buttons; header/body/footer aren't delineated; drag should be header-only | No button backgrounds and no zone banding. Header-only dragging is already enforced in `handle_mouse` logic (it only starts a drag when the click is in the header rect); it just *appears* broken because of bug #4's native image drag. |

Note bugs #4 and #5's "drag only via header" share a fix: once the backdrop (and all chrome
elements) have native dragging disabled, the **only** way to move the window is the helper's
synthetic header drag, which already requires a click inside the header rect.

## Fix design

### `lib/settings/config_gui.lua` (shared chrome)

Keep `HEADER_ROWS = 1`, `FOOTER_ROWS = 1`, `TABBAR_ROWS = 1`, `ROW_HEIGHT = 18` unchanged so
`visible_rows`/body-height math (and the many lib tests that depend on it) are untouched. All
changes are visual banding, footer insets, and disabling native drag.

1. **Zone banding (bugs #3, #5).** When `images` is injected, draw three new image elements,
   repositioned in `layout()` alongside the existing `bg`:
   - `header_bg` — full-width band over the header row, a lighter/accent shade than the body
     backdrop (e.g. alpha ~235, a blue-grey).
   - `footer_bg` — full-width band over the footer row, same accent shade.
   - The body region keeps the existing dark `bg` backdrop, so header / body / footer read as
     three distinct horizontal zones.
   When `images` is **not** injected (some lib tests), these are simply absent — the window is
   chromeless but hit-testing is unchanged, exactly as today.

2. **Button-looking Save/Discard, inset inside the window (bugs #2, #3, #5).** Add `save_bg`
   and `discard_bg` image rectangles (a raised/accent button color, e.g. Save blue-grey,
   Discard red-grey) drawn behind the Save/Discard text. Introduce layout constants:
   - `BTN_MARGIN = 4` — inset from the window's left/right edges.
   - `BTN_GAP = 6` — gap between the two buttons at the horizontal mid-line.
   - `BTN_VPAD = 3` — vertical inset inside the footer row.
   The Save/Discard **hit-rects, text, and backgrounds** all move to these inset coordinates,
   so nothing renders outside the perimeter. Hit-rects shrink to the visible button, which is
   what the user clicks. (The footer band still spans the full width for the zone look.)

3. **Disable native dragging on every chrome element (bug #4).** After creation, call
   `:draggable(false)` on `bg`, `header_bg`, `footer_bg`, `save_bg`, `discard_bg`, `panel`,
   `header`, `body`, `save`, `discard`, `up`, `down`, and each tab label. Windower then never
   moves any element on its own; the window moves **only** via the helper's header drag. This
   removes the body-drag-moves-background behavior and the snap-back entirely.

4. **Body clipping via a monospace character grid (bug #1).** Since Windower can't pixel-clip
   `texts` or measure their width, the helper guarantees the body never exceeds its box by
   emitting only text that fits — in **both** axes — before it is drawn:
   - **Vertical:** the existing `visible_rows` row-limit (unchanged).
   - **Horizontal (new):** render the single body `texts` element in a **fixed-width font**
     so column width is constant and exact. Add constants `BODY_FONT = 'Consolas'`,
     `BODY_FONT_SIZE = 11`, and `GLYPH_W` (px advance per character, **matched to that
     font/size and rounded up** so the estimate is conservative and can never overflow). The
     body element is created with `text = { font = BODY_FONT, size = BODY_FONT_SIZE }`.
   - Compute `body_cols = max(1, floor((width - BUTTON_W - 2*BODY_PAD) / GLYPH_W))` and, when
     building the visible slice in `render_active`, truncate each line to `body_cols`,
     appending an ellipsis (`utf8.char(0x2026)` when available, else `...`, reserving its
     cell width) when a line was longer. Lines that already fit are emitted verbatim.
   - The render model stays a **single `\n`-joined body block** (not per-row elements).
   - This makes "clipping" deterministic and unit-testable as pure string math, with no
     dependence on z-order or runtime text metrics. (Assumes single-byte body text, which all
     current addons use; documented as such.) `GLYPH_W` is tuned/verified in-game; the unit
     tests assert the truncation *logic* against the constant, not absolute pixels.
   - **Custom tabs** (the `render(vp,…)` seam) are unaffected — the addon owns drawing within
     `vp` and remains responsible for staying inside it.

5. **Layout/show/hide/destroy plumbing.** `layout()` positions the new image bands and button
   backgrounds (so they track header drags); `show`/`hide_all`/`destroy` show/hide/destroy them
   alongside the existing elements. Guard every new element on `state.images` being present.

No public API change: `config_gui.new`, `show/hide/set_tabs/set_pos/set_draggable/handle_mouse/
destroy` signatures and the tab contract are all unchanged.

### `echo/echo.lua` (addon)

1. **Window size +150 px on both axes (bug #1):** `size = { width = 470, height = 310 }`
   (was 320×160), per the chosen option. This is now comfort headroom: at 470 px the body is
   ~64 monospace columns, so Echo's help lines fit *without* triggering the helper's ellipsis
   truncation. The helper's clip is the guarantee; the wider window keeps content un-truncated.
2. **Tidy the General-tab body lines** in `build_tabs` for readability (optional polish — they
   already fit the clipped 470-px body). No line needs manual width-trimming anymore.
3. No lifecycle, command, staging, or mouse-handling changes.

## Geometry impact on tests

- **`tests/lib/settings/test_config_gui.lua`** keeps the 320×160 fixtures. Footer clicks at
  `(10,152)` / `(200,152)` / `(250,152)` still land inside the inset Save/Discard rects
  (`BTN_MARGIN=4`, `BTN_GAP=6` ⇒ Save x∈[4,154], Discard x∈[166,316], button y∈[145,157] —
  152 is inside). The row/scroll math is unchanged, so all scrolling/tab/visible-row tests
  pass as-is. New assertions are **added** (see Test plan), existing ones are not loosened.
- **`tests/echo/test_config_gui.lua`** hardcodes the old 320×160 geometry in `save_point`,
  `discard_point`, `header_point`, and comments. These helpers/comments are updated for
  470×310 (footer `y = anchor + 310 - 9 = 301`; `half_w = 235`; Discard point moved into the
  right half, e.g. `anchor_x + 350`). All other Echo tests are geometry-agnostic.

## Test plan (added coverage)

In `tests/lib/settings/test_config_gui.lua`:
- **Footer buttons are inset within the window** — Save/Discard hit-rects' left/right/bottom
  edges are strictly inside `[anchor, anchor+width]` / above `anchor+height` (no edge equals
  the window border). Assert via `gui:_rects_for_test()`.
- **Native dragging disabled** — after `show`, `bg._draggable == false` and every chrome
  element (and tab labels) has `_draggable == false`. A move event over the **body** (not the
  header) does not re-anchor the window and fires no `on_move` (extends the existing
  body-click/`set_draggable(false)` cases to prove drag is header-only).
- **Zone bands created and tracked** — when `images` injected, `header_bg`/`footer_bg`/
  `save_bg`/`discard_bg` exist, are shown with the window, hidden on `hide`, destroyed on
  `destroy`, and shift by the drag delta in the "drag moves all elements together" test.
- **Chromeless still works** — with no `images`, no bands are created and clicks are still
  blocked (existing test extended).
- **Monospace body clip** — add a `gui:_body_cols_for_test()` accessor. Assert every rendered
  body line's length ≤ `body_cols`; a line longer than `body_cols` is truncated and ends with
  the ellipsis; a line that already fits is emitted verbatim. (Existing exact-line assertions
  like `'General line 1'` still pass because those lines fit at 320 px.)

In `tests/echo/test_config_gui.lua`:
- Update geometry helpers to 470×310; keep the existing Save/Discard-click, drag-stage-persist,
  discard-revert, and block-clicks assertions green at the new size.

## Constraints

- No public API change to `config_gui`; tab contract unchanged.
- Keep `HEADER_ROWS`/`FOOTER_ROWS`/`TABBAR_ROWS`/`ROW_HEIGHT` and the `visible_rows` formula
  intact so existing scroll/row tests are unaffected.
- All new visuals degrade gracefully when `images` is not injected.
- No new Windower events; no addon state in the helper (`texts`/`images` stay injected).
- No `os.execute`/shell-out. 2-space indent, snake_case, no semicolons, CRLF line endings.
- `data/` untouched; GUI open/closed state stays ephemeral.

## Tasks

- **Task 1 — `config_gui` chrome redesign + lib tests** (lua-dev)
  - Implement the monospace body + character-grid clip (constants `BODY_FONT`,
    `BODY_FONT_SIZE`, `GLYPH_W`, `BODY_PAD`; per-line truncate-with-ellipsis in
    `render_active`; `_body_cols_for_test` accessor), zone banding, inset button
    backgrounds/hit-rects, and `:draggable(false)` on all chrome elements per the Fix design.
    Update `layout`/`show`/`hide_all`/`destroy`.
  - Add the lib-test coverage above to `tests/lib/settings/test_config_gui.lua`; extend the
    mock only if a needed image/text method is missing (current mocks already support
    `pos/size/color/alpha/draggable`).
  - Run `lua tests/lib/settings/run_tests.lua`.

- **Task 2 — Echo sizing + body lines + echo tests** (lua-dev, after Task 1's button constants)
  - Set Echo's window to 470×310; shorten `build_tabs` lines to fit the wider body.
  - Update `tests/echo/test_config_gui.lua` geometry helpers/comments to 470×310.
  - Run `lua tests/echo/run_tests.lua`.

- **Task 3 — Docs** (docs agent)
  - `echo/README.md`: refresh the configuration section if it states the window size/zones.
  - `lib/settings/CLAUDE.md`: note the header/footer zone banding and button styling in the
    behavior contract if it adds clarity (drag-only-header is already documented).

## Orchestration note

Tasks 1 and 2 are implemented together by a single lua-dev pass (one branch, no separate
worktrees): the helper's footer-inset constants and Echo's test click-points are a shared
geometry contract, so splitting them would only create merge churn. Pipeline: lua-dev
(code + both test suites + docs) → lua-reviewer → lua-dev (resolve) → lua-QA (full suite) →
orchestrator commits/pushes/opens PR. The `feat/fix-echo-gui-chrome` branch is the isolation
from `main`.

## Out of scope

- No change to the tab system, scrolling, custom-tab seam, or `lib/settings/settings.lua`.
- No new icons/textures beyond solid-color image rectangles.
- No migration of existing `data/` settings.

## Verification (manual, in-game)

1. `//lua r echo`, log in, `//ec config`.
2. Window is visibly larger (470×310); the General body text is in a fixed-width font and fits
   inside the frame with no right-edge overflow. (Sanity-check the clip: temporarily feed an
   over-long line — it truncates with an ellipsis at the body's right edge instead of bleeding
   past it. Confirm `GLYPH_W` is conservative enough that real text never crosses the border.)
3. Header, Save, and Discard are visually distinct banded/buttoned regions; clicking them is
   unambiguous. Save/Discard sit fully inside the window border.
4. Dragging the **body** moves nothing (no background drift, no snap-back). Dragging the
   **header** moves the whole window as one unit. `//ec save` persists the new anchor.
