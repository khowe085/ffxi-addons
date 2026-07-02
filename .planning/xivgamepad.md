# XIVGamepad — Implementation Plan

## Context

Clean-room replacement for xivcrossbar. XIVGamepad brings the Final Fantasy XIV cross hotbar
gamepad experience to FFXI as a fully conventional monorepo addon. Physical controller input is
shaped externally by Steam Input. No code from xivcrossbar is carried over (study for reference
only; it is a separately licensed BSD-3 fork). No AutoHotkey support.

**Input philosophy:** Hold-only (hold a trigger, then press a button). All gesture logic lives in
the addon so it is unit-testable; Steam Input is kept as thin as possible.

### Steam Input model (amended — see Resolved Decisions + Control Map)

- **Hybrid output** (Resolved Decision 8). The **left stick**, the **no-trigger d-pad**, and the
  **no-LB right stick** pass through as **native gamepad** (analog movement + party/alliance/menu
  targeting + analog camera, preserved unchanged, including alliance members the addon does not
  reimplement); everything the addon reads is **keyboard**.
- **No shared modifier on held-together controls** (Resolved Decision 1). Held-combinable controls
  (triggers, bumpers, faces, paddles) use **unmodified** keys; only the **discrete** controls
  (`BACK`/`START`/trackpad, never held together) use `Ctrl`+number — so Steam's non-reference-counted
  Ctrl can never collapse a held combo.
- **The d-pad chords.** The d-pad is mapped **as a native d-pad** (party/alliance & menu targeting),
  and Steam adds **button-chord** outputs on top: while **LT, RT, or RB** is held, each d-pad direction
  emits the key the addon reads (`LT/RT/RB + d-pad` chords). `LT`, `RT`, and `RB` each also emit their
  own single mapped key. So a bare d-pad stays native; a d-pad direction under a held trigger/RB fires
  the mapped key — conceptually how FFXIV's own cross hotbar behaves. (WXHB requires LT/RT held, so the
  chords are already live in it — L4/R4 need not drive them. RB's chords cover the four d-pad
  direct-switch positions.)
- **The LB zoom-layer.** The right stick is **native analog camera** (gamepad passthrough) whenever
  **LB** is not held; while **LB** is held, Steam's momentary layer overrides the right stick's vertical
  axis to the native zoom keys `.` / `,` (Steam-direct — Resolved Decision 6), so zoom does not fight
  the native camera pan.
- Beyond the d-pad chords and the LB zoom layer there are no action layers or mode shifts; every other
  gesture is resolved in the addon from (held-modifier state × button).

---

## Resolved Decisions (pre-planning, 2026-07-02)

These decisions are authoritative and **supersede any conflicting detail elsewhere in this
document**. The input-model facts below are **verified in-game** and reshaped decisions 1–3 and 6.

**Verified input facts (load-bearing):** returning `true` from the Windower `keyboard` event **does not
block any key FFXI acts on** (all four candidate face keys leaked — `NumPad-` opened the menu even
when "consumed"). Conversely, **`setkey` reliably drives native game input** (`enter` opened chat,
`escape` closed it; `.`/`,` zoom). The **plain number row (`` ` `` `1`–`0` `=`) is inert in FFXI**
(verified in-game), so it needs no neutralization at all. So the model is **inert keys + synthesis**,
not *game keys + suppression*.

1. **Key map = dead number row + Ctrl-number; F-keys preserved.** The 12 controls that can be **held
   together** — `LT`/`RT`, `LB`/`RB`, the four **face buttons**, and the four **d-pad hold-layer**
   directions — map to the **plain number row** (`` ` `` `1`–`0` `=`), which is **inert in FFXI**
   (verified in-game), so no modifier is needed and nothing leaks. The **discrete** controls that are
   never held together — `BACK`, `START`, and the **8 trackpad zones** — map to **`Ctrl` + that row**;
   because `Ctrl`+number is FFXI's live **macro palette** (a game function `return true` cannot block),
   the addon `bind noop`s each `Ctrl`+`` ` ``/`1`–`0`/`=` on load and restores them on unload.
   **Crucially, no two simultaneously-held controls share a modifier**, so Steam Input's
   non-reference-counted Ctrl can never collapse a held combo (the bug that rules out Ctrl+F for the
   core). The **rear paddles** (`L4/L5/R4/R5`) take plain **`F9`–`F12`** (unmodified, so they can be
   held/combined freely), `bind noop`'d on load and restored on unload — the **target-select `F1`–`F8`
   stay bound**. The right stick is **native gamepad analog camera** (passthrough; the addon never reads
   it), except while **LB** is held, when Steam's layer sends its vertical axis to the zoom keys. No
   owned camera keys anywhere.
2. **Native effects = active synthesis; suppression via `return true` is impossible.** Slot execution
   (a face/d-pad key under a held trigger) runs the binding via `send_command`; the key is
   dead in FFXI, so nothing leaks. **Bare (no-trigger) presses are fully configurable gestures** — the
   addon reads the dead key and fires the bound action: a **`setkey` synthesis** of a native key, a raw
   command, or a system action. Shipped bare defaults: `A → menu_confirm` (`setkey enter`),
   `B → menu_cancel` (`setkey escape`), `X → map`, `Y → jump`, `START → menu_open` (`setkey numpad-`),
   `BACK → menu_focus` (`setkey numpad+`). Full controller menu control with **zero reliance on
   `return true`**. **Deleted from the old plan:**
   `return true` suppression, the consume-both-edges invariant, the chat_open type-through carve-out,
   and the old restriction that faces could not host bare gestures. (Keys are made inert two ways:
   dead by default [the number row — no action needed], or `bind noop` [the `Ctrl`+number macro palette
   and the paddle `F9`–`F12`, on load; restored on unload] — never by `return true`.)
3. **Dispatch-suspend signals.** Hotbar **slot** dispatch suspends while any of `get_info().menu_open`,
   `get_info().chat_open`, or cutscene (status id 4) is true. Bare-face **menu synthesis still runs
   while `menu_open` *and* while `chat_open`** — so the controller can navigate a menu *and* back out of
   the chat bar it opened (A→`enter`, B→`escape`, BACK→`numpad+`); only hotbar slot dispatch and field
   commands are suspended. A **cutscene (status 4)** halts everything (synth included) so native
   controller input advances the scene.
4. **RB/LB precedence (unambiguous).** If **any trigger (LT/RT)** is held, `LB = target_previous` and
   `RB = target_next`, full stop — this covers XHB and WXHB alike (WXHB requires a trigger held).
   **Direct-switch** (`switch_set_N`, RB held + face/d-pad) and **`mode_switch`** (LB held + RB press)
   require **no trigger held**. Every `(button × context)` resolves to exactly one action.
5. **Timing = wall-clock.** All hold/tap/double-tap/expanded thresholds and windows use Windower's
   wall-clock scheduler (`coroutine.schedule`), **not** prerender frame ticks (which drift with frame
   rate). prerender is used only for any continuous per-tick effect. Tests stub the scheduler.
6. **Zoom = LB + right stick (Steam-direct); the right stick is otherwise native.** The right stick is
   **native gamepad analog camera** whenever LB is not held. With **no trigger held**, **LB held +
   right-stick up/down** zooms: Steam's LB momentary layer overrides the right-stick vertical **straight
   to the native zoom keys `.` / `,`** (verified tokens; the named `period`/`comma` are invalid)
   — so pan and zoom don't collide, and the **held stick carries no modifier** (ref-count-safe). The
   addon isn't in the loop for the camera or the default zoom; `zoom_in` / `zoom_out` remain **bindable
   `setkey` actions** for any other host via the Gestures tab.
7. **State refresh.** Player state refreshes on its events (buff gain/loss, job/subjob change, mount)
   **and** on `zone change`, **plus** a ~1 s **poll-and-diff** reconciliation: read buffs/job/mount,
   compare to cached state, and re-resolve overlays + refresh the HUD **only on change** (dirty flag).
   This also captures buffs already active at login / zone-in that the event handlers miss.
8. **Hybrid gamepad + keyboard input.** The controller runs as a hybrid: the **left stick (analog
   movement)**, the **no-trigger d-pad (party/alliance & menu targeting)**, and the **no-LB right stick
   (analog camera)** pass through as **native gamepad**; everything the addon reads (triggers, bumpers,
   faces, trigger-held d-pad, `BACK`/`START`, trackpad, paddles) is **keyboard**. FFXI's **gamepad
   support is enabled alongside keyboard** (a setup prerequisite) — the two coexist. This is what lets
   the plan preserve native alliance targeting, analog movement, and analog camera without
   reimplementing any of them.

---

## Architecture: Modules + Storage + Main Entry Point

| Component | File | Responsibility |
|-----------|------|----------------|
| Main | `xivgamepad/xivgamepad.lua` | Lifecycle, command dispatch, wires modules, owns runtime state (player_state, mode flags) |
| Input | `xivgamepad/input/keyboard.lua` | Windower keyboard events → virtual button press/release callbacks |
| Gamepad | `xivgamepad/gamepad.lua` | Virtual button state, modifier tracking, gesture resolution, fires gesture callbacks |
| Action | `xivgamepad/action.lua` | Modular action/binding-type registry, overlay resolver, execution engine, built-in actions |
| HUD | `xivgamepad/hud.lua` | Persistent hotbar HUD: slot icons, recast sweep, overlays, transparency, drag, cutscene hide |
| Config UI | `xivgamepad/config_ui.lua` | Config GUI on lib/settings `config_gui` (Sets / Display / Keys / Gestures tabs); launches the wizard |
| Tester | `xivgamepad/tester.lua` | Gamepad Tester diagnostic overlay (`//xg test`) |
| Wizard | `xivgamepad/wizard.lua` | Key-Capture Wizard / Learn Mode (`//xg learn`) |
| Binder | `xivgamepad/binder.lua` | In-game slot-binding menu (opened by BACK while an XHB is active) |
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
- **Right stick**: **native gamepad analog camera** (passthrough). The addon never reads it — with no
  LB held it drives the native FFXI camera exactly like a joystick, configured in FFXI's own gamepad
  config (right stick → camera). Camera **zoom in/out** is **Steam-direct** (per Resolved Decision 6):
  while **LB** is held, Steam's momentary layer overrides the right-stick vertical to the native zoom
  keys `.` / `,` — the addon isn't involved, and the held stick carries no modifier. This keeps pan and
  zoom from colliding and needs no arrow-key binding.
- **D-pad** (`DPAD_UP/DOWN/LEFT/RIGHT`): only ever seen by the addon while a modifier (LT/RT/RB) is
  held — see the Steam Input constraint above. When no modifier is held the d-pad is native.
- **No gesture chords.** The gamepad module resolves every gesture from **(active modifier state ×
  physical button)** — Steam never encodes a *gesture combination* into a unique key, because the addon
  sees LT/RT/RB/LB hold state directly. (The only modifier in the map is the `Ctrl` on the discrete
  `BACK`/`START`/trackpad keys, used purely for distinct scancodes, never to encode a gesture.)
- Face buttons are **dead number-row keys** (`5`–`8`; inert in FFXI) and context-routed by the addon:
  **no modifier → configurable bare gesture** (Resolved Decision 2); trigger held → hotbar slot; binder
  open → binder navigation.
  - **Bare-press = a configurable gesture.** With no trigger held, a face press fires its bound action
    — a `setkey` synthesis of a native key, a command-wrapper action, or a system action. Shipped
    defaults: `A → menu_confirm` (`setkey enter`), `B → menu_cancel` (`setkey escape`), `X → map`,
    `Y → jump` (and `START → menu_open`, `setkey numpad-`; `BACK → menu_focus`, `setkey numpad+`). Bare
    faces are *not* reserved — they can host any no-modifier gesture (see **Custom / user-added gestures**).
  - **Trigger held = slot.** A face key while a trigger (LT/RT) is held executes the displayed slot via
    `send_command`; the key is dead in FFXI, so nothing leaks — no consume-both-edges, no suppression.
  - **Menu / cutscene / chat suspend.** Hotbar **slot** dispatch suspends during cutscenes (status 4),
    while a menu is open (`get_info().menu_open`), and while chat is open (`get_info().chat_open`) —
    Resolved Decision 3. The **menu-nav synth actions (A `menu_confirm`, B `menu_cancel`, BACK
    `menu_focus`) keep working while `menu_open` *and* `chat_open`** (navigate the menu, and back out of
    the chat bar the controller opened); slot dispatch and field commands (`map`, `jump`) are suspended.
    Only a cutscene (status 4) halts the synth as well.
- **No `return true` suppression.** The Windower `keyboard` event **cannot block** any
  key FFXI acts on (verified in-game — see Resolved Decisions), so the design never tries. Instead every
  mapped key is made **inert** one of two ways: **dead by default** (the number-row core — no action
  needed) or **`bind noop`** (the `Ctrl`+number macro palette and the paddle keys `F9`–`F12`, on load;
  restored on unload). The keyboard handler only **reads** presses to drive
  gestures; it never returns `true`, and there is no consume-both-edges. Native effects are produced by
  the addon **actively** — `send_command` for abilities, `setkey` for menu keys. (The number row **does**
  type during text entry, so **slot** dispatch suspends while chat/console is open — the bare-face menu
  synth stays live so the controller can dismiss the chat bar — and the physical keyboard types
  normally.)
- Extended buttons — the 8 **trackpad zones** (`TRACKPAD_1..8`, on `Ctrl`+number) and the rear paddles
  (`L4/L5/R4/R5`, on `bind noop`'d `F9`–`F12`) are standalone hosts you bind in the Gestures tab.
  **`L4`/`R4` default to Activate WXHB-L/R — but only *while the matching trigger is held* (LT+L4,
  RT+R4)**, so they are **not** standalone display modifiers and the d-pad chords stay on LT/RT/RB;
  a bare L4/R4 (no trigger) is free to bind. **`L5`/`R5` and the trackpad zones carry no default
  gesture**. The **trackpad zones (plus
  `BACK`/`START`) ride the shared `Ctrl`**, so a gesture must not require **two of them held together**;
  the **paddles are unmodified `F9`–`F12`**, so they *can* be held/combined freely (like the plain-row
  core).

---

## Control Map (reference)

Consolidated quick-reference for the Steam-profile author and the Task 3 wiki. Authoritative detail
lives in **Resolved Decisions**, **Storage → Default `key_mapping`**, and the **Gestures** table; this
section mirrors them.

### Physical control → Native assignment → Steam Input output

"Native assignment" = the FFXI-default function of that control/key (kept as-is, or `bind noop`'d).
The profile is a **hybrid**: native gamepad passthrough for movement/targeting, keyboard for everything
the addon reads.

| Physical Controller Input | Native Assignment (FFXI) | Steam Input Assignment |
|---|---|---|
| Left stick | Move character | passthrough (native gamepad) — analog movement (Resolved Decision 8) |
| D-pad — **no** trigger held | Party/alliance & menu targeting | passthrough (native gamepad) |
| D-pad — LT/RT/RB held (chord) | dead | `9` `0` `` ` `` `=` (chorded onto native d-pad) |
| Right stick — **no** LB held | Camera | passthrough (native gamepad) — analog camera (Resolved Decision 8) |
| Right stick ↑/↓ — **LB held** (LB layer) | Camera zoom | `.` / `,` |
| LT / RT | dead | `1` / `2` |
| LB / RB | dead | `3` / `4` |
| A / B / X / Y | dead | `5` / `6` / `7` / `8` |
| BACK (Select/View) | Macro palette → **`bind noop` on load** | `Ctrl+1` |
| START (Menu/Options) | Macro palette → **`bind noop` on load** | `Ctrl+2` |
| Trackpad zones 1–8 | Macro palette → **`bind noop` on load** | `Ctrl+3` … `Ctrl+0` |
| Paddle L4 / L5 / R4 / R5 | F9–F12 → **bind-noop on load** | `F9` / `F10` / `F11` / `F12` |

### Virtual gesture → Action

| Input (gesture) | Type | Action |
|---|---|---|
| Hold LT | `hold` | Activate **XHB-L** (cycling set, left 8) |
| Hold RT | `hold` | Activate **XHB-R** (cycling set, right 8) |
| Hold **LT + L4** / **RT + R4** | `hold_then_hold` | Activate **WXHB-L / WXHB-R** (paddle path; a trigger must be held) |
| Double-tap LT / RT | `double_tap` | Activate **WXHB-L / WXHB-R** (paddle-free alternate) |
| Hold LT then RT | `hold_then_hold` | Activate **Expanded LT→RT** |
| Hold RT then LT | `hold_then_hold` | Activate **Expanded RT→LT** |
| Face or d-pad, **trigger held** | `button` | `execute_slot` (d-pad→1–4, face→5–8 of displayed half) |
| Tap LB (no trigger) | `tap` | `auto_run` |
| Tap RB (no trigger) | `tap` | `cycle_set` |
| Hold LT/RT + press **LB** | `hold_then_press` | `target_previous` |
| Hold LT/RT + press **RB** | `hold_then_press` | `target_next` |
| Hold LB + press RB (no trigger) | `hold_then_press` | `mode_switch` (→ `dismount` if mounted) |
| Hold RB + face/d-pad (no trigger) | `button` | `switch_set_1` … `switch_set_8` (direct jump) |
| BACK, while XHB-L/R active | `button` | `open_binder` (toggle) |
| No trigger + hold LB + right-stick ↑/↓ | Steam-direct | zoom in / out (`.` / `,`) |
| Bare **A** (no trigger) | `button` | `menu_confirm` — `setkey enter` |
| Bare **B** (no trigger) | `button` | `menu_cancel` — `setkey escape` |
| Bare **X** (no trigger) | `button` | `map` (wrapper → `/map`) |
| Bare **Y** (no trigger) | `button` | `jump` (wrapper → `/jump`) |
| Bare **START** (no trigger) | `button` | `menu_open` — `setkey numpad-` |
| Bare **BACK** (no trigger) | `button` | `menu_focus` — `setkey numpad+` |

Precedence: while any trigger (LT/RT) is held, LB/RB are **always** `target_previous`/`target_next`, so
`auto_run` / `cycle_set` / `mode_switch` / direct-switch all require **no trigger held** (Resolved
Decision 4). WXHB via paddles is **LT+L4 / RT+R4** (a trigger must be held), so the d-pad chords
stay on **LT/RT/RB** and L4/R4 are not standalone modifiers. **BACK is context-split:** a **bare
BACK** (no trigger) fires `menu_focus` (`setkey numpad+`, focus the active window); **BACK while a
trigger is held** (XHB-L/R active) toggles the Binder. The two never collide.

### Setup — Steam Input profile + FFXI gamepad config

Two things are configured **outside the addon** and are prerequisites for it to work. Both must be
documented for the player (Task 3 Wiki) and are summarized here as the authoritative spec.

**A. FFXI gamepad configuration (in-game).** The addon runs as a **hybrid** (Resolved Decision 8), so
FFXI's own gamepad config owns the three native-passthrough controls and **nothing else**:

- **Enable gamepad support** in FFXI's config **alongside** keyboard input — the two must coexist. With
  gamepad disabled, native left-stick movement, no-trigger d-pad targeting, and right-stick camera all
  break.
- **Assign only these three native functions** in FFXI's gamepad config:
  - **Left stick → character movement.**
  - **Right stick → camera.** The right stick is native analog camera whenever LB is not held (the addon
    never reads it); the LB zoom layer is Steam-direct, so no arrow-key binding is needed.
  - **D-pad → targeting** (party / alliance members and the menu cursor).
- **Leave every other gamepad button blank / unassigned** in FFXI's config. Steam Input remaps all of
  them to the keyboard outputs the addon reads, so they must carry **no** native FFXI gamepad action —
  otherwise a single press could double-fire (native action *and* addon gesture).
- Leave the **plain number row** and **`F1`–`F8`** as their FFXI defaults (number row is inert; the
  addon `bind noop`s the `Ctrl`+number macro palette and `F9`–`F12` itself at load).

**B. Steam Input profile (per-control).** The profile is a **hybrid**: native gamepad for
movement/targeting, keyboard for everything the addon reads. Structure:

- **Left stick →** native gamepad (movement passthrough).
- **D-pad →** native gamepad (party/alliance & menu targeting), **plus button-chord outputs**: while
  **LT**, **RT**, **or RB** is held, each direction emits its mapped key (`9`/`0`/`` ` ``/`=`). Three
  chord sets (LT+d-pad, RT+d-pad, RB+d-pad) over the same four directions.
  - **How to set this up in Steam Input (important — prevents a double-fire):** leave the d-pad's
    **base** binding as the native gamepad d-pad, then add the keyboard outputs as **Chorded Bindings**
    on the d-pad, one *chord activator* per modifier (LT, then RT, then RB). Steam must **suppress the
    base d-pad output while a chord is active** so that a trigger-held d-pad press emits **only** the
    mapped key — *not* the native d-pad as well. In the Steam controller-config UI: open the d-pad,
    **Add Chorded Command**, set the activator to Left Trigger, and bind each direction to `9`/`0`/`` ` ``/`=`;
    repeat with Right Trigger and Right Bumper as activators. If your Steam build exposes a per-chord
    "**interrupt/replace base**" (vs. "add to base") toggle, choose **replace**; the base d-pad must not
    also fire.
  - **Verify in-game (integration-test block 6):** a **bare** d-pad press still cycles party/alliance
    targets, but **LT/RT/RB + d-pad moves the hotbar cursor only — the native target must not also
    move.** If the target still changes, the chord is *stacking* on the base d-pad; re-create the chord
    so the base binding is interrupted while the modifier is held.
- **Right stick →** native gamepad (analog camera passthrough), **plus** an **LB-held layer** overriding
  the vertical axis to `.` / `,` (zoom).
- **LT / RT / LB / RB →** single key each (`1` / `2` / `3` / `4`). LT/RT/RB additionally anchor the
  d-pad chords above.
- **A / B / X / Y →** `5` / `6` / `7` / `8`.
- **BACK / START →** `Ctrl+1` / `Ctrl+2`; **trackpad zones 1–8 →** `Ctrl+3` … `Ctrl+0` (discrete; never
  chorded together — they ride the shared `Ctrl`).
- **Paddles L4 / L5 / R4 / R5 →** `F9` / `F10` / `F11` / `F12` (unmodified, freely combinable).

Constraint carried from Resolved Decision 1: **no two controls that can be held together may share a
modifier.** Only the discrete `Ctrl` controls (BACK/START/trackpad) use a modifier; the d-pad chords and
everything else use unmodified keys, so Steam's non-reference-counted `Ctrl` can never collapse a held
combo. The **Key-Capture Wizard** reconciles this profile with the addon's `key_mapping` on first launch.

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
| WXHB-L | Hold LT + L4 (or double-tap LT) | User-assigned set | User-configured half |
| WXHB-R | Hold RT + R4 (or double-tap RT) | User-assigned set | User-configured half |
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
| `hold` | Hold LT (XHB-L) | min hold to engage; **stays engaged until release** — the handler may act each tick while engaged |
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
| Zoom in / out | — (Steam-direct) | no trigger + hold LB + right-stick up/down | **Steam LB layer** sends `.` / `,` natively (not an addon gesture; Resolved Decision 6) |
| Mode switch / dismount | `hold_then_press` | hold LB + press RB (no trigger held) | `mode_switch` |
| Direct-switch sets 1–8 | `button` | hold RB + face/d-pad (8 combos) | `switch_set_1` … `switch_set_8` |
| Previous / next target | `hold_then_press` | hold LT/RT (either or both), press LB / RB | `target_previous` / `target_next` |
| Activate XHB-L / XHB-R | `hold` | LT / RT | `activate_xhb_l` / `activate_xhb_r` |
| Activate WXHB-L / WXHB-R | `hold_then_hold` | **LT then L4 / RT then R4** (paddles) | `activate_wxhb_l` / `activate_wxhb_r` |
| Activate WXHB-L / WXHB-R (alt) | `double_tap` | LT / RT | `activate_wxhb_l` / `activate_wxhb_r` |
| Activate Expanded LT→RT / RT→LT | `hold_then_hold` | LT then RT / RT then LT | `activate_expanded_lt_rt` / `activate_expanded_rt_lt` |
| Execute slot | `button` | face/d-pad while a **trigger** (LT/RT) is held | `execute_slot` (display mode resolved from modifier state) |
| Menu / command (bare) | `button` | A / B (no trigger) · X / Y (no trigger) · START · BACK | `menu_confirm` / `menu_cancel` · `map` / `jump` · `menu_open` (START) · `menu_focus` (BACK) |
| Open binder | `button` | BACK while XHB-L/R active (a trigger held) | `open_binder` |

### Resolution rules
1. The gamepad module tracks which modifiers are held (LT/RT/RB/LB/L4/R4), and the display state machine
   (XHB = hold LT/RT; WXHB = LT+L4 / RT+R4, or double-tap-hold LT/RT; Expanded = LT+RT, first-pressed
   trigger as anchor). Note **WXHB always has a trigger held**, so LT/RT remain the display modifiers.
2. A face/d-pad press while a **trigger (LT/RT)** is held → `execute_slot` in the active display mode;
   the module maps the button to the displayed half's slot (d-pad → 1–4, face → 5–8, relative to the
   half).
3. A face/d-pad press while **RB** is held (no display modifier) → `switch_set_N` (direct switch).
4. **If any trigger (LT/RT) is held, `LB = target_previous` and `RB = target_next`, full stop**
   (Resolved Decision 4) — this covers XHB and WXHB alike (WXHB always has a trigger held). This takes
   priority over the buttons' no-trigger meanings (LB-tap `auto_run`, RB-tap `cycle_set`). Direct-switch
   (`switch_set_N`, RB + face/d-pad) and `mode_switch` (LB + RB) therefore require **no trigger held**,
   so `(button × context)` is never ambiguous. Zoom is the **LB + right-stick** gesture with no trigger
   held (Resolved Decision 6), fired via Steam-direct `.` / `,`; the stick is not a slot input, so it
   never conflicts.
   - **`mode_switch` is anchored on LB** (hold **LB**, then press **RB**). The reverse — hold **RB**,
     then tap **LB** — is **intentionally unmapped** (no default action); it is a free
     `(RB-held × LB)` context a user may bind later, and doing nothing by default keeps the anchor
     direction unambiguous.
5. `open_binder` only dispatches when XHB-L or XHB-R is the active display mode.
6. `mode_switch` is context-sensitive: it checks `player_state.is_mounted` at dispatch and routes to
   `dismount` if mounted, `toggle_mode` otherwise.

### Custom / user-added gestures
The default table above is just the shipped set. `gestures` is a **data-driven array**, and the
Gestures config tab lets you **add / edit / remove** entries (not only tune timing). So a new gesture
like **tap L5 (a free paddle) → `inventory`**, or rebinding **bare X** from `map` to something else, is
fully supported. Each entry is
`{ id, button + required modifier context, type, action, timing params }`, where `action` is a
registered system action (including the command-wrapper actions like `jump`/`map`/`inventory`) **or**,
as an escape hatch, a raw windower command string.

Two limits govern what can host a new gesture:
- **Only buttons the addon can see in that context.** Triggers, bumpers, faces, BACK, START, and
  paddles/trackpad are always visible; **bare faces are freely bindable** (the shipped
  `menu_confirm`/`menu_cancel`/`map`/`jump` are just defaults you can override). The **right stick is
  native gamepad camera and is not addon-visible** (zoom is Steam-direct), so it cannot host a gesture.
  The **d-pad is visible only while a trigger (LT/RT/RB) is held** (the hold layer); with no modifier it
  stays native for party/alliance targeting, so a no-modifier d-pad gesture is not possible. Two
  `Ctrl`-riding controls (`BACK`/`START`/trackpad) may not be required *held together* (Resolved
  Decision 1); paddles (unmodified `F9`–`F12`) may.
- **No clobbering reserved roles.** A `(button × context)` already claimed by a built-in cannot be
  reused — e.g. face/d-pad while a trigger is held is always `execute_slot`, and LB/RB while a trigger
  is held are always target-switch.

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
A gesture's `action` (or a slot binding) is a **registered action** — a named module registered at
load; new actions register without touching core code. The full assignable set, with descriptions:

**Display / hotbar**

| Action | Description |
|---|---|
| `activate_xhb_l` | While engaged, show XHB-L — the current cycling set's left half (slots 1–8). |
| `activate_xhb_r` | While engaged, show XHB-R — the current cycling set's right half (slots 9–16). |
| `activate_wxhb_l` | While engaged, show WXHB-L — the user-assigned set + configured half. |
| `activate_wxhb_r` | While engaged, show WXHB-R — the user-assigned set + configured half. |
| `activate_expanded_lt_rt` | While engaged, show the Expanded LT→RT view (assigned set + half). |
| `activate_expanded_rt_lt` | While engaged, show the Expanded RT→LT view (assigned set + half). |
| `execute_slot(display_mode, slot_index)` | Fire the binding in the addressed slot of the active display half. |
| `cycle_set` | Advance the XHB to the next set in the current mode's pool (skips empty / `skip_cycle`). |
| `switch_set_1` … `switch_set_8` | Jump the XHB directly to set position N; mode/pool unchanged. |
| `mode_switch` | Toggle shared/job mode — routes to `dismount` instead if mounted. |
| `toggle_mode` | Toggle the shared/job cycling pool (no dismount branch). |
| `open_binder` | Toggle the in-game Binder open/closed. |

**Character / game**

| Action | Description |
|---|---|
| `auto_run` | Toggle auto-run. |
| `dismount` | Dismount the current mount. |
| `target_previous` | Select the previous target in the cycle. |
| `target_next` | Select the next target in the cycle. |

**`setkey` synthesis** (Resolved Decision 2 — reproduce native input from inert keys)

| Action | Maps to | Description |
|---|---|---|
| `menu_confirm` | `setkey enter` | Confirm / open chat. |
| `menu_cancel` | `setkey escape` | Cancel / back out. |
| `menu_open` | `setkey numpad-` | Open the main menu. |
| `menu_focus` | `setkey numpad+` | Focus the active window. |
| `zoom_in` | `setkey .` | Camera zoom in (the default LB+right-stick zoom is Steam-direct). |
| `zoom_out` | `setkey ,` | Camera zoom out. |

**Command wrapper actions** — wrap a command or `setkey` chord so a gesture/slot references a **name**,
never a bare string; default `icon = 'item'` (used when slotted; gestures render no icon). Exact
`setkey` chords confirmed in Task 1. (`map` wraps the `/map` command — distinct from the `map` binding
*type*, same effect.)

| Action | Maps to | Description |
|---|---|---|
| `jump` | `/jump` | Jump. |
| `map` | `/map` | Open the map. |
| `inventory` | `setkey` Ctrl+I | Open Inventory. |
| `equipment` | `setkey` Ctrl+E | Open Equipment. |
| `case` | `/case` | Open the Case. |
| `satchel` | `/satchel` | Open the Satchel. |
| `sack` | `/sack` | Open the Sack. |
| `ward1` | `/ward1` | Open Ward 1. |
| `ward2` | `/ward2` | Open Ward 2. |

**Raw command (escape hatch):** a gesture/slot may still fire an arbitrary windower command string
directly, but all shipped defaults use the named actions above.

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

## Frontend (split modules)

The former single `frontend.lua` is **split into per-concern modules** so no one file grows unwieldy:
`hud.lua` (persistent HUD), `config_ui.lua` (config GUI tabs), `tester.lua` (Gamepad Tester), and
`wizard.lua` (Key-Capture Wizard). The **Binder** is its own module (`binder.lua`, Task 2c). Each is
tested independently; the functional descriptions below map onto those files.

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
  does), the HUD hides **and** the addon suspends gesture dispatch and bare-face synthesis so native
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
before any mapping exists. A `learn_mode` flag in main replaces normal gesture→action dispatch with
raw key capture; closing restores normal dispatch.

**Capture state machine (frontend), driven by raw key-down events:**
- Walks an **ordered button list**: triggers/bumpers first (`LT, RT, LB, RB`), then `BACK`, `START`,
  face (`A, B, X, Y`), and the **d-pad hold-layer** (`DPAD_UP/DOWN/LEFT/RIGHT`) last; optional
  paddles/trackpad follow (skippable). The **right stick is native gamepad camera** and is not captured.
- Each step shows a prompt ("Press **LT**"), waits for the next key-down, echoes the captured key, and
  advances. **Skip** (leave unmapped — for optional paddles/trackpad) and **Back/Redo** (re-capture the
  previous button) are always available.
- **D-pad steps require a held trigger** — the Steam d-pad chords only emit d-pad keys while LT/RT/RB is
  down. Because triggers are captured first, the wizard instructs "**Hold LT, then press D-pad Up**" and
  verifies a trigger key is currently down before accepting the d-pad key.
- **Collision detection:** a code already bound to an earlier button is rejected and re-prompted, naming
  the button that already owns it — two virtual buttons may never share a keyboard code.

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

Buttons map to keys FFXI does not act on — the **dead number row** for held-together controls, and
**`Ctrl` + number row** for discrete ones (Resolved Decision 1). The **right stick is native gamepad
camera** and has no `key_mapping` entry. Illustrative assignment (final codes = whatever the Steam
profile emits / the wizard captures):

**Plain number row (dead in FFXI; the held-together core, no modifier):**

| Virtual button | Default key |
|---|---|
| `LT` / `RT` | `1` / `2` |
| `LB` / `RB` | `3` / `4` |
| `A` / `B` / `X` / `Y` | `5` / `6` / `7` / `8` |
| `DPAD_UP/RIGHT/DOWN/LEFT` | `9` / `0` / `` ` `` / `=` (LT/RT/RB chord only) |

**`Ctrl` + number row (discrete; never held together — macro palette `bind noop`'d on load, restored on unload):**

| Virtual button | Default key |
|---|---|
| `BACK` | `Ctrl+1` |
| `START` | `Ctrl+2` |
| `TRACKPAD_1..8` | `Ctrl+3` … `Ctrl+0` |

**Rear paddles (unmodified `F9`–`F12`, `bind noop`'d on load, restored on unload — so they can be held/combined):**

| Virtual button | Default key |
|---|---|
| `L4` / `L5` / `R4` / `R5` | `F9` / `F10` / `F11` / `F12` |

Zoom is the **LB layer** (Resolved Decision 6): while LB is held, Steam sends the right stick's vertical
axis straight to the native zoom keys `.` / `,` — no addon key consumed, and no modifier on the held
stick (ref-count-safe).

**Default bare-press gestures** (no trigger held; bare presses are configurable — Resolved Decision 2):

| Button | Default action | Mechanism |
|---|---|---|
| `A` | `menu_confirm` | `setkey enter` (confirm / open chat) |
| `B` | `menu_cancel` | `setkey escape` (cancel) |
| `X` | `map` | wrapper action → `/map` |
| `Y` | `jump` | wrapper action → `/jump` |
| `START` | `menu_open` | `setkey numpad-` (open menu) |
| `BACK` | `menu_focus` | `setkey numpad+` (focus active window; bare BACK only — trigger+BACK toggles the Binder) |

No two **held-together** controls share a modifier, so releasing one of a held combo (e.g. LT+RT for
Expanded, or two paddles) never collapses another — the Steam Ctrl reference-counting bug is avoided.
The number row is **inert in gameplay** so nothing leaks. Load-time key changes (restored on unload):
`bind ^1 … ^0 ^`  ^= <addon> noop` (the `Ctrl`+number macro palette) and `bind f9/f10/f11/f12 <addon> noop`
(the paddle keys). **`F1`–`F8` stay bound** (target/party selection intact). Note the number row **does type
during text entry**: while chat/console is open, **slot** dispatch suspends (Resolved Decision 3) — the
bare-face menu synth stays live to dismiss chat — and the physical keyboard types normally.

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
- Where the dispatch-suspend states (`test_mode`, `binder_mode`, `learn_mode`, event/cutscene,
  `menu_open`, `chat_open`) live (main) vs. where they are asserted (tester/wizard tests,
  binder tests).
- The **input contract (no suppression)**: mapped buttons are keys FFXI does not act on — the dead
  number row (held-together core) and `Ctrl`+number (discrete controls; that macro palette `bind noop`'d
  on load, restored on unload). The keyboard handler only **reads** presses → virtual button events;
  it never returns `true` to block the game (verified in-game — that cannot work). Native effects are
  produced actively: `send_command` for slot bindings and command-wrapper actions (bare `X → map`,
  `Y → jump`), and **`setkey` synthesis** for the menu actions (bare `A → enter`, `B → escape`,
  `START → numpad-`). No two **held-together** controls share a modifier (ref-count-safe). See Resolved
  Decisions 1 / 2 and **Input Model**.
- The **logger interface** (`log.debug` / `log.info` / `log.error` / `log.set_debug` / `log.toggle`),
  which every module calls; `debug_enabled` is owned by `log`, defaults false, and is not persisted.

---

## Task Decomposition

**Input model (verified in-game).** `return true` **cannot** block any key FFXI acts on, but **`setkey`
reliably drives native input**. The model is therefore *inert keys (dead number row + `bind noop`'d
`Ctrl`+number and paddles) + `setkey` synthesis* (Resolved Decisions 1–3, 6) — no suppression. Zoom
tokens are `.`/`,`; `menu_open`/`chat_open` are usable dispatch-suspend signals.

Tasks 1a/1b/1c/1d are independent (parallel). Tasks 2a/2b/2c depend on all Task 1s merged (parallel
with each other). Task 3 is final integration.

### Task 1a — Input + Gamepad modules
**Files:** `xivgamepad/input/keyboard.lua`, `xivgamepad/gamepad.lua`, `tests/xivgamepad/test_input.lua`,
`tests/xivgamepad/test_gamepad.lua`
Keyboard module: key codes → virtual button names via configurable mapping; `on_button_event`
callback with **rising/falling edge detection** (OS auto-repeat collapsed to one press/release). The
handler only **reads** — it never returns `true` (Resolved Decisions 1/2; blocking via `return true`
is impossible), so there is no consume/edge-suppression state. Gamepad module: modifier +
button-state tracking, all six gesture types, modifier×button resolution to `on_gesture(id)`,
**wall-clock (`coroutine.schedule`) timing** for thresholds/windows (Resolved Decision 5). No
settings/UI deps. Tests drive press/release directly, **stub the scheduler**, and assert auto-repeat
is deduped and each gesture resolves to exactly one action (incl. the RB+trigger precedence).

### Task 1b — Action module
**Files:** `xivgamepad/action.lua`, `tests/xivgamepad/test_action.lua`
Type registry (`register_type`), system-action registry (`register_action`), overlay-type registry,
`resolve_binding`, and `execute`. All binding type codes and system actions implemented — including
the **`setkey`-synthesis actions** (`menu_confirm`/`menu_cancel`/`menu_open`/`menu_focus`,
`zoom_in`/`zoom_out`). `send_command`/`setkey` are stubbed in tests (assert the exact emitted
command/token); unknown type/action logs without raising.

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
logout hides UI + discards staging, destroy on unload). **On load** it makes the non-dead keys inert —
`bind ^1 … ^0 ^`  ^= <addon> noop` (the `Ctrl`+number macro palette) and `bind f9/f10/f11/f12 <addon> noop`
(the paddle keys) — and **on unload** restores both (mirrors xivcrossbar's `bind noop` camera-key
pattern for game-active keys; the
plain number row needs neither — it is already dead). Commands:
`config`/`c`, `save`/`s`,
`discard`/`d`, `help`, `test`/`t`, `learn`/`l`, `debugmode`/`dbg` (routes to `log.toggle`). On `login`, **offers the Key-Capture Wizard** when
`key_mapping_complete` is false (dismissable; keeps `init` idempotent). Registers the
buff/job-change/status Windower events that maintain `player_state`. Owns the dispatch-suspend states —
`test_mode`, `binder_mode`, `learn_mode` (raw key capture for the wizard), an **event/cutscene
state** (from `status change` id 4) that hides the HUD and halts gesture dispatch + bare-face synthesis
so native cutscene controls work, a **menu state** (`get_info().menu_open`) and a **text-input state**
(chat/console open, via `get_info().chat_open`) that suspend hotbar slot dispatch while a menu or chat
is open (bare-face menu synthesis keeps working during **both** `menu_open` and `chat_open`); all
restore on exit (Resolved Decision 3). Also registers a `zone change` handler and the ~1 s poll-and-diff reconciliation
(Resolved Decision 7).

### Task 2b — Frontend modules (HUD / Config UI / Tester / Wizard)
**Files:** `xivgamepad/hud.lua`, `xivgamepad/config_ui.lua`, `xivgamepad/tester.lua`,
`xivgamepad/wizard.lua`, `tests/xivgamepad/test_hud.lua`, `tests/xivgamepad/test_config_ui.lua`,
`tests/xivgamepad/test_tester.lua`, `tests/xivgamepad/test_wizard.lua`
Split from a single frontend so no file grows unwieldy. **`hud.lua`** — clock-sweep recast,
unusable/badge overlays, transparency, draggable HUD during config, cutscene hide. **`config_ui.lua`** —
config GUI (4 tabs) on lib/settings `config_gui` with unconditional `on_mouse` delegation; hosts the
Capture/Re-learn button that launches the wizard. **`tester.lua`** — Gamepad Tester overlay
(`//xg test`), gesture→tester display replacing dispatch. **`wizard.lua`** — key-capture state machine
(ordered-button walk incl. `START`, collision detection, d-pad-requires-trigger sequencing, staging
commit on finish). Tests call build-tabs / on_mouse directly with stubbed UI, assert tester suppression
display, and feed raw key-down sequences to the wizard to assert mapping, collision rejection,
d-pad-trigger gating, and cancel-leaves-mapping-untouched.

### Task 2c — Binder UI (depends on 1b + 1c)
**Files:** `xivgamepad/binder.lua`, `tests/xivgamepad/test_binder.lua`
Menu system toggled open/closed by the BACK-while-XHB gesture (stays open until toggled closed).
Navigated via the d-pad + face buttons while a trigger is held (d-pad chords live; d-pad = move, face
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
  overview / home; **Installation & Setup** — a step-by-step **FFXI gamepad configuration** page (enable
  gamepad alongside keyboard; left stick = movement, right stick = camera, d-pad = targeting, every
  other button blank) **and a Steam Input profile page** (per-control mapping: native left stick, native
  right stick + LB zoom layer, native d-pad + LT/RT/RB chords, the number-row/`Ctrl`-number/paddle key
  outputs), authored from the **Setup — Steam Input
  profile + FFXI gamepad config** spec above — followed by the **first-launch Key-Capture Wizard** to
  record the mapping; Controls & Gestures; Hotbar Sets & Display Modes (XHB / WXHB /
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
5. **Input & synthesis** — face key under a trigger fires the slot with **no chat/menu leak** (dead
   keys); LT+RT then release one → the other stays live (no Ctrl-collapse); bare (no-trigger) presses
   fire their bound action (A→confirm `setkey enter`, B→cancel `setkey escape`, X→`map`, Y→`jump`,
   START→open menu `setkey numpad-`, BACK→focus window `setkey numpad+`); **menu open (`menu_open`) and
   chat open (`chat_open`) both suspend slot dispatch while the bare menu-nav synth (A/B/BACK) keeps
   working** (navigate the menu; dismiss the chat bar the controller opened); cutscene (status 4) → HUD
   hides + dispatch/synth halt + scene advances, exit restores; `//xg test` → tester replaces dispatch,
   close restores.
6. **Native pass-throughs** — no-modifier d-pad selects party **and alliance**; **LT/RT/RB + d-pad moves
   the hotbar cursor only, with no native target change** (the Steam chord suppresses the base d-pad —
   catches a stacking chord that double-fires); right-stick pans the native camera; **no trigger + LB +
   right-stick up/down zooms** (via `setkey . / ,`) without panning.
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
- `lib/settings/config_gui.lua` — required by `xivgamepad/config_ui.lua`.
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
11. Open an in-game menu (equipment / shop): bare (no-trigger) **A → confirm**, **B → cancel**, and
    **BACK → focus window** drive the menu **natively** via `setkey` (**START → open menu** does so from
    the field); the `menu_open` gate suspends slot dispatch so a trigger press does not fight the menu.
12. Character switch — settings reload per character, no clobber. `//lua r xivgamepad` — clean reload,
    HUD and positions restored from disk.
13. Fresh install (no `key_mapping`) → login offers the **Key-Capture Wizard**; pressing each prompted
    button records its key; the d-pad steps only accept input while a trigger is held; a duplicate key
    is rejected with the conflicting button named; **finish** persists `key_mapping` and sets
    `key_mapping_complete`; **cancel** leaves any prior mapping untouched. `//xg learn` re-opens it with
    current values pre-loaded.
14. Hold RT and press the confirm face button to execute a slot → the slot fires and **no chat bar
    opens** (the face key is a dead number-row key). With no trigger held, a bare confirm/cancel/menu
    face press **synthesises** the native key (chat/confirm, cancel, open menu) via `setkey`.
15. With XIVGamepad loaded, in the open field the number-row buttons are **dead** (no game reaction);
    open chat and the **physical keyboard number row types normally** while gesture dispatch
    **suspends**; close chat and the mapped keys resume driving the addon. Likewise open a menu →
    `menu_open` suspends slot dispatch, close → resumes. Confirm `Ctrl`+number (macro palette) is
    `bind noop`'d (neutralized — no macro fires) while loaded and restored after `//lua unload`.
16. `//xg debugmode` → debug lines start appearing in chat **and** `data/debug.log`; run it again → they
    stop and the file is left as-is. After `//lua r xivgamepad`, debug mode is off again (default).

---

## Resources

- FFXIV cross hotbar guide — https://www.akhmorning.com/resources/controller-guide/the-cross-hotbar/
- FFXIV UI guides — https://na.finalfantasyxiv.com/uiguide/know/know-xhb/ (switching, hold, change,
  how-to)
- XIVHotbar2 (Windower) — https://github.com/WGINC/XIVhotbar2-Petit_Trois_Edition
- xivcrossbar (Windower) — `./xivcrossbar` (external git submodule; reference only)
- Windower FFXI functions (`get_info().menu_open` / `chat_open`) — https://github.com/Windower/Lua/wiki/FFXI-Functions
- Windower input commands (`setkey`) — https://docs.windower.net/commands/input/
