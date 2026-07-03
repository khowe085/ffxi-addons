# XIVGamepad — Module Contracts (contributor reference)

Frozen shapes originate in `.planning/xivgamepad-contracts.md`; this page reflects the code as
shipped. Every module returns its module table; `_`-prefixed functions are test-only accessors.
Require names: `xivgamepad.log`, `xivgamepad.input.keyboard`, `xivgamepad.gamepad`,
`xivgamepad.action`, `xivgamepad.storage`, `xivgamepad.hud`, `xivgamepad.config_ui`,
`xivgamepad.tester`, `xivgamepad.wizard`, `xivgamepad.binder`.

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

## input.keyboard

`configure(key_mapping)`, `set_callback(fn(button, pressed))` (edge events only),
`set_raw_callback(fn(dik, ctrl_down)|nil)` (learn mode, key-down edges), `on_key(dik, pressed)`
(registered on the `keyboard` event; collapses OS auto-repeat; never returns true),
`is_ctrl_down()`, `reset()`. Ctrl-gated buttons match at the key-down edge; a release maps to the
button its press resolved to.

## gamepad

`init({ schedule })`, `set_gestures(array)`, `set_gesture_callback(fn(id, params))`,
`set_display_callback(fn(mode_or_nil))`, `on_button_event(name, pressed)`, `get_display_mode()`,
`reset()`, `default_gestures()` (the shipped array, used for settings defaults). Display enum:
`'xhb_l' | 'xhb_r' | 'wxhb_l' | 'wxhb_r' | 'expand_lt_rt' | 'expand_rt_lt'` (idle `nil`).
Positional order (frozen addon-wide): `DPAD_UP=1, DPAD_RIGHT=2, DPAD_DOWN=3, DPAD_LEFT=4, A=5,
B=6, X=7, Y=8`; direct-switch uses the same order for set positions. Reserved dispatch is
hard-wired: slot buttons under `trigger_held` fire `execute_slot
{ display_mode, slot }`; LB/RB under `trigger_held` fire `target_previous`/`target_next`;
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
`get_player_state`, `on_element_move(element_id, x, y)`), `show()`, `hide()`,
`set_display(mode_or_nil)`, `refresh(view)`, `tick()` (prerender; recast sweeps), `set_draggable
(bool)`, `on_mouse(mtype, x, y, delta)` (drag + tooltips; returns true only while consuming a
drag), `destroy()`. View model: `{ active_set, set_name, mode, display_mode, slots = { [1..16] =
resolved binding or nil } }`; slots still carrying `overlays` are re-resolved through the injected
resolver. Elements: `half_left`, `half_right`, `label`; positions persist under
`hud_positions[element_id]` (staged by main).

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
`images`; optional: `on_close` (main clears `binder_mode` here) and `ct_presets`
(`{ label, command }` array; defaults to Rest/Sit/Check/Lock On). `toggle(ctx)` (ctx:
`active_set`, `display_mode`, `mode`; `'xhb_r'` targets slots 9–16, anything else the left half),
`close()`, `is_open()`, `on_button(name, pressed)` (routed by main while `binder_mode`; navigation
pauses while no trigger is held). Remove/Swap write immediately; bind/Replace/Overlay flows write
on the final Confirm (Replace writes a fresh binding, dropping base + overlays); Reorder commits
on the drop-A and discards on B-while-grabbed. The subjob overlay captures the player's current
subjob; overlay flows additionally offer the `noop` type (confirms directly, no action/target
step).
