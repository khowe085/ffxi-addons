# XIVGamepad — Pre-Planning Input Spike

## Status: GATE — must pass before any module work (Task 1+) begins

This spike exists because the entire input model rests on one unproven assumption:
that returning `true` from Windower's `keyboard` event actually stops FFXI from acting
on a key. xivcrossbar's own code proves this is **not** true for keys FFXI reads via
DirectInput held-state polling (camera) — it has to `bind <key> noop` those instead
(see `xivcrossbar/xivcrossbar.lua` load event and the Home/PageUp comment). The resolved
key map (see `xivgamepad.md` → Resolved Decisions) deliberately keeps **zero** held-state
camera keys in the owned set, so the remaining question is narrow but load-bearing:
**does `return true` reliably suppress the four face menu-keys (`Enter`, `Escape`,
`NumPad −`, `NumPad +`) while a trigger is held, and does a bare press still drive native
menus?** Everything else about the contract is decided; this just verifies the physics.

## The probe

A throwaway, single-file Windower addon (not shipped, not in the monorepo test suite). It
does **only** what is needed to observe the four behaviours below — no settings, no HUD, no
`lib/settings`. High level, it must:

- Register a `keyboard` event that logs every `(dik, pressed, blocked)`.
- Treat one designated key as a stand-in "trigger" (a quiet F-key) and track its held state.
- For each of the four face menu-keys: when the stand-in trigger is held, **return `true`**
  (consume) and record it; when no trigger is held, **return `false`** (pass through).
- Apply the consume-both-edges rule: if a key's key-**down** was consumed, consume its
  key-**up** too, even if the trigger was released in between.
- Expose a command that prints `windower.ffxi.get_info().menu_open` and `.chat_open`.
- Expose a command that fires the candidate zoom keystrokes via `setkey` so the exact key
  token (`.` vs `period`, `,` vs `comma`) can be confirmed on real hardware.

Test with the **actual Steam Input profile** where possible (the real keys the profile
emits), and also by pressing the physical keyboard keys directly.

## Checks (each is pass/fail, observed in-game)

1. **Suppression under a trigger.** Hold the stand-in trigger, then press each of `Enter`,
   `Escape`, `NumPad −`, `NumPad +` in turn, in a normal field state (not in a menu, chat
   closed). Expect: **no chat bar opens, no menu opens, no window focus changes** — the game
   does not act on the key. Repeat each while **releasing the trigger before the face key**;
   the key-up must still be suppressed (no leak).
2. **Bare passthrough.** With no trigger held, press each of the four keys. Expect the
   **native** result: `Enter` → chat bar; `Escape` → menu; `NumPad −` / `NumPad +` → menu /
   active-window focus. Confirms bare presses can still drive native menus.
3. **Zoom keystroke.** Fire the `setkey` zoom command. Expect the FFXI camera to **zoom in**
   on `.` and **zoom out** on `,`. Record the exact key token that works.
4. **`menu_open` semantics.** Print `menu_open` while: (a) in the open field, (b) main menu
   open, (c) a shop / equip / dialog menu open, (d) map open, (e) a target locked. Determine
   which states report `menu_open = true`, to confirm it is the right signal to suspend
   dispatch on without also killing the hotbar in states where it should stay live.

## Pass/fail → what it gates

- **Check 1 passes for all four keys** → freeze the contract as written; the owned face keys
  are suppressed via `return true` + consume-both-edges.
- **Check 1 fails for a specific key** → that key falls back to the **quiet-key + `bind noop`**
  variant (loses this key's bare-passthrough carve-out; native menus for that action move to
  another key or the keyboard). Only the failing key changes; the rest of the map stands.
- **Check 2** confirms the bare-passthrough carve-out is real (if it isn't, native-menu
  control from the controller is dropped and the binder becomes the only in-addon menu path).
- **Check 3** pins the zoom mechanism + exact key token used by the `zoom_in` / `zoom_out`
  actions.
- **Check 4** sets the exact suspend condition wired into the main module's dispatch gate.

## Out of scope for the spike

No gesture engine, no overlays, no storage, no config GUI, no wizard — those are Task 1+.
The probe is deleted once the four checks are recorded.
