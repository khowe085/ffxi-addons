# XIVGamepad — WXHB "Always Show" Display Option

## Context

FFXIV's own cross hotbar has an "always display" option for the WXHB (wide cross hotbar) half:
when on, that half stays visible on screen at standard/idle transparency even when you aren't
holding the trigger, so you can eyeball recast sweeps at a glance; you still have to hold the
trigger to actually press a WXHB button. This plan brings the same option to XIVGamepad's WXHB-L /
WXHB-R views.

**Hard constraint:** this is a **display-only** change. XIVGamepad's "Input philosophy: Hold-only"
(`.planning/xivgamepad.md`) and the gesture/activation state machine in `xivgamepad/gamepad.lua`
must not change in any way that affects when a slot actually fires. A d-pad/face press must keep
requiring the same hold gesture it requires today, with or without "always show" enabled. This
plan's job is to make the *HUD render* something while idle; it is explicitly not a mandate to
relax `gamepad.lua`'s hold thresholds, add a new gesture type, or let `execute_slot` dispatch
without the trigger held.

## Current Behavior — Investigation Findings

These are load-bearing facts discovered by reading `gamepad.lua`, `hud.lua`, and `xivgamepad.lua`;
they shape both the design questions and the approach below.

1. **The HUD is already visible almost all the time — "always show" is really "always show the
   right content."** `hud.lua` keeps all 16 slots rendered (`state.visible = true`) continuously
   except during cutscenes; there is no existing "hidden until a trigger is held" state. What
   changes today, on hold, is *which set's content* fills the two screen halves and *how
   transparent* each half is — not whether the HUD exists on screen at all. So this feature is
   about changing content-source-while-idle + a transparency value, not about summoning a
   previously-absent overlay.
2. **Idle fallback already shows something: the current active/cycling set.** When no gesture is
   engaged (`display.mode == nil`), `xivgamepad.lua`'s `build_view()` falls back to
   `live_settings.active_set`, and both screen halves (`half_left` = slots 1–8, `half_right` =
   slots 9–16) show that one set's two halves at `transparency_standard` (default `0`, fully
   opaque). Holding LT/RT doesn't add content, it re-labels one existing half "active"
   (`transparency_active`) and fades the other to `transparency_inactive` (default `100`,
   invisible).
3. **A screen half's content today comes from exactly one 16-slot "set position."** `build_view()`
   resolves one `position` (either `active_set`, or — while a WXHB/Expanded gesture is live —
   the position assigned to that mode via `display[mode]`) and hands `hud.refresh()` a single flat
   `slots[1..16]` array. `half_left`/`half_right` are just two 8-slot windows into that one array.
   There is currently no path for the two screen halves to show two *different* sets'
   content at the same time.
4. **`hud.lua` cannot resolve hotbar content on its own.** It never touches `storage.lua` or
   `shared_sets`/`job_sets`; it only renders whatever `slots` array `xivgamepad.lua` hands it via
   `hud.refresh(view)`. Any feature that wants a screen half to show a *different* set's content
   than what's currently resolved into `view` needs `xivgamepad.lua`'s `build_view()` to resolve
   that content and put it in the view — this is not a hud-internal-only change.
5. **`display[mode].half` already controls which screen half a WXHB/Expanded view lands on**
   (`active_half()` in `hud.lua`), independent of which trigger invokes it. So "WXHB-L" is not
   hard-wired to the left screen cluster — it's wherever its configured `half` points.
6. **Recast sweeps are already computed for every slot in the current view, unconditionally.**
   `hud.tick()` loops all 16 slot indices and computes `recast_remaining()` for whatever binding is
   in `view.slots[i]`, regardless of display mode, active/inactive half, or transparency. There is
   no "only sweep the active half" optimization to preserve or break. This means recast accuracy
   is a non-issue for whichever content ends up in the view — the open question is only *which*
   content is in the view while idle, not whether its sweep will animate correctly once it's there.
7. **`gamepad.lua` has zero awareness of settings or the HUD.** It only tracks button/hold state
   and reports `display.mode` transitions through a callback. It has no `always_show`-shaped
   concept today and, per the constraint above, doesn't need one — the display-callback contract
   (`gamepad.set_display_callback(fn)`, `fn(mode_or_nil)`) is unaffected either way.

## Design Decisions to Resolve

These are presented as investigation-informed options, not decisions — the orchestrator should
pose them to the user before implementation starts (also listed tersely in **Open Questions**).

1. **Toggle granularity.** FFXIV lets WXHB-L and WXHB-R be configured to always-show
   independently. XIVGamepad's `display` settings table is already keyed per view
   (`wxhb_l`, `wxhb_r`, `expand_lt_rt`, `expand_rt_lt`), so per-side toggles are a natural fit and
   match the FFXIV precedent the user cited. A single global toggle is simpler to reason about and
   configure but can't express "always show my healing WXHB but not my melee one."
2. **Scope: WXHB only, or Expanded too?** Expanded views (`expand_lt_rt`/`expand_rt_lt`) only ever
   engage while *both* triggers are held together — a rarer, more deliberate gesture than a single
   held trigger — and (per Finding 3) already share the same single-set-per-screen-half rendering
   path as WXHB. Extending "always show" to Expanded is mechanically similar but doubles the
   design/testing surface for a mode that's arguably less in need of passive glanceability (it's
   already a two-hand commitment to bring up). Needs an explicit answer either way.
3. **Transparency semantics for the new state.** Idle-but-configured-visible is a *fourth* distinct
   visual state, different from all three existing transparency keys:
   - `transparency_inactive` defaults to `100` (fully invisible) — reusing it would silently make
     "always show" invisible by default, defeating the feature.
   - `transparency_standard` currently governs the idle *active-set fallback* halves; reusing it
     would also change the opacity of unrelated idle content for players who only wanted the WXHB
     half affected.
   - A new dedicated key (e.g. something in the shape of `transparency_always_shown`) avoids both
     collisions but adds another settings row/concept. Needs a call on naming and whether it's one
     value shared by both WXHB sides or, consistent with decision 1, per-side.
4. **Where the flag(s) live in settings.** Two additive shapes fit the existing schema equally
   well: nested inside each `display[mode]` entry (e.g. a third field alongside `set`/`half`) so a
   view's assignment and its always-show flag travel together, or a new sibling top-level key
   (mirroring the shape of `display`) that keeps the "always show" concept visually separate on the
   Display tab. Both are backward-compatible additions (existing saved settings files simply lack
   the new field/key and get the default).
5. **Config GUI surface.** The Display tab is the natural home (it already owns the `display`
   table's set/half assignment, `hide_empty_slots`, and transparency rows). Needs a decision on
   whether it's one click-to-toggle row per WXHB view (matching the existing per-row click-zone
   pattern) or a single combined row — informed by decision 1's answer.
6. **View/contract shape.** Because of Finding 4, supporting two screen halves showing two
   different sets' content simultaneously is a small but real change to what `xivgamepad.lua`'s
   `build_view()` produces and what `hud.refresh(view)` receives — not just a `hud.lua`-internal
   tweak. This should be called out explicitly as a third small amendment to
   `.planning/xivgamepad-contracts.md` (following the base-addon and crossbar-port amendments
   already there), while confirming `gamepad.lua`'s contract section is untouched.

## Approach (high-level)

- **`gamepad.lua` is not modified.** It keeps reporting exactly the same live gesture-engaged
  `display.mode` transitions it does today; "always show" never influences whether or when a mode
  engages, and `execute_slot` dispatch continues to depend solely on `gamepad.lua`'s existing hold
  state. This is the load-bearing invariant that keeps the change display-only.
- **`xivgamepad.lua`'s view-building gains a second, settings-driven input alongside the live
  gesture mode.** Today `build_view()` answers one question ("what does the *live* mode want to
  show, or the idle active-set fallback"). It needs to answer that question *per screen half*
  instead of once globally: for each half, prefer the live/engaged content if a gesture currently
  owns that half; otherwise, if that half has an always-show-configured WXHB view assigned to it,
  resolve and show that view's content; otherwise, fall back to today's active-set behavior
  unchanged. This is the "hud needs to know both the live mode and the persistent configuration,
  and render whichever applies per half" shape the feature calls for.
- **`hud.lua`'s transparency resolution gains the new always-shown-but-idle state**, applied only
  to a half that is (a) not the live-engaged half and (b) covered by an enabled always-show flag —
  every other half/mode combination keeps its current transparency behavior byte-for-byte.
- **`config_ui.lua`'s Display tab gains rows/click-zones for the new setting(s)**, staged through
  the existing `on_change` → `settings.stage_set` path (no new staging mechanism), following the
  same pattern as the existing per-view set/half cycling rows.
- **Settings defaults add the new key(s) defaulted to off/false**, so a fresh install and every
  existing saved-settings file behave identically to today until a player opts in.
- No changes are anticipated to `action.lua`, `binder.lua`, `wizard.lua`, `tester.lua`, or
  `storage.lua` — the feature is confined to view-building (main), rendering (hud), and
  configuration (config_ui), plus settings defaults and docs.

## Task Decomposition

This is a single tightly-coupled feature (a settings default → config UI → main view-building →
hud rendering chain all describing the same new concept), not a set of independently developable
surfaces — per this repo's established "single-task session worktree" convention, it should be
implemented directly in the session worktree rather than split into parallel per-task worktrees.
Recommended sequential subtasks within that one task:

1. **Contracts amendment** — add the small third amendment to `xivgamepad-contracts.md`: the new
   settings key(s)/default, the `hud.refresh(view)` schema addition, and an explicit note that
   `gamepad.lua`'s contract is unchanged. Doing this first gives the rest of the work a frozen
   target.
2. **Settings defaults** — add the new key(s) to `xivgamepad.lua`'s `build_defaults()`.
3. **View-building (`xivgamepad.lua`)** — per-half content resolution as described in Approach.
4. **HUD rendering (`hud.lua`)** — new transparency state, wired to the view/settings additions.
5. **Config GUI (`config_ui.lua`)** — Display tab row(s) + staged mutator function(s).
6. **Tests** (see below).
7. **Docs** (see below).

## Testing

- **`test_hud.lua`** — new cases: a half configured always-show + idle shows the assigned view's
  content at the new transparency; a half without always-show enabled is unaffected and keeps
  today's idle active-set-fallback behavior; when a gesture engages a half that also has
  always-show configured, it uses the existing active-transparency behavior (live gesture always
  wins); recast-sweep animation for always-shown-but-idle content behaves like any other rendered
  slot (regression coverage for Finding 6, not new sweep logic). Full regression pass with the new
  setting(s) left at their default (off) to prove zero behavior change for existing users.
- **`test_config_ui.lua`** — staging/save/discard coverage for the new Display-tab row(s): toggle
  writes only to the staged copy, `save` commits it, `discard` reverts it, matching the existing
  per-row tests for set/half cycling.
- **`test_gamepad.lua`** — no new gamepad behavior to test, but add (or confirm via existing
  coverage) an explicit assertion that `execute_slot`/display-mode-engagement is unaffected by
  the new settings existing at all, since `gamepad.lua` never sees them — a regression guard for
  the display-only constraint.
- **`test_integration.lua`** — one end-to-end scenario chaining settings → `build_view` → `hud`
  for the always-show path, if the existing integration test's shape supports it.
- **`test_lifecycle.lua`** — confirm no changes needed (new settings key(s) should just load via
  the existing defaults-merge path; call out only if that assumption doesn't hold).

## Docs to Update

- `xivgamepad/README.md` — settings table gains the new key(s); Configuration GUI section
  mentions the new Display-tab control.
- `docs/xivgamepad/reference/settings-schema.md` — new row(s) in the top-level keys table and,
  if the flag nests inside `display[mode]`, an update to the `display` default code block.
- `docs/xivgamepad/wiki/Configuration.md` — Display tab section gains a bullet describing the new
  toggle and its transparency behavior, consistent with the existing `standard`/`active`/`inactive`
  bullet's style.

## Resolved Decisions (approved)

1. **Toggle granularity:** a **single global** `always_show_wxhb` flag controls both WXHB-L and
   WXHB-R together (not independent per-side flags).
2. **Scope:** **WXHB only** — the two Expanded views are unaffected.
3. **Transparency key:** **reuse `transparency_standard`** — no new transparency setting. This
   also means the always-shown-but-idle half renders identically to today's idle active-set
   fallback opacity, which is consistent since (per Finding 2) that fallback is already what
   "idle" looks like everywhere else in the HUD.
4. **Settings shape:** because the toggle is global (decision 1), it is a **single top-level
   settings key** (`always_show_wxhb`, default `false`) rather than nested per-mode inside
   `display[mode]` — nesting the same boolean identically into both `display.wxhb_l` and
   `display.wxhb_r` would be redundant duplicate state with no independent meaning. (This
   supersedes the plan's original "nested vs. sibling key" framing, which assumed per-side
   granularity; see `.planning/xivgamepad-contracts.md`'s "WXHB always-show amendment" for the
   frozen shape.)
5. **Contract scope:** confirmed — the small `hud.refresh(view)`-adjacent view-building change is
   documented as a third frozen amendment in `xivgamepad-contracts.md`; `gamepad.lua`'s contract
   and the activation model are untouched.
6. **Task execution:** single task, implemented directly in the session worktree (no new
   worktree/branch), per this repo's established single-task convention — sequential subtasks as
   listed above, with a lua-dev → lua-reviewer review cycle before lua-qa runs the full suite.
