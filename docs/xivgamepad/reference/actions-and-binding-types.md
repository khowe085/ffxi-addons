# XIVGamepad — Actions & Binding Types (contributor reference)

Everything here is a **named module registered at load** in `xivgamepad/action.lua`
(`register_type` / `register_action` / `register_overlay_type`); new entries register without
touching core code. All game effects go through `windower.send_command`. Unknown types/actions log
via `log.error` and never raise.

## Binding type codes (slot bindings)

`execute_binding(binding, ctx)` routes on `binding.type`. Target defaults to `t`
(`target_of` → `<t>`).

| Code | Meaning | Emitted command |
|---|---|---|
| `ma` | Magic | `input /ma "<action>" <target>` |
| `ja` | Job ability | `input /ja "<action>" <target>` |
| `ws` | Weapon skill | `input /ws "<action>" <target>` |
| `pet` | Pet command | `input /pet "<action>" <target>` |
| `item` | Use item | `input /item "<action>" <target>` |
| `a` | Attack | `input /attack <target>` |
| `ra` | Ranged attack | `input /ra <target>` |
| `ta` | Switch target | `input /ta <target>` |
| `mount` | Mount | `input /mount "<action>"` |
| `map` | View map | `input /map` |
| `ct` | Raw command | `binding.action` sent verbatim |
| `ex` | Switch display mode | `host.show_display(binding.action)` — action is a display-mode enum value |
| `noop` | Empty | Renders empty (`describe` → `''`), does nothing. Used by overlays to blank a base binding. |

Binding fields: `type, action, target, alias, icon, equip_slot, warmup, cooldown, usable` +
ordered `overlays`. `alias` labels the binder/HUD; `icon` overrides the per-type icon; `usable =
false` renders the fade + indicator; `cooldown` (seconds) scales the recast sweep; `count` (when
present in the data) renders the badge.

## System actions

A gesture's `action` (or `run_action(name, ctx, params)`) resolves to one of these. Any string
that is **not** a registered action is executed as a **raw Windower command** — the escape hatch.

### Display / hotbar (host-routed)

| Action | Semantics |
|---|---|
| `activate_xhb_l` / `activate_xhb_r` | Show XHB-L / XHB-R (current cycling set, left/right half). Drive the gamepad display state machine when used in gesture entries. |
| `activate_wxhb_l` / `activate_wxhb_r` | Show WXHB-L / WXHB-R (assigned set + half). |
| `activate_expanded_lt_rt` / `activate_expanded_rt_lt` | Show the Expanded views. |
| `execute_slot` | Fire the addressed slot; params `{ display_mode, slot 1..8 }` (relative to the displayed half; right half maps to absolute 9–16). |
| `cycle_set` | Advance to the next set in the current mode's pool, skipping empty and `skip_cycle` sets. |
| `switch_set_1` … `switch_set_8` | Jump directly to set position N; mode/pool unchanged. |
| `mode_switch` | If `ctx.player_state.is_mounted` → `dismount`; else `host.toggle_mode()`. |
| `toggle_mode` | Toggle the shared/job pool (no dismount branch); jumps to the new pool's first non-empty, non-skip set. |
| `open_binder` | Toggle the Binder. The gamepad module only dispatches it while XHB-L/R is the active display. |

### Character / game

| Action | Semantics |
|---|---|
| `auto_run` | `input /autorun` (in-game verification pending; fallback would be key synthesis). |
| `dismount` | `input /dismount` |
| `target_previous` | `setkey` chord `lshift` + `tab` |
| `target_next` | `setkey` press `tab` |

### `setkey` synthesis

A press is a `setkey <token> down` / `setkey <token> up` pair (`setkey_press`); a chord wraps the
key press in modifier down/up (`setkey_chord`). Valid tokens used: `enter`, `escape`, `numpad-`,
`numpad+`, `.`, `,`, `tab`, `lshift`, `lctrl`, `i`, `e`.

| Action | Token(s) | Description |
|---|---|---|
| `menu_confirm` | `enter` | Confirm / open chat. |
| `menu_cancel` | `escape` | Cancel / back out. |
| `menu_open` | `numpad-` | Open the main menu. |
| `menu_focus` | `numpad+` | Focus the active window. |
| `zoom_in` / `zoom_out` | `.` / `,` | Camera zoom (the default LB+stick zoom is Steam-direct; these are for user gestures). |
| `inventory` | `lctrl` + `i` | Open Inventory (icon `item`). |
| `equipment` | `lctrl` + `e` | Open Equipment (icon `item`). |

### Command wrappers

Named so gestures/slots reference a name, never a bare string; `icon = 'item'` when slotted.

| Action | Command |
|---|---|
| `jump` | `input /jump` |
| `map` | `input /map` (distinct from the `map` binding *type*; same effect) |
| `case` / `satchel` / `sack` | `input /case` / `input /satchel` / `input /sack` |
| `ward1` / `ward2` | `input /ward1` / `input /ward2` |

## Overlay types

`resolve_binding(slot, player_state)` walks `slot.overlays` in array order and returns the **first
entry whose `check(condition, player_state)` passes**, else the base slot; nil-safe (nil slot →
nil). Malformed entries and unknown types are skipped with a debug log (hand-edited JSON must
degrade, not raise). `is_available(player_state)` filters the Binder's overlay-type menu.

| Type | `check` passes when | `is_available` |
|---|---|---|
| `subjob` | `player_state.sub_job == condition.subjob` | a subjob is set |
| `light_arts` | buff **358** active | main or sub job is SCH |
| `dark_arts` | buff **359** active | main or sub job is SCH |
| `addendum_white` | buff **401** active | main or sub job is SCH |
| `addendum_black` | buff **402** active | main or sub job is SCH |

First match wins — the Addendum overlays must be ordered before the Arts overlays or they can
never surface (Addendum implies the Arts buff).

## Host interface (injected by main via `action.set_host`)

`show_display(mode)`, `hide_display()`, `execute_slot(display_mode, slot)`, `cycle_set()`,
`switch_set(n)`, `toggle_mode()`, `open_binder()`, `get_player_state()`. `ctx` passed to
executions: `{ player_state, addon_path }`.
