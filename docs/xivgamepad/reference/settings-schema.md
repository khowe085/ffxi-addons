# XIVGamepad — Settings & Storage Schema (contributor reference)

Addon config lives in `data/{CharacterName}/settings.json`, managed exclusively through
`lib/settings` (staged in the config GUI, committed on save). Hotbar **content** lives in
`data/{CharacterName}/shared.json` / `job.json`, written directly by `storage.lua` via the
Windower `files` API. Player-facing docs: [../wiki/Home.md](../wiki/Home.md).

## Top-level settings keys (defaults)

| Key | Default | Notes |
|---|---|---|
| `config_x` / `config_y` | `100` / `100` | Config-window anchor. |
| `current_mode` | `'job'` | Cycling pool: `'job'` or `'shared'`. |
| `active_set` | `1` | Set position 1–8 the XHB shows. Runtime changes are committed immediately (mirrored into staging while a config session is open). |
| `key_mapping_complete` | `false` | First-run flag; while false the wizard auto-opens on login. Set true by finishing the wizard or dismissing the first-run offer. |
| `key_mapping` | table below | Virtual button → key entry. |
| `sets` | table below | Position metadata only (content lives in storage files). |
| `display` | table below | Set + half per non-XHB view. |
| `always_show_wxhb` | `false` | Global toggle: when true, each screen half not currently the live gesture-engaged half shows its assigned `wxhb_l`/`wxhb_r` view's content (if one is assigned there) at `transparency_standard`, instead of the idle `active_set` fallback / `transparency_inactive`. WXHB only — `expand_lt_rt`/`expand_rt_lt` are unaffected. Display-only: does not change when a slot actually fires (`gamepad.lua`'s hold gesture is unaffected). |
| `hide_empty_slots` | `false` | HUD hides empty slot frames (positions reserved). |
| `transparency_standard` | `0` | 0 = opaque … 100 = invisible; alpha = round((100 − t) × 255 / 100). |
| `transparency_active` | `0` | Displayed half while a view is active. |
| `transparency_inactive` | `100` | Other half while a view is active. |
| `gestures` | `gamepad.default_gestures()` | Data-driven gesture array, schema below. |
| `gestures_version` | `0` | Migration marker (issue #30 follow-up). A save is renumbered by `gamepad.migrate_gestures` (direct-switch entries still matching the pre-swap factory default) only while this is below the current value `2`; main bumps it to `2` in memory once migrated (persisted on the next natural save). A save already at `2` is trusted as-is, so a deliberate post-swap customization that recreates the old factory default byte-for-byte is never re-migrated. `0` covers both a pre-marker save (key absent — `lib/settings.load` only fills in missing keys) and a brand-new install (already in the current order, so migrating is a harmless no-op). |
| `hud_positions` | `{}` | `hud_positions[element_id] = { x, y }`; element ids `half_left`, `half_right`, `label`, `sc_timer`, `set_selector` (the RB-held set-selector overlay). Unset elements use the HUD's built-in defaults (`180,520` / `460,520` / `180,494` / `180,470` / `500,300`). |
| `skillchain_display` | `true` | Skillchain HUD display: the `sc_timer` element and per-slot chain highlights. Toggled from the Display tab; the injected getter gates the skillchain adapter, and a false → true save re-seeds the ported lib. |

### `sets` default

Eight entries `{ name, source, skip_cycle }`: positions 1–5 `source='job'`, 6–8 `source='shared'`;
`skip_cycle` true for positions 3, 4, 5, 7; names `'Set 1'` … `'Set 8'`.

### `display` default

```lua
display = {
  wxhb_l       = { set = 2, half = 'left'  },
  wxhb_r       = { set = 2, half = 'right' },
  expand_lt_rt = { set = 4, half = 'right' },
  expand_rt_lt = { set = 4, half = 'right' },
}
```

## `key_mapping`

```lua
key_mapping[button_name] = { code = <DIK number>, ctrl = <bool, omitted = false> }
```

Virtual button names (exact strings): `LT RT LB RB A B X Y DPAD_UP DPAD_RIGHT DPAD_DOWN DPAD_LEFT
BACK START L4 L5 R4 R5 TRACKPAD_1 .. TRACKPAD_8`. Ctrl itself (DIK 29 LCTRL / 157 RCTRL) is
tracked inside the keyboard module and is never a virtual button. A key's release maps to whatever
button its press resolved to, so a Ctrl release mid-hold cannot strand a pressed button.

Default mapping (DirectInput key codes; what the recommended Steam profile emits):

| Button | Key | `code` | `ctrl` |
|---|---|---|---|
| LT / RT | `1` / `2` | 2 / 3 | |
| LB / RB | `3` / `4` | 4 / 5 | |
| A / B / X / Y | `5` / `6` / `7` / `8` | 6 / 7 / 8 / 9 | |
| DPAD_UP / DPAD_RIGHT | `9` / `0` | 10 / 11 | |
| DPAD_DOWN / DPAD_LEFT | `` ` `` / `=` | 41 / 13 | |
| BACK / START | Ctrl+`1` / Ctrl+`2` | 2 / 3 | true |
| TRACKPAD_1..8 | Ctrl+`3` … Ctrl+`0` | 4–11 | true |
| L4 / L5 / R4 / R5 | F9 / F10 / F11 / F12 | 67 / 68 / 87 / 88 | |

## `gestures` array

Each entry:

```lua
{ id = 'auto_run', type = 'tap', button = 'LB', context = 'bare', action = 'auto_run',
  params = { max_hold = 0.25 } }
```

- `id` — unique string; the config UI rejects duplicate ids.
- `context` — `'bare'` (no modifier) | `'trigger_held'` (LT or RT) | `'rb_held'` | `'lb_held'`.
- `action` — a registered system-action name (see
  [actions-and-binding-types.md](actions-and-binding-types.md)); any unrecognized string is
  executed as a raw Windower command (escape hatch).
- `type` + timing params (defaults):

| Type | Params (defaults) | Semantics |
|---|---|---|
| `button` | none | Fires once on key-down; no repeat while held. |
| `tap` | `max_hold = 0.25` | Fires on release if held no longer than `max_hold` and the press was not consumed as a modifier. |
| `hold` | `min_hold = 0.12` | Engages after `min_hold`; stays engaged until release. |
| `double_tap` | `max_gap = 0.33`, `min_hold = 0.12` | Second press within `max_gap` of the first release, held `min_hold`. |
| `hold_then_hold` | `min_hold_first = 0.12`, `min_hold_second = 0.12` | Anchor held `min_hold_first`, second button held `min_hold_second`. |
| `hold_then_press` | `min_anchor_hold = 0.12` | Press accepted once the context anchor has been held `min_anchor_hold`. |

Default gesture ids: `xhb_l, xhb_r, wxhb_l_paddle, wxhb_r_paddle, wxhb_l_tap, wxhb_r_tap,
expand_lt_rt, expand_rt_lt, auto_run, cycle_set, mode_switch, target_previous, target_next,
direct_switch_1..direct_switch_8, execute_slot, open_binder, bare_a, bare_b, bare_x, bare_y,
bare_start, bare_back`.

Reserved `(button × context)` pairs are hard-wired in the gamepad module and cannot be rebound by
gesture entries: face/d-pad under `trigger_held` is always `execute_slot`, and LB/RB under
`trigger_held` are always `target_previous` / `target_next`, firing immediately on the bumper
press (their entries' timing params are not consumed). The XHB `hold` entries on LT/RT only tune
`min_hold`.

## Hotbar content files (`storage.lua`)

- `data/{CharacterName}/shared.json` — sets table.
- `data/{CharacterName}/job.json` — `{ [job_abbrev] = sets table }` (3-letter uppercase, e.g.
  `"SCH"`).

`sets[position 1..8] = { slots = { [1..16] = <slot binding> or nil } }`. **Sparse containers
(positions, slots) are encoded as JSON objects keyed by number strings** (`"1"`..`"16"`), decoded
back to numeric-keyed Lua tables — JSON arrays cannot hold holes. Dense arrays (`overlays`) are
encoded as JSON arrays.

Slot binding fields: `type, action, target, alias, icon, equip_slot, warmup, cooldown, usable`,
plus an ordered `overlays` array. Overlay entry:
`{ overlay_type = <name>, condition = <table>, <binding fields that replace the base> }`.
A resolved binding may additionally carry `count` (HUD badge, supplied by the data) — see
[actions-and-binding-types.md](actions-and-binding-types.md) for type/overlay semantics.

Directory creation mirrors the lib/settings contract: `windower.create_dir` with the **absolute**
addon-anchored path (separators matched to `addon_path`, never walking above it); all `files` API
paths are **addon-relative**. Windower `files` API only — no `io.*`, no `os.execute`/`io.popen`
(sole reviewed exception: `crossbar/icon_extractor.lua`, see
[module-contracts.md](module-contracts.md#io-carve-out)).

## Generated and cached data files (character-independent)

Two regenerable caches live directly under `data/` — both are always safe to delete:

- `data/generated/crossbar_spells.lua` and `data/generated/crossbar_abilities.lua` — Lua sources
  (`return { ... }`) written by the ported resource generator and loaded by the `gamedata`
  adapter via `files.read` + `loadstring` (never `require`). Regenerated whenever the embedded
  MD5 metadata no longer matches Windower's own `res/spells.lua` / `res/job_abilities.lua` /
  `res/weapon_skills.lua`.
- `data/icons/items/{item_id}.bmp` — 32x32 item icons extracted from the game DATs by the `icons`
  adapter, written lazily at render time — the first time an item binding is displayed on the
  HUD. On extraction failure (non-standard install, missing DATs) nothing is written and the HUD
  keeps the generic item art.

### Generated-entry schema

Both files map **kebab-cased English names** to entry tables, alongside string-valued MD5
metadata keys (`["spells.lua.md5"]` in the spells file; `["job_abilities.lua.md5"]` and
`["weapon_skills.lua.md5"]` in the abilities file):

| Field | spells | job abilities | weapon skills |
|---|---|---|---|
| `id` | spell id | ability id | ws id |
| `en` | English name | English name | English name |
| `res_key` | `"spells"` | `"job_abilities"` | `"weapon_skills"` |
| `type` | `"ma"` | `"ja"` or `"pet"` | `"ws"` |
| `skill` | magic skill name | — | — |
| `recast_id` | recast timer id | recast timer id | — (absent) |
| `category` | spell category | kebab-cased category (`abilities`, `phantom-rolls`, `blood-pacts/rage`, …) | weapon-skill skill name |
| `element` | element name | element name | element name |
| `default_icon` | `/images/icons/spells/NNNNN.png` | `/images/icons/abilities/NNNNN[.JJ].png` | `/images/icons/weapons/<skill>.png` |
| `custom_icon` | `<category>/<key>.png` (iconpack-relative) | `<category>/<key>.png` | `weaponskills/<category>/<key>.png` |
| `mp_cost` / `tp_cost` | mp / 0 | 0 / tp | 0 / 1000 |

`default_icon` values carry a leading slash in the generated file; `gamedata.icon_for` normalizes
it away and returns addon-relative paths.
