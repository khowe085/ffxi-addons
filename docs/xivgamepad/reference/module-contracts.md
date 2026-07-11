# XIVGamepad — Module Contracts (contributor reference)

Frozen shapes originate in `.planning/xivgamepad-contracts.md`; this page reflects the code as
shipped. Every module returns its module table; `_`-prefixed functions are test-only accessors.
Require names are `{AddonPath}`-relative — Windower's addon `package.path` covers the addon's
own directory plus the shared `addons/libs`, not the addons root — so addon-root files use flat
names and subdirectories use slash-relative names: `log`, `input/keyboard`, `gamepad`, `action`,
`storage`, `hud`, `config_ui`, `tester`, `wizard`, `binder`, plus the crossbar-port adapters
`gamedata`, `icons`, `mounts`, `skillchain` and the ported third-party subtree under
`crossbar/` (see [the subtree section](#crossbar-subtree-ported-third-party) below). An
addon-root module must **never** be named `resources`, `actions`, `lists`, `sets`, or `pack` —
those names would shadow Windower's shared libs on the addon search path.

## Global wiring rules

- **No `return true` suppression.** The Windower keyboard event cannot block keys FFXI acts on
  (verified in-game). Mapped keys are inert instead: the number row is dead by default; the
  `Ctrl`+number macro palette and `F9`–`F12` are `bind <key> xivgamepad noop`'d on load and
  unbound on unload (`F1`–`F8` untouched). Handlers only read. Native effects are produced
  actively (`send_command`, `setkey`).
- **Wall-clock timing.** All gesture thresholds/windows run on a schedule function
  (`coroutine.schedule` in production, stubbed in tests) — never prerender ticks, never
  `os.clock`. Prerender drives only the HUD's per-frame recast sweep (`hud.tick`).
- **Suspend flags live in main** (`xivgamepad.lua`): `test_mode`, `binder_mode`, `learn_mode`,
  `player_state.in_event`; `menu_open` / `chat_open` are read live from
  `windower.ffxi.get_info()`. Policy: `in_event` halts everything and hides the HUD; menu/chat
  suspend all gestures except the menu-nav synth actions (`menu_confirm`, `menu_cancel`,
  `menu_open`, `menu_focus`); `test_mode` routes gestures to the tester; `learn_mode` routes raw
  keys to the wizard; `binder_mode` routes button events to the binder. Frontends report into
  these via injected callbacks; they never own the flags.
- **Files-API path rule:** the Windower `files` library prefixes `windower.addon_path` itself —
  paths passed to `files.new`/`exists` are **addon-relative** (`data/debug.log`,
  `data/{Char}/shared.json`). Only `windower.create_dir` takes the absolute addon-anchored path
  (separators matched, never above `addon_path`).
- **Dependencies are injected** (texts/images libs, storage/action interfaces, settings
  accessors) so every module is testable without main; `log` is the only cross-module require —
  a leaf depending solely on `windower` + `files`.

## main — `xivgamepad/xivgamepad.lua`

Lifecycle (defer on load / idempotent `init` on login / logout hides + discards / unload restores
binds), command dispatch (`config c save s discard d help test t learn l debugmode dbg` + internal
`noop`), module wiring, `player_state` ownership
(`{ buffs = {id=true}, main_job, sub_job, is_mounted, in_event }` — status 4 = event, 85 =
mounted), buff/job/status/zone event handlers plus a ~1 s poll-and-diff reconciliation (dirty-flag
refresh; catches buffs already active at login/zone-in), runtime set-state persistence
(`active_set`/`current_mode` committed immediately; mirrored into staging while config is open),
wizard offer on `login` while `key_mapping_complete` is false, and the `host` table injected into
`action`. Public: `dispatch`, `dispatch_gesture(id, params)`, `init`, `on_button(name, pressed)`,
`on_load/on_logout/on_unload`, `on_mouse`, `print_help`, `refresh_hud`, `setup_open`,
`setup_close_save`, `setup_close_discard`, `cmd_test`, `cmd_learn(sub)`, `cmd_debugmode(arg)`.
Main also owns the RB-held set-selector overlay rule (issue #27): `on_button` recomputes
`hud.set_selector(...)` from `gamepad.is_held` (RB down, neither trigger down) on every RB/LT/RT
press and release, and the zone-change / cutscene reset paths recompute it after `gamepad.reset()`
so the overlay can never linger; `hud_opts` injects `gamepad.direct_switch_order()` for the
labels.

Crossbar wiring also lives here — main owns all Windower event registration for the adapters:
`init()` runs `gamedata.init` + `ensure_fresh` (once per session), `icons.init`,
`mounts.refresh()`, and `skillchain.init({ enabled = <skillchain_display getter> })` +
`on_login()`; incoming chunk `0x055` → `mounts.refresh()` and every chunk is forwarded to
`skillchain.on_incoming_chunk` (no initialized/suspend gate — passive observation); the `action`
event, job change, zone change, logout, and prerender forward into the skillchain adapter; unload
calls `icons.close()`. Main registers the `mount_roulette` system action
(`mounts.ride_random`, icon `mount`) at load. `setup_close_save` re-seeds the ported skillchain
lib (`skillchain.on_login()`) when a save flips `skillchain_display` false → true, because the
gated adapter skipped its player/buff seeding while disabled. Only ws/ja/pet bindings resolve a
skillchain highlight (`skillchain_prop`): the lookup key is `entry.id` + `entry.res_key` from
`gamedata.entry_for` — never `recast_key`, whose ja recast-slot ids would guarantee misses.

## input.keyboard

`configure(key_mapping)`, `set_callback(fn(button, pressed))` (edge events only),
`set_raw_callback(fn(dik, ctrl_down)|nil)` (learn mode, key-down edges), `on_key(dik, pressed)`
(registered on the `keyboard` event; collapses OS auto-repeat; never returns true),
`is_ctrl_down()`, `reset()`. Ctrl-gated buttons match at the key-down edge; a release maps to the
button its press resolved to.

## gamepad

`init({ schedule })`, `set_gestures(array)`, `migrate_gestures(array)` (renumbers saved
direct-switch entries still matching the pre-swap factory default to the current order; in-place,
idempotent, user-customized entries untouched — matches purely on value and is unconditional; main
is the one that gates whether it runs at all, via the `gestures_version` marker described in
`settings-schema.md`, so a deliberate post-swap customization that recreates the old factory
default byte-for-byte is never re-migrated once the save is at the current version),
`set_gesture_callback(fn(id, params))`,
`set_display_callback(fn(mode_or_nil))`, `on_button_event(name, pressed)`, `get_display_mode()`,
`is_held(name)` (true while the named button is down — main's set-selector visibility reads held
state through this, so `reset()` can never strand it), `direct_switch_order()` (a fresh copy of
the LIVE button array for sets 1–8, derived from the gestures array passed to the most recent
`set_gestures` call — reflects a player's rebind of a `direct_switch_N` gesture's button via the
config UI's Gestures tab, falling back to the shipped default for any position whose `rb_held`
`switch_set_N` entry was removed rather than rebound; the single source of the set-number mapping;
main injects it into the HUD so the selector overlay never keeps its own copy), `reset()`,
`default_gestures()` (the shipped array, used for settings defaults). Display enum:
`'xhb_l' | 'xhb_r' | 'wxhb_l' | 'wxhb_r' | 'expand_lt_rt' | 'expand_rt_lt'` (idle `nil`).
Slot positional order (frozen addon-wide): `DPAD_UP=1, DPAD_RIGHT=2, DPAD_DOWN=3, DPAD_LEFT=4,
A=5, B=6, X=7, Y=8`. Direct-switch deliberately does **not** share that order: `Y=1, B=2, A=3,
X=4, DPAD_UP=5, DPAD_RIGHT=6, DPAD_DOWN=7, DPAD_LEFT=8` — sets 1–4 on the face buttons, 5–8 on
the d-pad. Reserved dispatch is hard-wired: slot buttons under `trigger_held` fire `execute_slot
{ display_mode, slot }`, where an engaged WXHB/Expanded mode is authoritative for `display_mode`
and otherwise the half is resolved at press time from the most-recently-pressed currently-held
trigger (never from the lagging engaged display, which would misfire the stale half or drop
presses inside the hold-threshold window); LB/RB under `trigger_held` fire
`target_previous`/`target_next` immediately on the bumper press (no minimum trigger-hold time);
`open_binder` only dispatches while XHB-L/R is active; WXHB/Expanded require their anchor trigger
(LT for `*_l`/`lt_rt`, RT for `*_r`/`rt_lt`). Releasing one control of a stacked view falls back
to the surviving trigger's XHB.

## action

See [actions-and-binding-types.md](actions-and-binding-types.md). Public: `register_type(code,
def{execute[,describe]})`, `register_action(name, def{run[,icon,description]})`,
`register_overlay_type(name, def{check,is_available})`, `resolve_binding(slot, player_state)`,
`execute_binding(binding, ctx)`, `run_action(name_or_command, ctx, params)`, `set_host(host)`,
`get_action(name)`, `get_overlay_type(name)`, `list_actions()` (sorted
`{name, description, icon}`), `list_overlay_types()` (sorted names).

## storage

`load_shared(addon_path, char_name)` / `save_shared(...)` and `load_job` / `save_job` (job table
keyed by 3-letter abbreviation); `{}` when a file is missing. Sparse containers serialize as JSON
objects keyed by number strings; see
[settings-schema.md](settings-schema.md#hotbar-content-files-storagelua).

## log

`init(addon_path)` (repeat-safe), `debug(fmt, ...)` (no-op while disabled), `info`, `error`
(always chat; file too while debug on), `set_debug(bool)` (enabling truncates `data/debug.log`
and writes a session header), `toggle()` (returns the new state), `is_debug()`. `debug_enabled`
starts false every load and is never persisted. Lines carry `os.date` timestamps.

## hud

`init(opts)` (idempotent; opts: `settings`, `addon_path`, `texts`, `images`, `resolve_binding`,
`get_player_state`, `on_element_move(element_id, x, y)`, the optional
`direct_switch_order` (button array from `gamepad.direct_switch_order()` — numbers the
set-selector labels; absent, the selector shows unnumbered cluster art), and the optional
crossbar-port members
`gamedata`, `get_item_icon(item_id_or_name)`, `get_skillchain_prop(binding)`,
`get_skillchain_window()` — every optional opt degrades: without `gamedata` the
res-scan/type-icon paths apply, without `get_item_icon` item slots keep the generic type icon,
without the skillchain getters the highlight layer and `sc_timer` stay hidden), `show()`,
`hide()`,
`set_display(mode_or_nil)`, `set_selector(visible)` (RB-held set-selector overlay — issue #27;
main owns the visibility rule: RB down and neither trigger down, recomputed on every RB/LT/RT
press AND release and after gamepad resets; the flag is ephemeral, cleared by every re-init,
never persisted), `refresh(view)`, `tick()` (prerender; recast sweeps, per-slot
skillchain highlights, and the `sc_timer` text), `set_draggable
(bool)`, `on_mouse(mtype, x, y, delta)` (drag + tooltips; returns true only while consuming a
drag), `destroy()`. View model: `{ active_set, set_name, mode, display_mode, slots = { [1..16] =
resolved binding or nil } }`; slots still carrying `overlays` are re-resolved through the injected
resolver. Elements: `half_left`, `half_right`, `label`, `sc_timer`, `set_selector`; positions
persist under
`hud_positions[element_id]` (staged by main). The `sc_timer` shows `Wait n.n` (red) while
resonance is set but the chain delay has not elapsed and `Go! n.n` (green) while the window is
open, hiding otherwise; each slot carries a skillchain highlight layer whose icon is
`images/icons/iconpacks/default/skillchain/<prop lowercase>.png` (fallbacks: radiance →
`light.png`, umbra → `darkness.png`), resolved per tick through `get_skillchain_prop`. The
`set_selector` element renders the d-pad and face-button cluster art
(`iconpacks/default/ui/dpad_xbox.png` / `facebuttons_xbox.png`) with one set-number label per
button from the injected `direct_switch_order` and the active set's label (from
`view.active_set`) highlighted green.

## config_ui

`init(opts)` (opts: `texts`, `images`, `on_save`, `on_discard`, `launch_wizard`,
`get_staged`/`get_live`, and an `on_change(key, value)` mutation sink — staging stays in main),
`open(staged)`, `close()`, `is_open()`, `destroy()`, `build_tabs(staged)` (pure/testable),
`on_mouse(...)` — delegates **unconditionally** to `gui:handle_mouse` (echo pattern). Tabs: Sets /
Display / Keys / Gestures, rendered as clickable rows; every mutation flows through a named public
function (`cycle_set_source`, `toggle_skip_cycle`, `cycle_display_set`, `toggle_display_half`,
`adjust_transparency`, `toggle_hide_empty_slots`, `request_capture`, `add_gesture`,
`add_gesture_template`, `remove_gesture`, `cycle_gesture_field`, `adjust_gesture_timing`,
`update_gesture`, `set_set_name`, `stage_window_pos`) and hands whole deep-copied sub-tables to
`on_change` under their top-level settings key.

## tester

`init(opts)`, `open()`, `close()`, `is_open()`, `destroy()`, `on_button_event(name, pressed)`
(live grid), `on_gesture(id, params)` (bounded 10-line log). Plain texts overlay — not config_gui.

## wizard

`start(opts)` (opts: `current_mapping`, `on_finish(new_mapping)`, `on_cancel`, ui deps),
`on_raw_key(dik, ctrl_down[, pressed])` (fed from `keyboard.set_raw_callback`; the optional third
argument is a contract-consistent addition — down-only callers omit it), `skip()`, `back()`,
`cancel()`, `is_active()` — skip/back/cancel are driven by `//xg learn skip|back|cancel`. Capture
order: `LT, RT, LB, RB, BACK, START, A, B, X, Y, DPAD_UP, DPAD_RIGHT, DPAD_DOWN, DPAD_LEFT`
(required), then skippable `L4, L5, R4, R5, TRACKPAD_1..8`. Skip keeps the pre-loaded key. D-pad
steps require a this-session-captured LT/RT/RB code currently down. Collisions are rejected naming
the owning button. Finish → `on_finish(staged)` (main commits + sets `key_mapping_complete`);
cancel leaves the prior mapping intact (main's first-run dismissal additionally sets the
no-repeat-nag flag).

## binder

`init(opts)` — required: `action` (uses `list_overlay_types`/`get_overlay_type`),
`get_set(position)` → working-set table, `save_set(position, set)`, `get_player_state`, `texts`,
`images`; optional: `on_close` (main clears `binder_mode` here), `ct_presets`
(`{ label, command }` array; defaults to Rest/Sit/Check/Lock On), `get_mounts` (owned-mount
display names — the mount menu then lists these plus a final `'Mount Roulette'` entry writing the
binding `{ type = 'mount', action = 'Mount Roulette' }`; absent, every `res.mounts` entry is
offered), and `gamedata` (drives the job-ability category sub-menus from
`categories('job_abilities')` / `list('job_abilities', category)`; pet-type entries — blood
pacts, BST Ready moves reclassified via `res.job_abilities`, pet commands — are filtered out of
the `ja` flow because they belong to the `pet` binding type). `toggle(ctx)` (ctx:
`active_set`, `display_mode`, `mode`; `'xhb_r'` targets slots 9–16, anything else the left half),
`close()`, `is_open()`, `on_button(name, pressed)` (routed by main while `binder_mode`; navigation
pauses while no trigger is held). Remove/Swap write immediately; bind/Replace/Overlay flows write
on the final Confirm (Replace writes a fresh binding, dropping base + overlays); Reorder commits
on the drop-A and discards on B-while-grabbed. The subjob overlay captures the player's current
subjob; overlay flows additionally offer the `noop` type (confirms directly, no action/target
step).

## gamedata (crossbar adapter)

Generated-resources pipeline and lookup surface over the ported `crossbar/resource_generator`.
`init(addon_path)`, `ensure_fresh()` (idempotent per session; creates `data/generated/`,
regenerates on MD5 mismatch against Windower's res sources, falls back to a full regeneration if
a "current" file fails to load, and serves empty tables — logged once — when generation itself
fails), `spell(name)`, `ability(name)`, `entry_for(binding)` (`ma` → spells; `ja`/`ws`/`pet` →
abilities; any other type → nil), `icon_for(binding)`, `recast_key(binding)` →
`(recast_id or id, res_key)`, `categories(res_key)`, `list(res_key, category)` (entries sorted by
`en`). `icon_for` resolution order: `binding.icon` → iconpack `custom_icon` (existence-checked
via `files.exists`, hits **and misses** cached per session) → `default_icon` → nil; returned
paths are addon-relative **without** a leading slash (generator output carries one — normalized
away). Generated files `data/generated/crossbar_{spells,abilities}.lua` are loaded via
`files.read` + `loadstring` inside `pcall`, **never `require`** — regeneration must not be served
a stale cached module, and tests must stay on the in-memory fs. MD5 freshness reads Windower's
res sources via `files.new('../../res/spells.lua')` (and `job_abilities.lua` /
`weapon_skills.lua`) — a **documented read-only walk-up exception**; the
never-walk-above-`addon_path` rule governs directory creation and writes, not these reads.
Lookups are keyed by kebab-cased display name (`kebab_casify` is idempotent, so both forms hit);
the `*.lua.md5` metadata entries are strings and can never leak out as entries.

## icons (crossbar adapter)

Runtime item-icon extraction over the ported `crossbar/icon_extractor` (which owns all raw `io` —
see the carve-out below). `init(addon_path)`, `item_icon(item_id_or_en_name)` → addon-relative
path or nil, `close()`. Extracted 32x32 BMPs are cached at `data/icons/items/{item_id}.bmp`
(id-keyed; names resolve through `res.items`, memoized including misses). Any failure — missing
DAT, non-Windows env, unresolvable name — returns nil with **one `log.debug` per item per
session**; `item_icon` never raises into a render path. The extractor is handed an **absolute**
output path (raw io does not resolve addon-relative paths). Main injects
`get_item_icon = icons.item_icon` into the HUD opts: item bindings never appear in the generated
resources, so the extractor is the only real-art source for item slots — the HUD resolves them
lazily from `render_slot` (never from `tick()`; the adapter's per-item memoization keeps
refreshes cheap) and falls back to the iconpack `item.png` only when extraction fails.

## mounts (crossbar adapter)

Owned-mount tracking and roulette over the ported `crossbar/mountroulette`. `refresh()`
(rederives owned mounts from Mounts-category key items), `list()` (sorted display-name array;
names come from `res.mounts`, never a hardcoded map), `ride_random()` (dismounts if mounted, else
mounts a random owned mount), `has_mounts()`. No event registration here: main wires incoming
chunk `0x055` → `refresh()` and also calls it from `init()`. Every entry point no-ops safely
while logged out.

## skillchain (crossbar adapter)

Thin gate in front of the ported resonance state machine (`crossbar/skillchain/skillchains.lua`);
main forwards all events. `init({ enabled = getter })` (injected `skillchain_display` getter),
`on_action(act)` (the **raw** `action` event table — the ported handler wraps it itself),
`on_incoming_chunk(id, data)`, `on_job_change(job_abbrev)`, `on_zone_change()`, `on_login()`
(seeds player identity and buffs), `on_logout()`, `tick()` (prerender), `prop_for(id, res_key)` →
skillchain property name or nil (nil unless the ability would continue the active chain on the
current target inside the open window), `window()` → `(remaining_delay, remaining_window)`.
While disabled — or before init, or with no player — every handler no-ops and every query returns
nil; `on_logout`/`on_zone_change` are pure state clears gated only on `enabled` (at logout the
player is already gone). The WS/JA property data (`skills.lua`) is © 2017 — later additions never
resolve.

## crossbar/ subtree (ported third-party)

Ported third-party files live under `xivgamepad/crossbar/` with their BSD-3/MIT license headers
retained **verbatim** (summarized in
[`xivgamepad/LICENSES-THIRD-PARTY.md`](../../../xivgamepad/LICENSES-THIRD-PARTY.md)), plus a
`-- PORT:` comment block directly under the retained header enumerating **every** edit made to
the file. Only these edit categories are allowed:

1. require-path fixes
2. event-registration extraction (the file exposes handlers; main registers events)
3. output/input path redirection (runtime files under `data/`)
4. Lua 5.1 parse fixes (e.g. parenthesizing string-literal method calls)
5. global hygiene (localize accidental globals)

The subtree is exempt from the monorepo style/convention audits; everything conventional lives in
the four adapters above. Require names:

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

### io carve-out

> `xivgamepad/crossbar/icon_extractor.lua` is the single reviewed exception to the no-io rule. The
> Windower files API can neither read an arbitrary absolute path (the FFXI install under
> `windower.ffxi_path`) nor perform binary seeks into ROM DAT files. This file uses `io.open`
> read-only against the game's ROM DATs and write-only to produce 32x32 BMP files under
> `xivgamepad/data/icons/`. No other addon file may use or require `io`.
