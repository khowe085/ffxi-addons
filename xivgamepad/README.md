# XIVGamepad

XIVGamepad brings the Final Fantasy XIV cross hotbar experience to FFXI. Hold LT or RT to display an
eight-slot half of the active hotbar set, then press a d-pad direction or face button to fire that
slot. Every gesture is hold-only and resolved inside the addon from keyboard keys emitted by a
hybrid Steam Input profile — analog movement, the camera, and no-trigger d-pad targeting stay
native gamepad. Player documentation, including the required controller setup, lives in the wiki at
[docs/xivgamepad/wiki](../docs/xivgamepad/wiki/Home.md).

## Installation

1. Copy the `xivgamepad` folder (and the shared `lib` folder) into your Windower `addons/`
   directory.
2. Load the addon in-game:
   ```
   //lua load xivgamepad
   ```
3. To reload after changes:
   ```
   //lua reload xivgamepad
   //lua r xivgamepad
   ```
4. The addon is unusable without its controller setup: a Steam Input profile plus FFXI's own
   gamepad configuration. Follow the wiki's
   [Installation and Setup](../docs/xivgamepad/wiki/Installation-and-Setup.md) page before first
   use. On first login the Key-Capture Wizard opens to confirm the key mapping.

## Commands

All commands use the alias `xg` (or the full name `xivgamepad`).

| Command                          | Description                                                                                              |
|----------------------------------|----------------------------------------------------------------------------------------------------------|
| `//xg config` / `//xg c`         | Open the configuration window (Sets / Display / Keys / Gestures tabs); the HUD becomes draggable. A no-op if the window is already open. |
| `//xg save` / `//xg s`           | Save staged changes and close config — same as clicking **Save**.                                        |
| `//xg discard` / `//xg d`        | Discard staged changes and close config — same as clicking **Discard**.                                  |
| `//xg test` / `//xg t`           | Toggle the Gamepad Tester overlay: a live virtual-button grid and gesture log. While open, gestures are shown instead of executed. |
| `//xg learn` / `//xg l`          | Open the Key-Capture Wizard (auto-opens on first login until the mapping is confirmed).                  |
| `//xg learn skip`                | Wizard: skip the current optional button, keeping its current key. Required buttons cannot be skipped.   |
| `//xg learn back`                | Wizard: step back one button and re-capture it (its previous key is restored first).                     |
| `//xg learn cancel`              | Wizard: close without applying this session's captures. Cancelling the first-run wizard accepts the shipped mapping and stops the auto-open. |
| `//xg debugmode` / `//xg dbg`    | Toggle debug logging to chat and `data/debug.log`. `debugmode on` / `debugmode off` set it explicitly. Always off after a reload. |
| `//xg help`                      | Print the command list in chat.                                                                          |

An internal `noop` sub-command exists solely as the silent target of the load-time key
neutralization binds; it is not a player command. Unknown commands print the help list.

## Configuration GUI

`//xg config` opens a configuration window (built on `lib/settings/config_gui`) with four tabs:
**Sets** (name, shared/job source, and skip-cycle flag for the 8 set positions), **Display** (set
and half assigned to each WXHB/Expanded view, hide-empty-slots, transparency), **Keys** (the
captured key for every virtual button, plus a Capture / Re-learn control that launches the
Key-Capture Wizard), and **Gestures** (add, edit, remove, and time-tune gesture definitions). Rows
are edited by clicking directly on their values. While the window is open every HUD element is
draggable; all changes are staged and only written on **Save** (**Discard** reverts them, including
HUD positions). Slot bindings are assigned in-game with the Binder, not in this window. See the
wiki's [Configuration](../docs/xivgamepad/wiki/Configuration.md) page for details.

## Libraries

- `lib/settings` — per-character settings (load/stage/save/discard)
- `lib/settings/config_gui` — reusable configuration-window chrome
- `texts` — HUD labels, tooltips, badges, and the tester/wizard/binder overlays
- `images` — HUD slot icons, recast sweeps, and window backdrops
- `files` — hotbar content (`shared.json` / `job.json`) and `data/debug.log` I/O
- `resources` — spell/ability/item/mount lists for the Binder and recast lookups

## Configuration

Addon settings are stored per character at `data/{CharacterName}/settings.json` and managed through
`lib/settings`. Hotbar **content** (slot bindings and overlays) is stored separately in
`data/{CharacterName}/shared.json` and `data/{CharacterName}/job.json` (keyed by main-job
abbreviation) and is written by the Binder. Key settings:

| Key                       | Type    | Description                                                              |
|---------------------------|---------|--------------------------------------------------------------------------|
| `current_mode`            | string  | Active cycling pool: `job` or `shared`.                                  |
| `active_set`              | number  | The set position (1–8) the XHB currently shows.                          |
| `key_mapping`             | table   | Virtual button → keyboard key code (+ optional Ctrl flag).               |
| `key_mapping_complete`    | boolean | First-run flag; while false the Key-Capture Wizard opens on login.       |
| `sets`                    | table   | Per-position metadata: `name`, `source` (`job`/`shared`), `skip_cycle`.  |
| `display`                 | table   | Set + half assigned to each WXHB/Expanded view.                          |
| `hide_empty_slots`        | boolean | Hide empty slot frames on the HUD.                                       |
| `transparency_standard`   | number  | HUD transparency (0–100) when no view is active.                         |
| `transparency_active`     | number  | Transparency of the displayed half while a view is active.               |
| `transparency_inactive`   | number  | Transparency of the other half while a view is active (default 100).    |
| `gestures`                | table   | The data-driven gesture list (edited in the Gestures tab).               |
| `hud_positions`           | table   | Dragged positions of the HUD elements.                                   |
| `config_x` / `config_y`   | number  | Position of the configuration window.                                    |

The full schema, including the default key mapping and gesture entries, is documented in
[docs/xivgamepad/reference/settings-schema.md](../docs/xivgamepad/reference/settings-schema.md);
player-facing documentation is in the [wiki](../docs/xivgamepad/wiki/Home.md).

Settings are scoped per character and follow the login lifecycle: XIVGamepad can be loaded before
you log in (it waits), reloads the correct character's settings and hotbars on every login or
character switch, and hides the HUD at the character-select screen.

## Credits

The crossbar feature set (`crossbar/`, `images/icons/`) is ported from the
[xivcrossbar](https://github.com/AliekberFFXI/xivcrossbar) lineage. Full per-file attribution and
license texts live in [LICENSES-THIRD-PARTY.md](LICENSES-THIRD-PARTY.md).

- **Ivaar** — SkillChains library: skillchain resonance tracking and WS/JA property data.
- **Dean James (Xurion of Bismarck)** — Mount Roulette: the random-mount logic.
- **Rubenator** and **Trv** — icon extractor: item-icon extraction from the FFXI DATs (base
  extraction code by Trv).
- **Aliekber (AliekberFFXI)** — xivcrossbar: the resource generator, the default icon-pack art,
  and the extracted icon set shipped in `images/icons/`.
- **SirEdeonX** — XIVHotbar, the addon lineage xivcrossbar derives from.
- **kikito (Enrique García Cota)** — md5.lua, used for generated-resource freshness checks.
