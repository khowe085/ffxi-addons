# XIVGamepad — Frozen Interface Contracts

Companion to `.planning/xivgamepad.md` (the plan, which is authoritative on behavior). These shapes
are **frozen** so Tasks 1a/1b/1c/1d and later 2a/2b/2c can proceed in parallel without integration
churn. Do not deviate silently — if a contract proves unworkable, stop and surface it.

## Module layout & require paths

Tests run from the repo root (`lua tests/xivgamepad/run_tests.lua`), so the default `./?.lua`
package path resolves these; in Windower the addons root is on the package path the same way
(echo's `require('lib.settings.settings')` pattern).

| File | require name |
|---|---|
| `xivgamepad/log.lua` | `xivgamepad.log` |
| `xivgamepad/input/keyboard.lua` | `xivgamepad.input.keyboard` |
| `xivgamepad/gamepad.lua` | `xivgamepad.gamepad` |
| `xivgamepad/action.lua` | `xivgamepad.action` |
| `xivgamepad/storage.lua` | `xivgamepad.storage` |
| `xivgamepad/hud.lua` | `xivgamepad.hud` |
| `xivgamepad/config_ui.lua` | `xivgamepad.config_ui` |
| `xivgamepad/tester.lua` | `xivgamepad.tester` |
| `xivgamepad/wizard.lua` | `xivgamepad.wizard` |
| `xivgamepad/binder.lua` | `xivgamepad.binder` |

- Every module **returns its module table**; test-only accessors are `_`-prefixed functions on that
  table (the echo/test-harness pattern).
- Modules that log `require('xivgamepad.log')`. During parallel Task-1 development the real logger
  may not exist in your worktree: your **test files** preload a stub via
  `package.loaded['xivgamepad.log'] = stub` *before* requiring your module. Never stub it inside the
  shared mock.
- Shared harness: `tests/xivgamepad/mock_windower.lua` + `tests/xivgamepad/run_tests.lua` are seeded
  before parallel work. `run_tests.lua` pre-lists every planned `test_*.lua` and warn-skips absent
  files, so task agents never edit it. The mock may be extended **additively only** (new stub
  methods/fields, new fixtures); never change existing mock behavior. Resource fixtures are
  augmented from test files by mutating the loaded table (e.g. `res.spells[n] = {...}`), not by
  editing the mock.

## Virtual buttons (exact strings)

`LT RT LB RB A B X Y DPAD_UP DPAD_RIGHT DPAD_DOWN DPAD_LEFT BACK START L4 L5 R4 R5
TRACKPAD_1 .. TRACKPAD_8`

## key_mapping schema (settings key `key_mapping`)

`key_mapping[button_name] = { code = <DIK number>, ctrl = <bool, omitted = false> }`

Default mapping (DirectInput key codes; what the recommended Steam profile emits):

| Button | Key | code | ctrl |
|---|---|---|---|
| LT / RT | `1` / `2` | 2 / 3 | |
| LB / RB | `3` / `4` | 4 / 5 | |
| A / B / X / Y | `5` / `6` / `7` / `8` | 6 / 7 / 8 / 9 | |
| DPAD_UP / DPAD_RIGHT | `9` / `0` | 10 / 11 | |
| DPAD_DOWN / DPAD_LEFT | `` ` `` / `=` | 41 / 13 | |
| BACK / START | Ctrl+`1` / Ctrl+`2` | 2 / 3 | true |
| TRACKPAD_1..8 | Ctrl+`3` … Ctrl+`0` | 4..11 | true |
| L4 / L5 / R4 / R5 | F9 / F10 / F11 / F12 | 67 / 68 / 87 / 88 | |

Ctrl itself is DIK 29 (LCTRL) / 157 (RCTRL), tracked inside the keyboard module and never a
virtual button.

## Input module — `xivgamepad.input.keyboard`

```lua
keyboard.configure(key_mapping)     -- install/replace the mapping (init and on save)
keyboard.set_callback(fn)           -- fn(button_name, pressed_bool); edge events only
keyboard.set_raw_callback(fn|nil)   -- learn mode: fn(dik, ctrl_down) on every key-DOWN edge
keyboard.on_key(dik, pressed)       -- raw handler main registers on the 'keyboard' event
keyboard.is_ctrl_down()
keyboard.reset()                    -- clear all held state (login/zone)
```

- `on_key` collapses OS auto-repeat: only rising/falling edges reach callbacks. It **never returns
  true** (Resolved Decisions 1/2 — blocking is impossible; the handler only reads).
- Ctrl-gated buttons match only when Ctrl is down at the key-down edge; a key's **release maps to
  whatever button its press mapped to**, so a Ctrl release mid-hold cannot strand a pressed button.

## Gamepad module — `xivgamepad.gamepad`

```lua
gamepad.init({ schedule = fn })       -- schedule(fn, seconds): wall-clock one-shot timer.
                                      -- Production passes a coroutine.schedule wrapper; tests stub.
gamepad.set_gestures(gestures_array)  -- data-driven config (schema below)
gamepad.set_gesture_callback(fn)      -- fn(gesture_id, params); params always a table (may be {})
gamepad.set_display_callback(fn)      -- fn(display_mode_or_nil) on every display transition
gamepad.on_button_event(name, pressed)
gamepad.get_display_mode()            -- current enum value or nil (idle)
gamepad.reset()                       -- drop all held/timing state
```

**Display-mode enum:** `'xhb_l' | 'xhb_r' | 'wxhb_l' | 'wxhb_r' | 'expand_lt_rt' | 'expand_rt_lt'`
(idle = `nil`).

Gesture entries whose `action` is one of the six `activate_*` names drive the internal display
state machine (reported via the display callback); all other entries fire the gesture callback.

**Gesture callback params:**
- `execute_slot` → `{ display_mode = <enum>, slot = 1..8 }` (slot relative to the displayed half)
- `direct_switch_N` → `{ set = N }`
- everything else → `{}`

**Slot/button positional order (frozen addon-wide):** within the displayed half,
`DPAD_UP=1, DPAD_RIGHT=2, DPAD_DOWN=3, DPAD_LEFT=4, A=5, B=6, X=7, Y=8`. Direct-switch uses the
same order for set positions 1–8. (Visual arrangement is the HUD's concern; indices are fixed.)

**Gestures array schema** (settings key `gestures`; user-editable, data-driven):

```lua
{ id = 'auto_run', type = 'tap', button = 'LB', context = 'bare', action = 'auto_run',
  params = { max_hold = 0.25 } }
```

- `context` enum: `'bare'` (no modifier held) | `'trigger_held'` (LT or RT) | `'rb_held'` |
  `'lb_held'`.
- `type` enum + timing param names (defaults): `button` (none) · `tap` `{max_hold=0.25}` · `hold`
  `{min_hold=0.12}` · `double_tap` `{max_gap=0.33, min_hold=0.12}` · `hold_then_hold`
  `{min_hold_first=0.12, min_hold_second=0.12}` · `hold_then_press` `{min_anchor_hold=0.12}`.
- `action` is a registered system-action name; any unrecognized string is executed as a raw
  windower command (escape hatch).

**Default gesture ids** (frozen strings; the shipped `gestures` array):
`xhb_l, xhb_r, wxhb_l_paddle, wxhb_r_paddle, wxhb_l_tap, wxhb_r_tap, expand_lt_rt, expand_rt_lt,
auto_run, cycle_set, mode_switch, target_previous, target_next, direct_switch_1..direct_switch_8,
execute_slot, open_binder, bare_a, bare_b, bare_x, bare_y, bare_start, bare_back`
mapping to actions per the plan's **Default gestures** table (bare_a→`menu_confirm`,
bare_b→`menu_cancel`, bare_x→`map`, bare_y→`jump`, bare_start→`menu_open`, bare_back→`menu_focus`).

Precedence rules are the plan's **Resolution rules** (trigger held ⇒ LB/RB are always
target_previous/target_next; direct-switch and mode_switch require no trigger; RB-held + LB tap is
intentionally unmapped).

## Logger — `xivgamepad.log`

```lua
log.init(addon_path)   -- anchor data/debug.log at the absolute addon path; repeat-safe
log.debug(fmt, ...)    -- string.format semantics; no-op while disabled
log.info(fmt, ...)     -- always chat; file too while debug on
log.error(fmt, ...)    -- always chat; file too while debug on
log.set_debug(bool)    -- turning on truncates data/debug.log and writes a session header
log.toggle()           -- returns the new state
log.is_debug()
```

`debug_enabled` starts false each load, never persisted. File I/O via the Windower `files` API
only; directory creation via `windower.create_dir` anchored at the absolute `addon_path`
(separators matched to `addon_path`, never walking above it). Lines carry `os.date` timestamps.
Depends only on `windower` + `files` (leaf module — no addon requires).

> **Files-API path rule (all modules):** the real Windower `files` library prefixes
> `windower.addon_path` onto every path itself — paths passed to `files.new`/`files.exists` must be
> **addon-relative** (`data/debug.log`, `data/{Char}/shared.json`), never absolute. Only
> `windower.create_dir` takes the **absolute** addon-anchored path. Tests assert relative keys for
> file content and absolute separator-matched strings for created dirs.

## Action module — `xivgamepad.action`

```lua
action.register_type(code, def)          -- def.execute(binding, ctx); optional def.describe(binding)
action.register_action(name, def)        -- def.run(ctx, params); optional def.icon, def.description
action.register_overlay_type(name, def)  -- def.check(condition, player_state) -> bool
                                         -- def.is_available(player_state) -> bool (binder filter)
action.resolve_binding(slot, player_state) -- first matching overlay in array order, else base;
                                           -- nil-safe (nil slot -> nil)
action.execute_binding(binding, ctx)     -- routes by binding.type; unknown type: log.error, no raise
action.run_action(name_or_command, ctx, params) -- registered action, else raw windower command via
                                                -- windower.send_command; unknowns never raise
action.set_host(host)                    -- main-injected callbacks (below)
action.get_action(name) / action.list_actions()  -- enumeration for binder/config UI
```

**host** (injected by main): `show_display(mode)`, `hide_display()`,
`execute_slot(display_mode, slot)`, `cycle_set()`, `switch_set(n)`, `toggle_mode()`,
`open_binder()`, `get_player_state()`.

**ctx**: `{ player_state = <schema>, addon_path = <string> }`. All game effects go through
`windower.send_command` (slot dispatch, wrappers, and `setkey` synthesis — a press is a
`setkey <token> down` / `setkey <token> up` pair; tests assert the exact emitted strings).
`setkey` tokens per the plan: `enter`, `escape`, `numpad-`, `numpad+`, `.`, `,`.

**Binding type codes (frozen):** `ma, ja, ws, a, ra, pet, item, mount, ta, map, ct, ex, noop`.
**Binding fields:** `type, action, target, alias, icon, equip_slot, warmup, cooldown, usable`,
plus ordered `overlays` array.

**System-action names (frozen):** `activate_xhb_l, activate_xhb_r, activate_wxhb_l,
activate_wxhb_r, activate_expanded_lt_rt, activate_expanded_rt_lt, execute_slot, cycle_set,
switch_set_1..switch_set_8, mode_switch, toggle_mode, open_binder, auto_run, dismount,
target_previous, target_next, menu_confirm, menu_cancel, menu_open, menu_focus, zoom_in, zoom_out,
jump, map, inventory, equipment, case, satchel, sack, ward1, ward2` — semantics per the plan's
**Built-in System Actions** tables. `mode_switch` checks `player_state.is_mounted` and routes to
`dismount`, else `host.toggle_mode()`.

**Overlay types (frozen):** `subjob` (condition `{ subjob = 'WHM' }`), `light_arts`,
`addendum_white`, `dark_arts`, `addendum_black`. Buff ids: Light Arts **358**, Dark Arts **359**,
Addendum: White **401**, Addendum: Black **402**. Overlay entry:
`{ overlay_type = <name>, condition = <table>, <binding fields that replace the base> }`.

## player_state schema (owned by main, passed by reference)

```lua
player_state = {
  buffs      = { [buff_id] = true },  -- set of active buff ids
  main_job   = 'SCH',                 -- 3-letter uppercase abbreviation
  sub_job    = 'WHM',                 -- or nil
  is_mounted = false,
  in_event   = false,                 -- status id 4 (cutscene/event)
}
```

## Storage — `xivgamepad.storage`

```lua
storage.load_shared(addon_path, char_name)        -- -> sets table; {} when the file is missing
storage.save_shared(addon_path, char_name, sets)
storage.load_job(addon_path, char_name)           -- -> { [job_abbrev] = sets }; {} when missing
storage.save_job(addon_path, char_name, jobs)
```

Files: `data/{CharacterName}/shared.json`, `data/{CharacterName}/job.json`.
`sets[position 1..8] = { slots = { [1..16] = <slot binding> or nil } }`. Sparse containers are
serialized as JSON **objects keyed by number strings** (`"1"`..`"16"`), decoded back to
numeric-keyed Lua tables — JSON arrays cannot hold holes. Directory creation mirrors the
lib/settings contract (`windower.create_dir`, anchored at the absolute `addon_path`, separators
matched, never above `addon_path`). Windower `files` API only — no `io`/`os.execute`/`io.popen`.

## Dispatch-suspend states (owned by main — `xivgamepad/xivgamepad.lua`)

Flags: `test_mode`, `binder_mode`, `learn_mode`, `in_event`; `menu_open`/`chat_open` are read live
from `windower.ffxi.get_info()`. Policy (Resolved Decision 3):

- `in_event` (status 4): everything halts — slot dispatch, gestures, bare synth; HUD hidden.
- `menu_open` or `chat_open`: **slot dispatch and field commands suspended**; bare-face menu synth
  (`menu_confirm`, `menu_cancel`, `menu_focus`, `menu_open`) keeps working.
- `test_mode`: gestures route to the tester display instead of actions.
- `learn_mode`: raw key capture replaces gesture dispatch.
- `binder_mode`: face/d-pad/trigger events route to binder navigation; slot dispatch suspended;
  HUD keeps rendering.

Frontends *report into* these via main; they never own the flags. Tester/wizard/binder tests
assert routing through their own entry points.

## Frontend module contracts (for parallel 2a/2b/2c)

**hud** — `hud.init(opts)` (idempotent; opts: `settings`, `addon_path`, `texts`, `images`,
`resolve_binding`, `get_player_state`, `on_element_move(element_id, x, y)`), `hud.show()`,
`hud.hide()`, `hud.set_display(mode_or_nil)`, `hud.refresh(view)`, `hud.tick()` (called from
main's prerender for recast sweeps), `hud.set_draggable(bool)`, `hud.destroy()`.
View model: `view = { active_set, set_name, mode, display_mode, slots = { [1..16] = resolved
binding or nil } }`. Element positions persist under settings key `hud_positions[element_id] =
{x, y}` (element ids are hud-internal; main stages the table via `settings.stage_set`).

**config_ui** — `config_ui.init(opts)` (gui deps + `on_save`, `on_discard`, `launch_wizard`,
staged-settings accessors), `config_ui.open(staged)`, `config_ui.close()`, `config_ui.is_open()`,
`config_ui.build_tabs(staged)` (pure/testable), `config_ui.on_mouse(type, x, y, delta)` —
delegates **unconditionally** to `gui:handle_mouse` (echo pattern). Tabs: Sets / Display / Keys /
Gestures per the plan.

**tester** — `tester.init(opts)`, `tester.open()`, `tester.close()`, `tester.is_open()`,
`tester.on_button_event(name, pressed)` (live grid), `tester.on_gesture(id, params)` (log).

**wizard** — `wizard.start(opts)` (opts: `current_mapping`, `on_finish(new_mapping)`,
`on_cancel`, ui deps), `wizard.on_raw_key(dik, ctrl_down)` (fed from
`keyboard.set_raw_callback` while `learn_mode`), `wizard.skip()`, `wizard.back()`,
`wizard.cancel()`, `wizard.is_active()`. Skip/back/cancel are driven by addon sub-commands
(`//xg learn skip|back|cancel`). Capture order: `LT, RT, LB, RB, BACK, START, A, B, X, Y,
DPAD_UP, DPAD_RIGHT, DPAD_DOWN, DPAD_LEFT`, then optional (skippable) `L4, L5, R4, R5,
TRACKPAD_1..8`. D-pad steps verify a captured trigger code is currently down. Collisions are
rejected naming the owning button. Finish → `on_finish(new_mapping)` (main commits via
`settings.stage_set` + save and sets `key_mapping_complete`); cancel leaves the prior map intact.

**binder** — `binder.init(opts)` (storage/action/settings accessors + ui deps),
`binder.toggle(ctx)` (ctx: `active_set`, `display_mode`, `mode`), `binder.close()`,
`binder.is_open()`, `binder.on_button(name, pressed)` (routed by main while `binder_mode`;
navigation pauses while no trigger is held).

## Settings defaults (frozen top-level keys)

```lua
defaults = {
  config_x = 100, config_y = 100,
  current_mode = 'job',
  active_set = 1,
  key_mapping_complete = false,
  key_mapping = <default table above>,
  sets = {
    { name = 'Set 1', source = 'job',    skip_cycle = false },
    { name = 'Set 2', source = 'job',    skip_cycle = false },
    { name = 'Set 3', source = 'job',    skip_cycle = true  },
    { name = 'Set 4', source = 'job',    skip_cycle = true  },
    { name = 'Set 5', source = 'job',    skip_cycle = true  },
    { name = 'Set 6', source = 'shared', skip_cycle = false },
    { name = 'Set 7', source = 'shared', skip_cycle = true  },
    { name = 'Set 8', source = 'shared', skip_cycle = false },
  },
  display = {
    wxhb_l       = { set = 2, half = 'left'  },
    wxhb_r       = { set = 2, half = 'right' },
    expand_lt_rt = { set = 4, half = 'right' },
    expand_rt_lt = { set = 4, half = 'right' },
  },
  hide_empty_slots = false,
  transparency_standard = 0, transparency_active = 0, transparency_inactive = 100,
  gestures = <default array above>,
  hud_positions = {},
}
```

## Main entry commands (frozen)

`config`/`c`, `save`/`s`, `discard`/`d`, `help`, `test`/`t`, `learn`/`l` (+ `learn skip|back|cancel`),
`debugmode`/`dbg` (+ `debugmode on|off`). Unknown → `print_help()`.

Load-time key neutralization (on `load`; restored on `unload`):
`bind ^`` … ^1..^0 ^= xivgamepad noop` (Ctrl+number macro palette) and
`bind f9|f10|f11|f12 xivgamepad noop` (paddles). `F1`–`F8` stay untouched.
