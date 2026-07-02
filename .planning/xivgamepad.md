# XIVGamepad — Implementation Plan

## Context

Clean-room replacement for xivcrossbar. XIVGamepad brings the Final Fantasy XIV cross hotbar
gamepad experience to FFXI as a fully conventional monorepo addon. Physical controller input is
shaped externally by Steam Input. No code from xivcrossbar is carried over (study for reference
only; it is a separately licensed BSD-3 fork). No AutoHotkey support.

**Input philosophy:** Hold-only (hold a trigger, then press a button). All gesture logic lives in
the addon so it is unit-testable; Steam Input is kept as thin as possible.

### Steam Input constraint (amended)

- Each physical control maps 1:1 to at most one keyboard key. There are **no chords**; the only
  deviation is the d-pad hold-layer below.
- **The d-pad hold-layer.** The d-pad stays **native controller input** whenever no modifier is held,
  so FFXI's own party/alliance/menu targeting is preserved unchanged (including alliance members,
  which the addon does not reimplement). Steam activates a single momentary layer while **LT, RT, or
  RB** is held, remapping the four d-pad directions to keys the addon reads — momentary (tied to a
  physical hold), conceptually how FFXIV's own cross hotbar behaves. This layer is needed only
  because party/alliance targeting has no keyboard equivalent; inputs that *do* have one (e.g. the
  camera) are simply mapped 1:1 and handled in the addon.
- No chords, and no action layers or mode shifts beyond that one d-pad hold-layer. Everything else,
  camera zoom included, is resolved in the addon.
- The same momentary-layer mechanism is reused for **right-stick zoom**: while **LB** is held,
  Steam remaps the right stick's vertical axis off the arrow keys onto addon-read keys, so zoom
  (below) does not fight the native camera pan.

---

## Resolved Decisions (pre-planning, 2026-07-02)

These decisions are authoritative and **supersede any conflicting detail elsewhere in this
document**. They are gated by the input spike (`xivgamepad-spike.md`), which must pass before any
module work begins.

1. **Key map = quiet-key model with menu-key faces.** Primary buttons (d-pad hold-layer, `LT`/`RT`,
   `LB`/`RB`, `BACK`) map to **quiet F-keys** FFXI does not use; the four **face buttons map to
   `Enter` / `Escape` / `NumPad −` / `NumPad +`** (the `FFXI_Input.py` layout). The right stick maps
   to the **arrow keys** (native camera). Paddles/trackpad are **unmapped by default** (assigned via
   the wizard if the hardware has them). The owned/suppressed set therefore contains **zero
   held-state camera keys** — the one class `return true` cannot block — so suppression is reliable
   for everything owned. The old default map (brackets/semicolon/number-row/NumPad-dpad) is void.
2. **Face buttons: bare passthrough for all four.** A **bare** (no-trigger) press of any face button
   passes through to drive FFXI's **native menus** (confirm / cancel / menu / window-focus). While a
   trigger is held, all four are **consumed on both edges** (slot execution) — tracked per captured
   key, independent of whether the trigger is still held at release. Consequence: bare face presses
   are reserved for native menus, so **no-modifier custom gestures must be hosted on paddles,
   trackpad, `BACK`, or the bumpers** — not on face buttons.
3. **Suppression signals.** Gesture dispatch and input consumption suspend while any of:
   `get_info().menu_open`, `get_info().chat_open`, or cutscene (status id 4) is true. Because owned
   keys are F-keys (not text keys), there is **no "let the number row type through" carve-out** — that
   complexity is dropped.
4. **RB/LB precedence (unambiguous).** If **any trigger (LT/RT) is held**, `LB = target_previous` and
   `RB = target_next`, full stop. **Direct-switch** (`switch_set_N`, RB held + face/d-pad) and
   **`mode_switch`** (LB held + RB press) require **no trigger held**. Every `(button × context)`
   resolves to exactly one action.
5. **Timing = wall-clock.** All hold/tap/double-tap/expanded thresholds and windows use Windower's
   wall-clock scheduler (`coroutine.schedule`), **not** prerender frame ticks (which drift with frame
   rate). prerender is used only for any continuous per-tick effect. Tests stub the scheduler.
6. **Zoom = LB + right stick.** With **no trigger held**, **LB held + right-stick up/down** →
   `zoom_in` / `zoom_out`, which the action module fires as native keystrokes via `setkey`
   (`.` = zoom in, `,` = zoom out; exact token confirmed by the spike). Steam's LB momentary layer
   (above) makes the right-stick vertical emit addon-read keys so pan and zoom do not collide.
7. **State refresh.** Player state refreshes on its events (buff gain/loss, job/subjob change, mount)
   **and** on `zone change`, **plus** a ~1 s **poll-and-diff** reconciliation: read buffs/job/mount,
   compare to cached state, and re-resolve overlays + refresh the HUD **only on change** (dirty flag).
   This also captures buffs already active at login / zone-in that the event handlers miss.

---

## Architecture: 4 Modules + Storage + Main Entry Point

| Component | File | Responsibility |
|-----------|------|----------------|
| Main | `xivgamepad/xivgamepad.lua` | Lifecycle, command dispatch, wires modules, owns runtime state (player_state, mode flags) |
| Input | `xivgamepad/input/keyboard.lua` | Windower keyboard events → virtual button press/release callbacks |
| Gamepad | `xivgamepad/gamepad.lua` | Virtual button state, modifier tracking, gesture resolution, fires gesture callbacks |
| Action | `xivgamepad/action.lua` | Modular action/binding-type registry, overlay resolver, execution engine, built-in actions |
| Frontend | `xivgamepad/frontend.lua` | HUD, config GUI (lib/settings config_gui), binder UI, gamepad tester, key-capture wizard |
| Storage | `xivgamepad/storage.lua` | Hotbar set/binding file I/O (Windower `files` API) |
| Logging | `xivgamepad/log.lua` | Central debug/echo logging; `//xg debugmode` toggle; mirrors to chat + `data/debug.log` |

**Input flow:**
```
Steam Input → Keyboard Events (Windower) → Input module → Virtual Button Events
    → Gamepad module → (modifier state × button) → Gesture Fired → Action module → Game Effect
    → Frontend (HUD update)
```

---

## Input Model (Hold-only, addon-resolved)

- **Always mapped 1:1** (addon sees every press/release): `LT`, `RT`, `LB`, `RB`, `BACK`, the four
  face buttons (`A`, `B`, `X`, `Y`), and any enabled back paddles / trackpad zones. The `key_mapping`
  setting translates keyboard key codes to these virtual button names.
- **Right stick** (`RSTICK_UP` / `RSTICK_DOWN` / `RSTICK_LEFT` / `RSTICK_RIGHT`): mapped 1:1 to the
  keyboard camera arrow keys, so it drives the native FFXI camera exactly like a joystick when no
  modifier is held (the addon passes these through). Camera **zoom in/out** is an **addon gesture**
  (per Resolved Decision 6: no trigger + **LB** held + right-stick up/down → `zoom_in` / `zoom_out`,
  fired as native `setkey . / ,`). While LB is held, Steam's momentary layer remaps the right-stick
  vertical off the arrow keys onto addon-read keys so zoom does not also pan the camera.
- **D-pad** (`DPAD_UP/DOWN/LEFT/RIGHT`): only ever seen by the addon while a modifier (LT/RT/RB) is
  held — see the Steam Input constraint above. When no modifier is held the d-pad is native.
- **No chords.** The gamepad module resolves every gesture from **(active modifier state × physical
  button)**. Because the addon can see LT/RT/RB hold state directly, it does not need Steam to encode
  combinations into unique keys.
- Face buttons are always keyboard keys (the native-gamepad-passthrough alternative was weighed and
  declined) and context-routed by the addon: **no modifier → passes through to FFXI's native menus**
  (Resolved Decision 2); trigger held → hotbar slot; binder open → binder navigation.
  - **Default keys:** `A`/`B`/`X`/`Y` → `Enter` / `Escape` / `NumPad -` / `NumPad +` (the
    `FFXI_Input.py` layout). All four are FFXI **menu keys** (confirm / cancel / menu / window-focus),
    so an unbound bare press drives the native menu. The wizard still captures the actual codes.
  - **Consume-both-edges invariant (load-bearing, all four faces):** any face key the addon consumes
    on key-down while a trigger is held is also consumed on its key-up — tracked per captured key,
    *independent of whether the trigger is still held at release*. Without it, releasing the trigger
    before the face button leaks the key-up to the game (a stray `Enter` opens the chat bar; a stray
    `Escape` opens the menu) mid-combat.
  - **Bare-press routing.** With no trigger held, all four face keys **pass through** — the addon
    consumes neither edge — so they drive FFXI's native menus. While a trigger is held they are
    consumed (slot execution). Because bare presses are reserved for native menus, face buttons cannot
    host a no-modifier custom gesture (see **Custom / user-added gestures**).
  - **Menu / cutscene / chat suspend.** The addon is dormant and blocks nothing during cutscenes
    (status 4), while a menu is open (`get_info().menu_open`), and while chat is open
    (`get_info().chat_open`) — Resolved Decisions 3 / 4a. `menu_open` is the clean in-menu-yield signal
    (previously flagged as an open risk; now resolved).
- **Input ownership (suppression while loaded).** While loaded and active, the addon **owns every
  mapped key**: it returns `true` from the keyboard handler so FFXI never acts on them, and
  **releases them on unload** (its keyboard handler simply stops running). Because the owned set is
  **quiet F-keys plus the four face menu-keys** and contains **no held-state camera keys** (Resolved
  Decision 1), `return true` alone is sufficient — no owned key needs an FFXI-side `bind noop` (the
  spike, `xivgamepad-spike.md`, confirms this before module work). Dispatch and blocking also suspend
  during cutscenes, while a menu is open (`get_info().menu_open`), and while chat is open
  (`get_info().chat_open`) — Resolved Decision 3. Carve-outs: the right-stick **camera arrow keys pass
  through** (native camera), and **all four face buttons pass through on a *bare* press** to drive
  native menus, suppressed only while a trigger is held via the consume-both-edges rule. Because owned
  keys are quiet F-keys, there is no number-row/punctuation "type-through" problem to solve.
- Extended buttons — back paddles (`L4/L5/R4/R5`) and the 8 **trackpad zones** (`TRACKPAD_1..8`) — are
  **unmapped by default** and **carry no default gestures**: they are standalone hosts you bind in the
  Gestures tab (after mapping them via the wizard). Once mapped, they are owned/suppressed like the
  other quiet keys.

---

## Hotbar Sets and Display Modes

### Working set (8 in memory, per-character)
- The addon loads **8 set positions** into memory. Each position (1–8) has:
  - a **source flag** — `shared` or `job` — chosen in config, which selects where its content is
    pulled from (see Storage Model);
  - a **name** and a **skip_cycle** flag.
- Each set has **16 slots** split into left (1–8) and right (9–16) halves. Slots may be empty or hold
  a binding (type + parameters + optional overlays).

**Default set configuration (source + skip_cycle per position):**

| Position | Source | skip_cycle |
|----------|--------|------------|
| 1 | job | false |
| 2 | job | false |
| 3 | job | true |
| 4 | job | true |
| 5 | job | true |
| 6 | shared | false |
| 7 | shared | true |
| 8 | shared | false |

### Mode
- The player is always in **shared mode** or **job mode**; a gesture switches between them (analogous
  to FFXIV weapon draw/sheathe, which FFXI lacks).
- Mode determines which pool the XHB cycles through. Mode is tracked independently of the currently
  displayed set: jumping directly to a set does not change the cycling pool.

### Display Modes (6 views)

| View | Gesture | Set shown | Half shown |
|------|---------|-----------|------------|
| XHB-L | Hold LT | Current cycling set | Left 8 (1–8) |
| XHB-R | Hold RT | Current cycling set | Right 8 (9–16) |
| WXHB-L | Double-tap LT | User-assigned set | User-configured half |
| WXHB-R | Double-tap RT | User-assigned set | User-configured half |
| Expanded LT→RT | Hold LT then RT | User-assigned set | User-configured half |
| Expanded RT→LT | Hold RT then LT | User-assigned set | User-configured half |

Each non-XHB display mode is configured with a set name + half (left or right 8) in settings.

### Slot addressing (relative to the displayed half)
- Within whichever half is currently displayed, the **d-pad directions map to slots 1–4** and the
  **face buttons map to slots 5–8**, in FFXIV's positional order.
- This mapping is **relative to the activated/displayed half**, not a fixed 1–16 index. XHB-L shows
  the set's left 8; XHB-R shows the right 8; WXHB/Expanded show the assigned set's configured half —
  in every case the eight physical buttons address the eight displayed slots. This removes any
  coupling between the physical trigger and a fixed slot-number range.

### XHB Set Cycling
- A gesture cycles the XHB to the next set in the current mode's pool.
- Sets with no bindings, or individually marked skip_cycle, are skipped.
- Eight direct-switch gestures (hold RB + face/d-pad → positions 1–8) jump to any set regardless of
  current mode; mode does not change.

---

## Gestures (Gamepad Module)

### Gesture Types

| Gesture type | Example | Timing parameters (configurable) |
|---|---|---|
| `button` | Slot press (face/d-pad) | none; fires **once** on key-down — does not repeat while held |
| `tap` | Tap LB | max hold duration to count as a tap |
| `hold` | Hold LT (XHB); hold RS up/down (zoom) | min hold to engage; **stays engaged until release** — the handler may act each tick while engaged |
| `double_tap` | Double-tap+hold LT | max gap between release and second press; min hold on second press |
| `hold_then_hold` | Hold LT then hold RT | independent hold thresholds for each trigger |
| `hold_then_press` | Hold LB + press RB | min anchor-hold before a press is accepted |

All timing parameters are stored per-gesture in settings and are user-configurable. Per Resolved
Decision 5, hold/tap/double-tap/expanded thresholds use Windower's **wall-clock scheduler**
(`coroutine.schedule`, seconds), **not** `prerender` frame ticks (which drift with frame rate) and not
`os.clock`; prerender is used only for any continuous per-tick effect. Tests stub the scheduler. The
WXHB double-tap window defaults to ≈FFXIV's ~333 ms.

### Default gestures (resolved as modifier × button)

| Gesture | Type | Buttons | Action |
|---|---|---|---|
| Auto-run | `tap` | LB | `auto_run` |
| Cycle sets | `tap` | RB | `cycle_set` |
| Zoom in / out | `hold` | no trigger + hold LB + RSTICK_UP / RSTICK_DOWN (LB layer) | `zoom_in` / `zoom_out` (fires `setkey . / ,`; engaged while held) |
| Mode switch / dismount | `hold_then_press` | hold LB + press RB (no trigger held) | `mode_switch` |
| Direct-switch sets 1–8 | `button` | hold RB + face/d-pad (8 combos) | `switch_set_1` … `switch_set_8` |
| Previous / next target | `hold_then_press` | hold LT/RT (either or both), press LB / RB | `target_previous` / `target_next` |
| Activate XHB-L / XHB-R | `hold` | LT / RT | `activate_xhb_l` / `activate_xhb_r` |
| Activate WXHB-L / WXHB-R | `double_tap` | LT / RT | `activate_wxhb_l` / `activate_wxhb_r` |
| Activate Expanded LT→RT / RT→LT | `hold_then_hold` | LT then RT / RT then LT | `activate_expanded_lt_rt` / `activate_expanded_rt_lt` |
| Execute slot | `button` | face/d-pad while a trigger is held | `execute_slot` (display mode resolved from trigger state) |
| Open binder | `button` | BACK while XHB-L/R active | `open_binder` |

### Resolution rules
1. The gamepad module tracks which modifiers are held (LT/RT/RB/LB), and the trigger state machine
   (hold vs double-tap-hold vs expanded — expanded uses the first-pressed trigger as anchor).
2. A face/d-pad press while a trigger is held → `execute_slot` in the active display mode; the module
   maps the button to the displayed half's slot (d-pad → 1–4, face → 5–8, relative to the half).
3. A face/d-pad press while **RB** is held → `switch_set_N` (direct switch).
4. **If any trigger (LT/RT) is held, `LB = target_previous` and `RB = target_next`, full stop**
   (Resolved Decision 4). This takes priority over the buttons' no-trigger meanings (LB-tap
   `auto_run`, RB-tap `cycle_set`). Direct-switch (`switch_set_N`, RB + face/d-pad) and `mode_switch`
   (LB + RB) therefore require **no trigger held**, so `(button × context)` is never ambiguous. Zoom
   is the **LB + right-stick** gesture with no trigger held (Resolved Decision 6), fired as
   `setkey . / ,`; the stick is not a slot input, so it never conflicts.
5. `open_binder` only dispatches when XHB-L or XHB-R is the active display mode.
6. `mode_switch` is context-sensitive: it checks `player_state.is_mounted` at dispatch and routes to
   `dismount` if mounted, `toggle_mode` otherwise.

### Custom / user-added gestures
The default table above is just the shipped set. `gestures` is a **data-driven array**, and the
Gestures config tab lets you **add / edit / remove** entries (not only tune timing). So a new gesture
like **tap L4 (a paddle) → a command** is fully supported. Each entry is
`{ id, button + required modifier context, type, action, timing params }`, where `action` is a
registered system action **or** a raw windower command (e.g. `/jump`).

Three limits govern what can host a new gesture:
- **Only buttons the addon can see in that context.** Triggers, bumpers, BACK, paddles/trackpad, and
  the right stick are always visible. The **d-pad is visible only while a trigger is held** (the hold
  layer); with no modifier it stays native for party/alliance targeting, so a no-modifier d-pad
  gesture is not possible.
- **Bare face presses are reserved** (Resolved Decision 2). A no-trigger press of any face button
  passes through to FFXI's native menus, so face buttons cannot host a **no-modifier** custom gesture
  — host it on a paddle, trackpad zone, `BACK`, or a bumper instead.
- **No clobbering reserved roles.** A `(button × context)` already claimed by a built-in cannot be
  reused — e.g. face/d-pad while a trigger is held is always `execute_slot`, and LB/RB while a
  trigger is held are always target-switch.

---

## Action Module

### Binding Types (modular registry)
Each type is a named module registered at load; new types register without touching core code. Same
coverage xivcrossbar supports:

| Category | Type codes |
|---|---|
| Magic | `ma` (white/black/song/ninjutsu/summoning/blue/geomancy/trust) |
| Abilities | `ja` (job ability, phantom roll, quick draw, stratagem, dance, rune, ward, effusion) |
| Physical | `ws` (weapon skill), `a` (attack), `ra` (ranged) |
| Pet | `pet` (pet command, ready, blood pact, summon) |
| Items | `item` (use/trade item), `mount` |
| Navigation | `ta` (switch target), `map` (view map) |
| Commands | `ct` (raw windower command), `ex` (switch display mode) |
| Empty | `noop` (renders empty, does nothing; used to clear a base binding in overlays) |

**Binding data fields:** `type`, `action`, `target`, `alias`, `icon`, `equip_slot`, `warmup`,
`cooldown`, `usable` (mirrors xivcrossbar's field set for reference parity).

### Built-in System Actions
`auto_run`, `cycle_set`, `dismount`, `execute_slot(display_mode, slot_index)`, `mode_switch`,
`switch_set_N` (1–8), `target_previous` / `target_next`, `toggle_mode`, `zoom_in` / `zoom_out`.
Unknown type/action logs to chat without raising (via `log.error`).

---

## Logging Module

All chat output and diagnostics route through one module (`xivgamepad/log.lua`) — no other module
calls `windower.add_to_chat` directly.

- **API:** `log.debug(fmt, ...)` (diagnostics), `log.info(...)` / `log.error(...)` (always-on,
  user-facing), `log.set_debug(bool)`, `log.toggle()`. Every module is instrumented with `log.debug`
  at its decision points — button events, gesture resolution, display-mode transitions, action
  execution, storage read/write, overlay resolution, suppression-state changes, wizard captures.
- **Debug off by default.** `debug_enabled` starts **false** each load (ephemeral, never persisted);
  `log.debug` is a no-op while disabled, so debug lines never show unasked.
- **`//xg debugmode` (`dbg`)** toggles it and echoes the new state (`debugmode on|off` sets explicitly).
- **When enabled, both sinks:** each emitted line goes to the **game chat log** *and* is appended to
  **`data/debug.log`**. `info`/`error` also mirror to the file while debug is on (full session trace);
  while off, only chat gets `info`/`error` and the file is untouched.
- **File I/O via the Windower `files` API only** (append) — never `io` / `os.execute` / `io.popen`.
  The target dir is created with `windower.create_dir` anchored at the **absolute**
  `windower.addon_path`, never walking above it (same directory-creation contract as Storage). The
  file is **truncated with a session header when debug is switched on** so it captures one session and
  can't grow unbounded; lines carry an `os.date` timestamp.
- **No addon-module dependencies** (only `windower` + `files`) — a leaf everything else requires
  without cycles.

---

## Frontend Module

### HUD
Slot visuals modeled on XIVHotbar2 (which already demonstrates the recast/tooltip techniques below):
- Icons sourced from game resources. Slots arranged in the FFXIV cross pattern: two ✛ clusters
  (d-pad cluster + face cluster) side by side. Within the displayed half, d-pad directions = slots
  1–4, face buttons = slots 5–8, in FFXIV positional order. XHB-L puts the d-pad cluster left;
  XHB-R puts it right; WXHB/Expanded follow the displayed half.
- **Tooltips** on mouse hover: spell/action info (name, type, MP/TP, recast). Mouse-only.
- **Active-display highlighting** when a trigger is held.
- Per-slot overlays: **recast** clock-sweep (circular, XIVHotbar2-style, not a vertical fill),
  **unusable** fade + indicator, **item count** badge, **ninja tool count** badge, **stratagem
  charge count** (0–3) badge.
- Active display-mode label; empty slots optionally hidden (`hide_empty_slots`, position reserved).
- **Hotbar transparency** — three configurable states: `transparency_standard` (nothing activated,
  default 0), `transparency_active` (this hotbar active, default 0), `transparency_inactive` (another
  hotbar active, default 100).
- **Every HUD element is individually repositionable by dragging while config is open**; dragging
  disabled on close; each element has its own `{x, y}` written via `settings.stage_set`, committed on
  save / reverted on discard.
- **Hidden during cutscenes / events.** On `status change` to the event status (id 4, as xivcrossbar
  does), the HUD hides **and** the addon suspends gesture dispatch and input blocking so native
  controller input can advance the scene; both restore when status leaves 4. Uses the same
  `status change` event that feeds `is_mounted`.

### Config GUI
Built on `lib/settings/config_gui` (required). `on_mouse` delegates **unconditionally** to
`gui:handle_mouse` (echo pattern). Custom tabs:
- **Sets** — 8 set positions (name, source shared/job, skip_cycle).
- **Display** — assign set + half to each WXHB/Expanded mode; `hide_empty_slots`; transparency.
- **Keys** — map keyboard key codes to virtual buttons; a **Capture / Re-learn** button launches the
  Key-Capture Wizard (see below).
- **Gestures** — add / edit / remove gesture definitions (button + modifier context, type, and the
  action or raw command they fire) and tune each one's timing. See "Custom / user-added gestures".

Slot bindings are assigned in-game via the **Binder**, not the config GUI.

### Binder UI
In-game menu **toggled** by its open gesture — BACK while XHB-L/R is active (a trigger held). The
same gesture closes it; otherwise the binder **stays open until explicitly closed**. Suppresses
normal gesture dispatch (a `binder_mode` flag in main) while open — d-pad/face presses route to
binder navigation instead of slot execution; normal HUD keeps rendering.
- **Navigated with the d-pad and face buttons** while a trigger is held (keeping the Steam d-pad
  layer active so the d-pad emits mappable keys): the d-pad moves the selection, a face button
  confirms, and a face button (cancel) backs up one menu level. Releasing the trigger only **pauses**
  navigation — the binder stays open — and re-holding a trigger resumes it. The open gesture (BACK
  with a trigger held) toggles the binder closed.
- Flow: slot selection → for empty slots, type menu → action → target → confirm; for occupied slots,
  a slot menu (**Overlay**, **Replace** [clears base + all overlays], **Remove**, **Swap**, **Reorder
  Overlays**).
- **Magic sub-menus** branch by skill type (Healing, Enhancing, Enfeebling, Elemental, Dark,
  Ninjutsu, Song, Summoning, Blue, Geomancy, Trust) before listing spells.
- **Overlay type filtering:** each overlay type declares an `is_available(player_state)` predicate;
  only relevant types show (e.g. Scholar arts types only when main/sub is SCH; subjob entries only
  for valid subjobs).

### Gamepad Tester (`//xg test`)
Diagnostic overlay (plain texts/images, not config_gui): live virtual-button state grid + scrolling
gesture log. A `test_mode` flag in main replaces gesture→action dispatch with gesture→tester display;
closing restores normal dispatch. HUD keeps rendering.

### Key-Capture Wizard (Learn Mode)
Guided flow that **auto-populates `key_mapping`** by asking the player to press each virtual button and
recording the raw key-down code Steam Input emits. Removes the error-prone hand-transcription between
the Steam profile and the Keys tab, and closes the Steam↔addon half of the three-way alignment.

**Entry points:**
- **First launch** — on `login`, if `key_mapping_complete` is false (its state on a fresh install, even
  though `key_mapping` ships pre-filled with the defaults), the addon *offers* the wizard (chat prompt +
  auto-open), **pre-loaded with the shipped defaults** so a player whose Steam profile already matches
  can accept in seconds. Dismissing accepts the defaults and sets `key_mapping_complete` (no repeat
  nag); it never forces the flow, so `init` stays idempotent. Re-openable anytime via `//xg learn`.
- **Keys config tab** — a **Capture / Re-learn** button opens it.
- **Command** — `//xg learn` (`l`) launches it anytime.

**Presentation:** plain texts/images overlay (like the Gamepad Tester, **not** config_gui) so it works
before any mapping exists. A `learn_mode` flag in main replaces normal gesture→action dispatch and
input blocking with raw key capture; closing restores normal dispatch.

**Capture state machine (frontend), driven by raw key-down events:**
- Walks an **ordered button list**: triggers/bumpers first (`LT, RT, LB, RB`), then `BACK`, face
  (`A, B, X, Y`), right stick (`RSTICK_UP/DOWN/LEFT/RIGHT`), and the **d-pad hold-layer**
  (`DPAD_UP/DOWN/LEFT/RIGHT`) last.
- Each step shows a prompt ("Press **LT**"), waits for the next key-down, echoes the captured key, and
  advances. **Skip** (leave unmapped — for optional paddles/trackpad) and **Back/Redo** (re-capture the
  previous button) are always available.
- **D-pad steps require a held trigger** — the Steam hold-layer only emits d-pad keys while LT/RT/RB is
  down. Because triggers are captured first, the wizard instructs "**Hold LT, then press D-pad Up**" and
  verifies a trigger key is currently down before accepting the d-pad key.
- **Collision detection:** a code already bound to an earlier button is rejected and re-prompted, naming
  the button that already owns it — two virtual buttons may never share a keyboard code. `RSTICK` keys
  intentionally coincide with FFXI's own camera keys and are recorded as such (the player still binds
  those same keys in FFXI's config; the wizard only records which they are — it cannot set FFXI binds).

**Staging & commit:** captures write to a **staging copy** of `key_mapping` (same model as config);
**finishing** commits via `settings.stage_set` + save and sets `key_mapping_complete`; **cancelling**
discards, leaving the prior mapping untouched. Re-running pre-loads current values so a single button
can be fixed without redoing all.

---

## Storage Model

Hotbar **content** (set definitions + slot bindings) is stored separately from addon **config**.

### Addon config — via lib/settings (`data/{CharacterName}/settings.json`)
Not hotbar content: config window position; per-element HUD positions; `current_mode`; `active_set`;
`key_mapping` (ships with a default set, below) and a `key_mapping_complete` first-run flag (starts
false, so the wizard still runs even though the map is pre-filled); the 8 set positions' metadata (name, source flag, skip_cycle); `display` assignments
(`wxhb_l={set,half}`, `wxhb_r`, `expand_lt_rt`, `expand_rt_lt`); `hide_empty_slots`; transparency
values; the `gestures` array (each entry: `id`, button + required modifier context, `type`, `action`
— a named system action **or** a raw command — and timing params). GUI operates on a staging copy;
committed on save, dropped on discard.

Display defaults: `wxhb_l={set=2,half=left}`, `wxhb_r={set=2,half=right}`,
`expand_lt_rt={set=4,half=right}`, `expand_rt_lt={set=4,half=right}`. (Consistent now that slot
addressing is relative to the displayed half.)

**Default `key_mapping`** (per Resolved Decision 1 — quiet-key model; shipped so the addon is
functional immediately; the wizard still runs on first login because it is gated on
`key_mapping_complete`, not on the map being empty):

| Virtual button | Default key | Notes |
|---|---|---|
| `LT` / `RT` | `F11` / `F12` | quiet |
| `LB` / `RB` | `F5` / `F6` | quiet |
| `BACK` | `F9` | quiet |
| `A` / `B` / `X` / `Y` | `Enter` / `Escape` / `NumPad -` / `NumPad +` | menu keys; bare = native menu, consumed under a trigger |
| `DPAD_UP/RIGHT/DOWN/LEFT` | `F1 / F2 / F3 / F4` | hold-layer only |
| `RSTICK_UP/DOWN/LEFT/RIGHT` | `Up / Down / Left / Right` arrows | native camera (pass-through) |
| right-stick vertical **under LB layer** | two quiet F-keys (e.g. `F7` / `F8`) | zoom in / out proxies |
| `L4/L5/R4/R5` (paddles) | unmapped | assign via wizard if present |
| `TRACKPAD_1..8` (8 zones) | unmapped | assign via wizard if present |

The primary buttons use **quiet F-keys** FFXI does not act on, so `return true` fully owns them; the
four face buttons are **menu keys** that pass through on a bare press and are consumed on both edges
under a trigger (Resolved Decision 2). `RSTICK_*` maps to the **arrow keys** (native camera
pass-through); **zoom is handled separately via the LB layer** (Resolved Decision 6), not by stealing
the arrow keys. Extended buttons are unmapped by default. Exact F-key codes are whatever the Steam
profile emits and the wizard captures; the wizard pre-loads these defaults so a player whose Steam
profile already matches can accept in seconds.

### Hotbar content — direct file I/O (Windower `files` API), additive to lib/settings
- `data/{CharacterName}/shared.json` — up to 8 shared set definitions.
- `data/{CharacterName}/job.json` — up to 8 job set definitions **keyed by main-job abbreviation**.
- Each set definition: `{ slots = [16 slot objects or null] }`; each slot object holds base binding
  fields plus an ordered `overlays` array.
- At runtime, working position N resolves its content from `shared.json[N]` or the current job's
  `job.json[main_job][N]`, per that position's source flag in config; metadata (name/skip_cycle)
  comes from config.
- The storage module creates the per-character directory (anchored at the **absolute**
  `windower.addon_path`, via `windower.create_dir`) before writing — never walking above
  `addon_path`. This mirrors the lib/settings directory-creation contract.

---

## Per-Slot Overlay System

Each slot holds a base binding plus an optional ordered `overlays` array. A shared **overlay
resolver** (used by both the action module and the frontend) evaluates overlays in array order and
returns the first match; otherwise the base binding. First match wins, so users place the most
specific overlay first (e.g. Addendum White before Light Arts).

Player state is maintained at runtime by main and passed to the resolver; state changes refresh the
HUD. Runtime events feeding player state: buff gain/loss (arts/addendum via buff status IDs
358/359/401/402), job/subjob change, mount status, and **`zone change`**. Per Resolved Decision 7, a
~1 s **poll-and-diff** reconciliation runs alongside these events: read buffs/job/mount, compare to
the cached state, and re-resolve overlays + refresh the HUD **only when something changed** (dirty
flag — no blind re-render). The poll is the safety net that also captures buffs already active at
login / zone-in, which the event handlers miss; the events remain the fast path.

### Overlay types (modular registry)
Each type registers a `check(condition, player_state)` function; new types register without touching
core code.

| Overlay type | Condition | Active when |
|---|---|---|
| `subjob` | `{ subjob = "WHM" }` | Current subjob matches |
| `light_arts` | `{}` | Light Arts buff active |
| `addendum_white` | `{}` | Addendum: White buff active |
| `dark_arts` | `{}` | Dark Arts buff active |
| `addendum_black` | `{}` | Addendum: Black buff active |

Each overlay entry contains: `overlay_type`, `condition`, and the full binding fields that replace the
base when active.

---

## Interface Contracts (freeze before parallel work)

To let Tasks 2a/2b/2c proceed in parallel without integration churn, these contracts are fixed as part
of the Task 1 deliverables and reviewed before 2x begins:
- Gesture **id strings** and the `on_gesture(id)` / `on_button_event(name, pressed)` callback shapes.
- The `player_state` schema (buffs, main/sub job, is_mounted, in_event).
- The **display-mode enum** and the `resolve_binding(slot, player_state)` signature.
- Where the suppression states (`test_mode`, `binder_mode`, `learn_mode`, event/cutscene, `menu_open`,
  `chat_open`) live (main) vs. where they are asserted (frontend tester/wizard tests, binder tests).
- The **key-consumption contract**: the Windower keyboard handler **suppresses every owned key while
  loaded** (both edges, tracked per captured key), except the pass-through carve-outs — camera arrow
  keys, and a **bare press of any of the four face menu-keys** (`Enter`/`Escape`/`NumPad -`/`NumPad +`).
  The consume-both-edges rule guarantees a face key used for slot execution can never leak on release
  (Resolved Decisions 1 / 2). See **Input ownership** in the Input Model.
- The **logger interface** (`log.debug` / `log.info` / `log.error` / `log.set_debug` / `log.toggle`),
  which every module calls; `debug_enabled` is owned by `log`, defaults false, and is not persisted.

---

## Task Decomposition

**Gate — Task 0 (Input Spike):** `xivgamepad-spike.md` must pass before any module work starts. It
verifies `return true` suppresses the four face menu-keys under a trigger, bare passthrough drives
native menus, `setkey . / ,` zooms, and `menu_open` semantics. A failure only narrows the affected key
to a `bind noop` fallback; it does not change the module plan.

Tasks 1a/1b/1c/1d are independent (parallel). Tasks 2a/2b/2c depend on all Task 1s merged (parallel
with each other). Task 3 is final integration.

### Task 1a — Input + Gamepad modules
**Files:** `xivgamepad/input/keyboard.lua`, `xivgamepad/gamepad.lua`, `tests/xivgamepad/test_input.lua`,
`tests/xivgamepad/test_gamepad.lua`
Keyboard module: key codes → virtual button names via configurable mapping; `on_button_event`
callback; owns the Windower keyboard handler's blocked-return, **consuming both edges of any key it
reports consumed** (tracked per captured key, not by live modifier state). Gamepad module: modifier +
button-state tracking, all six gesture types, modifier×button resolution to `on_gesture(id)`,
**wall-clock (`coroutine.schedule`) timing** for thresholds/windows (Resolved Decision 5). No
settings/UI deps. Tests drive press/release directly, **stub the scheduler**, and assert a face key
pressed under a trigger is blocked on release **even when the trigger is released first**.

### Task 1b — Action module
**Files:** `xivgamepad/action.lua`, `tests/xivgamepad/test_action.lua`
Type registry (`register_type`), system-action registry (`register_action`), overlay-type registry,
`resolve_binding`, and `execute`. All binding type codes and system actions implemented;
`send_command` stubbed in tests; unknown type/action logs without raising.

### Task 1c — Storage module
**Files:** `xivgamepad/storage.lua`, `tests/xivgamepad/test_storage.lua`
All hotbar-content file I/O via the `files` API. Reads/writes `shared.json` and job-keyed `job.json`;
creates the per-character directory anchored at the absolute addon path. Tests must exercise **path
construction** against realistic (Windows-style) paths, not merely a stubbed `create_dir`. No
dependency on lib/settings, gamepad, or UI.

### Task 1d — Logging module
**Files:** `xivgamepad/log.lua`, `tests/xivgamepad/test_log.lua`
Central logger: `debug`/`info`/`error`, `set_debug`/`toggle`, chat + `data/debug.log` mirroring while
enabled, `files`-API append, session-truncate + `os.date` timestamps. Depends only on `windower` +
`files`. Tests: `log.debug` is silent while disabled and hits **both** sinks when enabled; **path
construction is exercised against realistic Windows-style paths** (not just a stubbed `create_dir`);
append is verified through the mocked `files` API.

### Task 2a — Main entry point
**Files:** `xivgamepad/xivgamepad.lua`, `tests/xivgamepad/mock_windower.lua`,
`tests/xivgamepad/run_tests.lua`, `tests/xivgamepad/test_lifecycle.lua`,
`tests/xivgamepad/test_commands.lua`
Wires modules; lifecycle follows echo exactly (defer on load, re-init on login, idempotent init,
logout hides UI + discards staging, destroy on unload). Commands: `config`/`c`, `save`/`s`,
`discard`/`d`, `help`, `test`/`t`, `learn`/`l`, `debugmode`/`dbg` (routes to `log.toggle`). On `login`, **offers the Key-Capture Wizard** when
`key_mapping_complete` is false (dismissable; keeps `init` idempotent). Registers the
buff/job-change/status Windower events that maintain `player_state`. Owns the suppression states —
`test_mode`, `binder_mode`, `learn_mode` (raw key capture for the wizard), an **event/cutscene
state** (from `status change` id 4) that hides the HUD and halts gesture dispatch + input blocking so
native cutscene controls work, a **menu state** (`get_info().menu_open`) and a **text-input state**
(chat/console open, via `get_info().chat_open`) that suspend gesture dispatch + input blocking while a
menu or chat is open; all restore on exit (Resolved Decisions 3 / 4a). Also registers a `zone change`
handler and the ~1 s poll-and-diff reconciliation (Resolved Decision 7).

### Task 2b — Frontend module
**Files:** `xivgamepad/frontend.lua`, `tests/xivgamepad/test_frontend.lua`
HUD (clock-sweep recast, unusable/badge overlays, transparency), config GUI (4 tabs), draggable HUD
during config, unconditional `on_mouse` delegation, gamepad tester sub-component, and the **key-capture
wizard** sub-component (ordered-button capture state machine, collision detection, d-pad-requires-trigger
sequencing, staging commit on finish). Tests call build-tabs / on_mouse directly with stubbed UI, assert
tester suppression display, and feed raw key-down sequences to the wizard to assert mapping, collision
rejection, d-pad-trigger gating, and cancel-leaves-mapping-untouched.

### Task 2c — Binder UI (depends on 1b + 1c)
**Files:** `xivgamepad/binder.lua`, `tests/xivgamepad/test_binder.lua`
Menu system toggled open/closed by the BACK-while-XHB gesture (stays open until toggled closed).
Navigated via the d-pad + face buttons while a trigger is held (d-pad layer live; d-pad = move, face
= confirm/cancel); navigation pauses when no trigger is held. Covers slot navigation, type menus
(incl. magic skill-type
sub-menus), overlay type selection with `is_available` filtering, Replace/Overlay/Remove/Swap/Reorder
operations, writes via storage. `binder_mode` suppresses normal dispatch. Tests exercise each branch,
overlay filtering (mock player state), swap/remove/reorder, and Replace-clears-overlays.

### Task 3 — Integration, Documentation + Integration Test Plan
**Files:** `xivgamepad/README.md`; user-facing Wiki under `docs/xivgamepad/wiki/`; developer
reference under `docs/xivgamepad/reference/`; `docs/xivgamepad/integration-test-plan.md`.

Full suite green. `README.md` matches echo/README.md structure (what it does, install, commands
table, configuration table, libraries table) and links to the Wiki. Documentation has two audiences,
**both in-repo — no external wiki platform (GitHub/Forgejo)**:

- **User-facing Wiki** (`docs/xivgamepad/wiki/`) — the primary end-user home, written for players:
  overview / home; Installation + Steam Input setup (1:1 mappings including the right stick, and the
  trigger-gated d-pad layer) followed by the **first-launch Key-Capture Wizard** to record the mapping;
  Controls & Gestures; Hotbar Sets & Display Modes (XHB / WXHB /
  Expanded); Using the Binder; Configuration (the config GUI tabs); Troubleshooting / FAQ.
- **Developer reference** (`docs/xivgamepad/reference/`) — concise contributor reference: settings
  keys/schema, action & binding type-code signatures, gesture-type parameters, and the module
  interface contracts.

### Task 3 deliverable — In-Game Integration Test Plan
**File:** `docs/xivgamepad/integration-test-plan.md` — a **follow-along, player-runnable** checklist
that walks button-press combinations and state changes to flush out edge cases on real hardware (what
unit tests can't reach).

**Format (kept deliberately simple):**
- A short **button legend** (controller → what to press) assuming the recommended Steam profile.
- Grouped into **state blocks**, each opening with a one-line SETUP (e.g. "In town, sheathed, chat
  closed, no menu open") and ending with a **RESET** line (release all buttons, close menus) so blocks
  are independent.
- Every check is one atomic row — **Do → Expect → ☐** — single action, single observable result, a
  tick box. No branching, no internal/function names; written for a player.
- Numbered continuously (e.g. `5.3`) so a failure is reported by number.

**Coverage blocks (the edge-case matrix):**
1. **Boot & lifecycle** — load-before-login (no crash); login (HUD, set label, icons); `//lua r`
   restores state; logout→login; character switch (per-char, no clobber).
2. **Key-Capture Wizard** — each prompt records a key; d-pad steps require a held trigger;
   duplicate-key rejection names the conflict; finish persists + sets `key_mapping_complete`; cancel
   keeps prior map; `//xg learn` re-opens pre-loaded.
3. **Display-mode transitions** — hold LT / RT (XHB-L/R); LT→RT and RT→LT (both Expanded orders, anchor
   = first trigger); double-tap LT / RT (WXHB); hold both triggers; release one of two held; rapid
   release-then-rehold; full release returns to idle. Correct set+half each time.
4. **Slot addressing & execution** — d-pad→1–4, face→5–8 relative to the displayed half; executed
   action matches the on-screen icon; empty slot no-ops; one execution per display mode.
5. **Input-edge & suppression** — all four face keys consumed during slot execution **including
   release-trigger-before-face** (no chat/menu leak); bare (no-trigger) face press → native menu
   (pass-through, both edges); **menu open (`menu_open`) and chat open (`chat_open`) → dispatch
   suspends**, close → keys drive the addon; cutscene (status 4) → HUD hides + dispatch/blocking halt +
   scene advances, exit restores; `//xg test` → tester replaces dispatch, close restores.
6. **Native pass-throughs** — no-modifier d-pad selects party **and alliance**; right-stick pans the
   native camera; **no trigger + LB + right-stick up/down zooms** (via `setkey . / ,`) without panning.
7. **Mode / cycling / direct-switch** — mode switch toggles shared/job and jumps to that pool's first
   set; cycle skips empty + `skip_cycle`; all eight direct-switches (RB + face/d-pad) jump with mode
   preserved; mounted + mode-switch → dismount.
8. **Targeting & taps** — LT/RT held + LB/RB = prev/next target (beats auto_run / cycle_set /
   mode_switch); bare LB tap = auto-run; bare RB tap = cycle set.
9. **Overlay resolution** — gain/lose Light Arts, Dark Arts, Addendum White/Black; subjob change; mount
   → the slot swaps to the overlay binding and the HUD refreshes; first-match-wins ordering (Addendum
   before Light Arts).
10. **Binder** — open (BACK while XHB); navigate d-pad/face while a trigger is held; **pause on release,
    resume on re-hold**; toggle closed; empty-slot flow (type→action→target→confirm); occupied-slot
    menu (Overlay/Replace/Remove/Swap/Reorder); **Replace clears base + overlays**; overlay list
    filtered by `is_available`; writes survive a reload.
11. **HUD visuals** — recast clock-sweep; unusable fade + indicator; item/tool/stratagem badges; three
    transparency states; active-display highlight on hold; empty-slot hide.
12. **Config GUI & commands** — `//xg config` opens; every HUD element draggable, drag off on close;
    save persists positions + settings; discard reverts; `config` while open no-ops; clicks over the
    window don't reach the game. `//xg debugmode` toggles debug output (default off) to chat **and**
    `data/debug.log`; resets to off after reload.

---

## Utilities to Reuse

- `lib/settings/settings.lua` — required by `xivgamepad.lua`.
- `lib/settings/config_gui.lua` — required by `xivgamepad/frontend.lua`.
- `tests/echo/mock_windower.lua` — model for `tests/xivgamepad/mock_windower.lua`.
- `tests/echo/test_lifecycle.lua` — template for lifecycle tests.

Reference only (do not copy): `xivcrossbar/action_binder.lua` / `action_manager.lua` for binding
field parity; `xivcrossbar/ui.lua` for what to improve in the recast animation; XIVHotbar2 for the
clock-sweep recast and tooltip techniques.

---

## Deferred / Out of Scope

- Target selection features beyond native + prev/next cycle
- Job gauges (Rune Fencer, Scholar, Corsair)
- Toggle / Mixed input modes
- AutoHotkey support

---

## Verification

**Automated:** `lua tests/xivgamepad/run_tests.lua` — all files pass, non-zero exit on failure.
Storage path-construction is verified against realistic Windows paths (not just a stubbed
`create_dir`). The key-capture wizard's state machine is verified by feeding raw key-down sequences
(including a collision and a d-pad-before-trigger attempt) and asserting the resulting `key_mapping`.
The logger is verified for silent-while-disabled, dual-sink (chat + file) while-enabled, and
Windows-style path construction for `data/debug.log`.

**Manual (in-game) smoke test** — the quick pass below; the exhaustive follow-along matrix is the
**In-Game Integration Test Plan** deliverable (`docs/xivgamepad/integration-test-plan.md`, Task 3):
1. Load before login — no crash.
2. Login — HUD appears with active-set label and icons.
3. `//xg config` — window opens; HUD becomes draggable; save/discard persist/revert.
4. Hold LT → XHB-L (left 8); release returns to idle. Hold LT then RT → Expanded LT→RT with its
   configured set/half. Double-tap LT → WXHB-L with its configured set/half.
5. No modifier held: d-pad up/down still selects party **and alliance** members natively.
6. Mode switch → toggles shared/job; XHB updates to first set of new mode. Cycle → next non-empty,
   non-skipped set. Direct-switch (RB + face/d-pad) → jumps to position; mode preserved.
7. Slot execute → binding fires; the executed slot matches the icon shown in the displayed half.
8. Recast animates as a circular sweep; unusable slot fades with indicator.
9. Open binder (BACK while holding LT/RT) → stays open; navigable with the d-pad + face buttons while
   a trigger is held, navigation pauses on release and resumes on re-hold; the same BACK gesture
   toggles it closed. With the binder closed and no trigger held, d-pad party/alliance targeting is
   unaffected.
10. Enter a cutscene → HUD hides and controller input advances the scene normally (the addon does not
    eat it); leaving the cutscene restores the HUD.
11. Open an in-game menu (equipment / shop): the bare (no-trigger) face buttons confirm / cancel /
    open-menu / focus **natively** (all four pass through); the `menu_open` gate suspends gesture
    dispatch so a trigger press does not fight the menu.
12. Character switch — settings reload per character, no clobber. `//lua r xivgamepad` — clean reload,
    HUD and positions restored from disk.
13. Fresh install (no `key_mapping`) → login offers the **Key-Capture Wizard**; pressing each prompted
    button records its key; the d-pad steps only accept input while a trigger is held; a duplicate key
    is rejected with the conflicting button named; **finish** persists `key_mapping` and sets
    `key_mapping_complete`; **cancel** leaves any prior mapping untouched. `//xg learn` re-opens it with
    current values pre-loaded.
14. Hold RT and press the confirm button (`Enter`) to execute a slot → the slot fires and **no chat bar
    opens**; repeat but release RT *before* the face button → still no chat bar / menu (key-up
    consumed). With no trigger held, a bare unbound confirm/cancel press drives FFXI's native menu.
15. With XIVGamepad loaded, open chat and type — normal typing is **unaffected** (owned keys are quiet
    F-keys, not text keys) and dispatch **suspends while chat is open**; close chat and the mapped keys
    resume driving the addon. Likewise open a menu → `menu_open` suspends dispatch, close → resumes.
16. `//xg debugmode` → debug lines start appearing in chat **and** `data/debug.log`; run it again → they
    stop and the file is left as-is. After `//lua r xivgamepad`, debug mode is off again (default).

---

## Resources

- FFXIV cross hotbar guide — https://www.akhmorning.com/resources/controller-guide/the-cross-hotbar/
- FFXIV UI guides — https://na.finalfantasyxiv.com/uiguide/know/know-xhb/ (switching, hold, change,
  how-to)
- XIVHotbar2 (Windower) — https://github.com/WGINC/XIVhotbar2-Petit_Trois_Edition
- xivcrossbar (Windower) — `./xivcrossbar` (external git submodule; reference only)
- Input spike (gate) — `.planning/xivgamepad-spike.md`
- Windower FFXI functions (`get_info().menu_open` / `chat_open`) — https://github.com/Windower/Lua/wiki/FFXI-Functions
- Windower input commands (`setkey`) — https://docs.windower.net/commands/input/
