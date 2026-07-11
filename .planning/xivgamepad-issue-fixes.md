# Plan: xivgamepad issue fixes — #25, #26, #27, #29, #30

**Base branch:** `work/xivgamepad` (PR #17) · **Worktree:** `.claude/worktrees/xivgamepad` · **Status:** awaiting approval

## Root-cause findings (verified against current code + tests)

### #25 — RT-held face buttons fire the left half
The dispatch/read/write chain (`execute_slot` → `display_target` → `content.slots[9..16]`, binder
write path) is provably correct and unit-tested; the issue's "right half stored as a copy of the
left" hypothesis is disproven. The real defect is a **timing window**: `trigger_held` context is
true the instant a trigger goes down, but `display.mode` only changes when the trigger's hold
gesture engages **0.12 s later** (`arm_hold` → `engage_display`). A face press inside that window
either fires the **stale previous mode** (rolling from LT to RT with brief overlap → left half
fires — the reported symptom) or is **silently dropped** (`display.mode` still nil on a fresh
trigger press). Fast play routinely lands presses inside 120 ms.

### #26 — bare START/BACK/A/B/X/Y do nothing
**No in-repo defect.** Every layer is correct and test-covered: wizard capture, keyboard scancode
resolution (press-time identity is remembered for release — verified directly), `compute_context`
→ bare dispatch, gesture defaults, real actions. The issue's own hypothesis ("faces are native
passthrough like the d-pad") is contradicted by the documented Steam Input profile, which emits
bare outputs for all six. Since #25 proves the face buttons DO emit keys while a trigger is held,
all-six-failing-bare points at the **user's Steam Input profile** emitting face/START/BACK outputs
only inside trigger layers (or not at all bare). Also: bare A = Enter (opens chat) and bare B =
Escape — easy to misread as "nothing." Repo-side remedy: close the coverage gap (no test drives a
bare face press through the keyboard→button→action boundary) and add a profile troubleshooting
section to the wiki; no code change, no debug logging.

### #29 — trigger-held + LB/RB target prev/next doesn't fire
Dispatch is correct and unit-tested after the anchor threshold passes. The in-repo defect is the
same silent-drop class as #25: `qualifying_anchor` requires the trigger held ≥ 0.12 s before the
bumper press counts, and a press inside that window is **dropped with no retry**. There is no
competing gesture on trigger+LB/RB that needs this disambiguation. (Independent residual risk,
in-game-only: whether synthesized Tab / Shift+Tab actually cycle targets in FFXI — already flagged
in the integration test plan.)

### #30 — RB-held direct-switch order wrong
Confirmed. `DIRECT_SWITCH_ORDER` must become Y, B, A, X, D-pad Up/Right/Down/Left. The issue's
one-line swap is **incomplete**: (a) two tests hard-code the current order; (b) two contract docs
state direct-switch shares `SLOT_INDEX` order (becomes false — `SLOT_INDEX` itself must NOT
change); (c) the integration plan's expected results change; and critically (d) **gestures are
persisted wholesale in settings.json and a saved array replaces code defaults on load** — existing
saves keep the old order forever without a migration.

### #27 — no RB-held set-selector indicator (enhancement)
No signal reaches the HUD today: `rb_held` exists only inside `gamepad.compute_context`, and the
HUD display callback fires only for XHB/WXHB/expand display actions. A new held-state hook is
required. Everything else needed already exists: show/hide-on-state HUD pattern
(`render_sc_timer`), active-set source (`state.view.active_set`), cluster layout offsets, and
shipped-but-unused controller art (`images/icons/iconpacks/default/ui/` d-pad/face-button PNGs +
per-button `binding_icons/`).

### Discovered adjacent defect (out of scope — file as a new issue)
BACK (Ctrl+'1') shares its base scancode with LT ('1'), START (Ctrl+'2') with RT ('2'); the
keyboard layer's key-down guard swallows BACK-while-LT-held and START-while-RT-held entirely.
This breaks `open_binder` (BACK in trigger_held) whenever the held trigger is LT. Not one of the
five issues; recommend filing separately rather than widening this change.

## Approach

All work sequential in the existing session worktree on `work/xivgamepad` (single PR #17), since
tasks T1–T3 all touch `gamepad.lua` and its tests.

- **T1 (#30):** Reorder `DIRECT_SWITCH_ORDER`; keep `SLOT_INDEX` unchanged; update the two
  hard-coded tests, both contract docs, and integration-plan expectations. Add a load-time
  migration that renumbers saved `direct_switch_*` gesture entries still matching the old factory
  defaults to the new order, leaving user-customized entries untouched; test the migration
  (old-default save → new order; customized save → preserved).
- **T2 (#25):** Resolve the target half at press time from held-trigger state instead of waiting
  for display engagement: engaged WXHB/expanded modes stay authoritative; otherwise the
  most-recently-pressed currently-held trigger determines the half (covers both the stale-mode
  and the nil-mode window). Handle the WXHB double-tap-pending edge deliberately. Amend the
  contract docs; add regression tests for roll-over, fast-press, and both-held windows.
- **T3 (#29):** Drop the anchor-hold gate for the reserved trigger-held LB/RB target gestures —
  fire immediately when a trigger is held (mode_switch's gate untouched). Amend contracts/tests;
  note the Tab/Shift+Tab in-game verification item remains open in the integration plan.
- **T4 (#26):** No behavior change. Add the missing keyboard→button→action boundary tests for
  bare A/B/X/Y/START/BACK; add a Steam-profile troubleshooting subsection to the wiki (bare
  outputs checklist, and that bare A/B are Enter/Escape by design). Issue gets closed with the
  external-cause explanation and that checklist.
- **T5 (#27):** RB-held set-selector overlay: new HUD element using the shipped cluster art,
  labeled 1–8 per the **new** #30 order with the active set highlighted; shown/hidden via a new
  RB-held hook from the button layer; position persisted and draggable during config per repo
  GUI rules; tests for show/hide, numbering, and highlight.

Then per workflow: reviewer loop (zero open issues) → QA full suite → README/docs pass → commit,
push, update PR #17 body (Fixes #25/#26/#27/#29/#30).

## Tasks

- [ ] T1 — #30 order swap + docs/tests + persisted-gestures migration
- [ ] T2 — #25 press-time half resolution + regression tests
- [ ] T3 — #29 remove reserved-target anchor gate + tests
- [ ] T4 — #26 boundary tests + wiki troubleshooting (no code change)
- [ ] T5 — #27 RB-held set-selector overlay
- [ ] Review loop → QA → docs → push/PR update
