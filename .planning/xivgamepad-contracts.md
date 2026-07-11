# XIVGamepad — Frozen Interface Contracts

Companion to `.planning/xivgamepad.md` (the plan, which is authoritative on behavior). These shapes
are **frozen** so Tasks 1a/1b/1c/1d and later 2a/2b/2c can proceed in parallel without integration
churn. Do not deviate silently — if a contract proves unworkable, stop and surface it.

## Module layout & require paths

Windower's addon `package.path` covers the addon's OWN directory (the `{AddonPath}?.lua`
template) plus the shared `addons/libs` — NOT the addons root. Intra-addon requires therefore
use flat names for addon-root files and slash-relative names for subdirectories; the xivcrossbar
submodule (runs in-game) is the reference for this convention (`require('gamepad')`,
`require('ui/icon_extractor')`). The test harness mirrors it by prepending `xivgamepad/?.lua`
to `package.path` in `tests/xivgamepad/mock_windower.lua`.

| File | require name |
|---|---|
| `xivgamepad/log.lua` | `log` |
| `xivgamepad/input/keyboard.lua` | `input/keyboard` |
| `xivgamepad/gamepad.lua` | `gamepad` |
| `xivgamepad/action.lua` | `action` |
| `xivgamepad/storage.lua` | `storage` |
| `xivgamepad/hud.lua` | `hud` |
| `xivgamepad/config_ui.lua` | `config_ui` |
| `xivgamepad/tester.lua` | `tester` |
| `xivgamepad/wizard.lua` | `wizard` |
| `xivgamepad/binder.lua` | `binder` |

- Every module **returns its module table**; test-only accessors are `_`-prefixed functions on that
  table (the echo/test-harness pattern).
- Modules that log `require('log')`. During parallel Task-1 development the real logger
  may not exist in your worktree: your **test files** preload a stub via
  `package.loaded['log'] = stub` *before* requiring your module. Never stub it inside the
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

## Input module — `input/keyboard`

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

## Gamepad module — `gamepad`

```lua
gamepad.init({ schedule = fn })       -- schedule(fn, seconds): wall-clock one-shot timer.
                                      -- Production passes a coroutine.schedule wrapper; tests stub.
gamepad.set_gestures(gestures_array)  -- data-driven config (schema below)
gamepad.set_gesture_callback(fn)      -- fn(gesture_id, params); params always a table (may be {})
gamepad.set_display_callback(fn)      -- fn(display_mode_or_nil) on every display transition
gamepad.on_button_event(name, pressed)
gamepad.get_display_mode()            -- current enum value or nil (idle)
gamepad.is_held(name)                 -- true while the named button is down (selector wiring)
gamepad.direct_switch_order()         -- fresh copy of the LIVE sets 1-8 button array, derived from
                                      -- the gestures array passed to the most recent set_gestures
                                      -- call (falls back to the shipped default for any position
                                      -- whose rb_held switch_set_N entry was removed rather than
                                      -- rebound); single source -- main injects it into hud so no
                                      -- second copy exists
gamepad.reset()                       -- drop all held/timing state
gamepad.migrate_gestures(array)       -- renumbers saved direct-switch entries still matching the
                                      -- pre-#30 factory default to the current order; in-place,
                                      -- idempotent, value-based and unconditional -- main gates
                                      -- whether it runs at all via gestures_version (below)
```

**Display-mode enum:** `'xhb_l' | 'xhb_r' | 'wxhb_l' | 'wxhb_r' | 'expand_lt_rt' | 'expand_rt_lt'`
(idle = `nil`).

Gesture entries whose `action` is one of the six `activate_*` names drive the internal display
state machine (reported via the display callback); all other entries fire the gesture callback.

**Gesture callback params:**
- `execute_slot` → `{ display_mode = <enum>, slot = 1..8 }` (slot relative to the dispatched half;
  an engaged WXHB/Expanded mode is authoritative, otherwise the half is resolved at press time
  from the most-recently-pressed currently-held trigger — never from the lagging `display.mode`,
  which would misfire the stale half or drop presses inside the hold-threshold window — issue #25)
- `direct_switch_N` → `{ set = N }`
- everything else → `{}`

**Slot/button positional order (frozen addon-wide):** within the displayed half,
`DPAD_UP=1, DPAD_RIGHT=2, DPAD_DOWN=3, DPAD_LEFT=4, A=5, B=6, X=7, Y=8`. Direct-switch
deliberately does **not** share this order (issue #30): `Y=1, B=2, A=3, X=4, DPAD_UP=5,
DPAD_RIGHT=6, DPAD_DOWN=7, DPAD_LEFT=8` — sets 1–4 on the face buttons, 5–8 on the d-pad.
(Visual arrangement is the HUD's concern; indices are fixed.)

A settings key `gestures_version` (default `0`; current value `2`) gates the migration: main only
calls `gamepad.migrate_gestures` when the loaded save's `gestures_version < 2`, and bumps it to `2`
in memory afterward (persisted on the next natural save). This is what lets a deliberate
post-swap customization that happens to recreate the old factory default byte-for-byte survive —
without the gate, `migrate_gestures`'s pure value match would silently flip it back every reload.

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
target_previous/target_next, firing immediately on the bumper press with no minimum trigger-hold
time — issue #29; direct-switch and mode_switch require no trigger; RB-held + LB tap is
intentionally unmapped).

## Logger — `log`

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

## Action module — `action`

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

## Storage — `storage`

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
`resolve_binding`, `get_player_state`, `on_element_move(element_id, x, y)`, optional
`direct_switch_order` — button array from `gamepad.direct_switch_order()` numbering the
set-selector labels), `hud.show()`,
`hud.hide()`, `hud.set_display(mode_or_nil)`, `hud.set_selector(visible)` (issue #27 RB-held
set-selector overlay; main owns the visibility rule — RB down, neither trigger down — and the
flag is ephemeral: cleared on every re-init, never persisted), `hud.refresh(view)`, `hud.tick()`
(called from
main's prerender for recast sweeps), `hud.set_draggable(bool)`, `hud.destroy()`.
View model: `view = { active_set, set_name, mode, display_mode, slots = { [1..16] = resolved
binding or nil } }`. Element positions persist under settings key `hud_positions[element_id] =
{x, y}` (element ids are hud-internal; main stages the table via `settings.stage_set`). The
`set_selector` element (default 500,300) drags and persists through the same machinery.

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
  gestures_version = 0,
  hud_positions = {},
}
```

## Main entry commands (frozen)

`config`/`c`, `save`/`s`, `discard`/`d`, `help`, `test`/`t`, `learn`/`l` (+ `learn skip|back|cancel`),
`debugmode`/`dbg` (+ `debugmode on|off`). Unknown → `print_help()`.

Load-time key neutralization (on `load`; restored on `unload`):
`bind ^`` … ^1..^0 ^= xivgamepad noop` (Ctrl+number macro palette) and
`bind f9|f10|f11|f12 xivgamepad noop` (paddles). `F1`–`F8` stay untouched.

## Crossbar port amendments (Wave 0, frozen)

Companion to `.planning/xivgamepad-crossbar-features.md`. Same rules as the base contracts: these
shapes are **frozen** so Waves 1A–1E and 2A–2C can proceed in parallel; do not deviate silently.

### `crossbar/` subtree rule

Ported third-party files live under `xivgamepad/crossbar/` with their BSD-3/MIT license headers
retained **verbatim**, plus a `-- PORT:` comment block (directly under the retained header)
enumerating **every** edit made to the file. Only these edit categories are allowed:

1. require-path fixes
2. event-registration extraction (the file exposes handlers; main registers events)
3. output/input path redirection (runtime files under `data/`, per the data-paths section)
4. Lua 5.1 parse fixes (e.g. parenthesizing string-literal method calls)
5. global hygiene (localize accidental globals)

| File | require name |
|---|---|
| `xivgamepad/crossbar/icon_extractor.lua` | `crossbar/icon_extractor` |
| `xivgamepad/crossbar/mountroulette.lua` | `crossbar/mountroulette` |
| `xivgamepad/crossbar/skillchain/skillchains.lua` | `crossbar/skillchain/skillchains` |
| `xivgamepad/crossbar/skillchain/skills.lua` | `crossbar/skillchain/skills` |
| `xivgamepad/crossbar/resource_generator.lua` | `crossbar/resource_generator` |
| `xivgamepad/crossbar/kebab_casify.lua` | `crossbar/kebab_casify` |
| `xivgamepad/crossbar/ordered_pairs.lua` | `crossbar/ordered_pairs` |
| `xivgamepad/crossbar/md5.lua` | `crossbar/md5` |

Adapter modules live at the addon root (`gamedata`, `icons`, `mounts`, `skillchain`) and follow
every monorepo convention. An adapter (or any addon-root module) must **never** be named
`resources`, `actions`, `lists`, `sets`, or `pack` — those names would shadow Windower's shared
libs on the addon search path.

### Adapter APIs (frozen)

**gamedata** — generated-resources pipeline and lookup surface:

```lua
gamedata.init(addon_path)
gamedata.ensure_fresh()          -- idempotent per session; creates data/generated/;
                                 -- regenerates on MD5 mismatch against Windower res sources
gamedata.spell(name)             -- generated spell entry or nil
gamedata.ability(name)           -- generated ability/weapon-skill entry or nil
gamedata.entry_for(binding)      -- ma -> spells; ja/ws/pet -> abilities; any other type -> nil
gamedata.icon_for(binding)       -- resolution order below; addon-relative path or nil
gamedata.recast_key(binding)     -- -> (recast_id or id, res_key)
gamedata.categories(res_key)     -- category names present in the generated table
gamedata.list(res_key, category) -- entries in that category (binder sub-menus)
```

`icon_for` resolution order: `binding.icon` → iconpack `custom_icon` (existence-checked via
`files.exists`, result cached) → `default_icon` → nil. Returned paths are **addon-relative
WITHOUT a leading slash** (upstream generator output carries a leading slash — normalize it away).

Generated files: `data/generated/crossbar_spells.lua` and `data/generated/crossbar_abilities.lua`,
loaded via `files.read` + `loadstring` inside `pcall` — **NEVER `require`**: regeneration must not
be served a stale cached module, and tests must stay on the in-memory fs. MD5 freshness is checked
against Windower's res sources read via `files.new('../../res/spells.lua')` (and
`job_abilities.lua` / `weapon_skills.lua`) — a **documented read-only walk-up exception**; the
never-walk-above-`addon_path` rule governs directory creation and writes, not these reads.

**icons** — runtime item-icon extraction:

```lua
icons.init(addon_path)
icons.item_icon(item_id_or_en_name) -- addon-relative path or nil
icons.close()
```

Extracted 32x32 BMPs are cached at `data/icons/items/{item_id}.bmp` (keyed by item id). Any
extraction failure (missing DAT, non-Windows env, bad id) returns nil and emits **one `log.debug`
per item id per session**; `item_icon` never raises into a render path.

**mounts** — owned-mount tracking and roulette:

```lua
mounts.refresh()     -- rederive owned mounts from key items
mounts.list()        -- sorted display-name array of owned mounts
mounts.ride_random() -- dismount if mounted, else mount a random owned mount
mounts.has_mounts()
```

Main wires incoming chunk `0x055` (key-item update) → `mounts.refresh()` and also calls `refresh`
from `init()`.

**skillchain** — resonance state machine (main forwards all events):

```lua
skillchain.on_action(act)
skillchain.on_incoming_chunk(id, data)
skillchain.on_job_change(job_abbrev)
skillchain.on_zone_change()
skillchain.on_login()
skillchain.on_logout()
skillchain.tick()
skillchain.prop_for(id, res_key)  -- skillchain property name or nil
skillchain.window()               -- -> (remaining_delay, remaining_window)
```

Enabled gate: an **injected getter** reading settings key `skillchain_display`. While disabled,
every query returns nil and every handler is a no-op.

### New system action (frozen)

`mount_roulette` — registered by **MAIN** via `action.register_action`. `action.lua`'s `mount`
binding type special-cases the action name `'Mount Roulette'` → `run_action('mount_roulette')`.

### New settings key (frozen)

`skillchain_display = true` (top-level default; toggled from the config GUI's Display tab).

### HUD contract additions

- `hud.init` opts gain `gamedata`, `get_skillchain_prop(binding)`, `get_skillchain_window()`
  (→ remaining_delay, remaining_window — drives the `sc_timer` element; shipped alongside
  `get_skillchain_prop` but previously omitted here), and `get_item_icon(name_or_id)`
  (→ addon-relative path or nil; main wires it as a thin closure over `icons.item_icon`).
  All are optional and degrade to the pre-port behavior when absent.
- Item-slot icon resolution (`type == 'item'`): `gamedata.icon_for` (returns the `binding.icon`
  user override when set; items are never in the generated resources, so it otherwise misses) →
  `binding.icon` → `get_item_icon(binding.action)` → `TYPE_ICONS.item`. Resolved during
  refresh/render, never in `tick()`; the first call per item performs the DAT extraction and is
  cached (or failure-memoized) by the icons adapter thereafter.
- New draggable element id `sc_timer` ("Wait n.n" / "Go! n.n"), position persisted under
  `hud_positions.sc_timer` via the existing hud_positions machinery.
- Per-slot skillchain **highlight layer** resolved during `tick()` (time-windowed within the chain
  window). Highlight icon: `images/icons/iconpacks/default/skillchain/<prop lowercase>.png`, with
  fallbacks radiance → `light.png` and umbra → `darkness.png`.

### Binder contract additions

- `binder.init` opts gain `get_mounts` (owned display names) and `gamedata` (drives job-ability
  category sub-menus).
- The mount menu lists the owned mounts plus a `'Mount Roulette'` entry that produces the binding
  `{ type = 'mount', action = 'Mount Roulette' }`.

### Data paths

- `data/generated/` — generated resources (character-independent).
- `data/icons/items/` — extracted item icon BMPs.

### io carve-out (frozen wording)

> `xivgamepad/crossbar/icon_extractor.lua` is the single reviewed exception to the no-io rule. The
> Windower files API can neither read an arbitrary absolute path (the FFXI install under
> `windower.ffxi_path`) nor perform binary seeks into ROM DAT files. This file uses `io.open`
> read-only against the game's ROM DATs and write-only to produce 32x32 BMP files under
> `xivgamepad/data/icons/`. No other addon file may use or require `io`.

## WXHB always-show amendment (frozen)

Companion to `.planning/xivgamepad-wxhb-always-show.md`. `gamepad.lua`'s contract (state machine,
`display.mode` transitions, `execute_slot` dispatch) is **unchanged** — this is a display-only
addition resolved entirely in main's view-building and `hud`'s rendering.

### New settings key (frozen)

`always_show_wxhb = false` (top-level default; toggled from the config GUI's Display tab). A
single global flag — when `true`, both `wxhb_l` and `wxhb_r`'s assigned set/half render at
`transparency_standard` on their configured screen half whenever that half isn't currently the
live gesture-engaged half. When `false`, behavior is byte-for-byte identical to today.

### View contract addition

`hud.refresh(view)`'s `view.slots[1..16]` continues to be a single flat array, but when
`always_show_wxhb` is enabled, **main** (not hud) resolves it per screen half instead of from one
position: for each half (`half_left` = slots 1-8, `half_right` = slots 9-16), if a live gesture
currently owns that half, its content wins (unchanged today's behavior); otherwise, if
`always_show_wxhb` is true and a `wxhb_l`/`wxhb_r` view is assigned to that half (via
`display[mode].half`), that view's assigned set fills the half at `transparency_standard`;
otherwise, today's `active_set` fallback fills the half unchanged. `hud.lua` does not gain any new
content-resolution logic — it only gains the ability to render a half at `transparency_standard`
that isn't the live-active half, which the existing transparency plumbing already supports.
