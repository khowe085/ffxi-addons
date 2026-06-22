# Echo

Echo displays a user-provided string in a persistent, draggable on-screen text overlay. The text is set via command and its position is configured through the standard `config`/`save`/`discard` GUI flow, with both the text and position persisted per character. Echo is the reference implementation of the shared `lib/settings/config_gui` configuration window.

## Installation

1. Copy the `echo` folder into your Windower `addons/` directory.
2. Load the addon in-game:
   ```
   //lua load echo
   ```
3. To reload after changes:
   ```
   //lua reload echo
   //lua r echo
   ```

## Commands

All commands use the alias `ec` (or the full name `echo`).

| Command            | Description                                                                                          |
|--------------------|------------------------------------------------------------------------------------------------------|
| `//ec set <text>`              | Set and display the text. Saved immediately; if config is open, staged until save. Multi-word text is supported. With no text, prints the command list. |
| `//ec clear`                   | Clear the displayed text.                                                                             |
| `//ec config` / `//ec c`       | Open the configuration window (header, body, Save/Discard footer); the overlay becomes draggable. A no-op if the window is already open. |
| `//ec save` / `//ec s`         | Save staged changes and close config — same as clicking **Save**.                                     |
| `//ec discard` / `//ec d`      | Discard staged changes and close config — same as clicking **Discard**.                               |
| `//ec help`                    | Print the command list in chat.                                                                       |

## Configuration GUI

`//ec config` opens a configuration window (built on `lib/settings/config_gui`) with a visually
distinct **Echo** header band, a body showing the current `text` / `pos_x` / `pos_y` and a
positioning hint, and a distinct footer band holding button-styled **Save** and **Discard** hit
targets. While it is open:

- Drag the on-screen **text overlay** to reposition it — `pos_x`/`pos_y` update when you release the mouse.
- Drag the **window header** to move the config window itself — its anchor (`config_x`/`config_y`) is saved. Only the header drags the window; the body is not draggable.
- If the text is empty when you open config, it is shown as `SAMPLE TEXT` so there is always something to position.
- Clicks anywhere on the window are captured and never pass through to the game.
- **Save** (or `//ec save`) commits the staged changes; **Discard** (or `//ec discard`) reverts them. Both close the window.

## Libraries

- `lib/settings` — per-character settings (load/stage/save/discard)
- `lib/settings/config_gui` — reusable configuration-window chrome
- `texts` — on-screen text overlay and window text elements
- `images` — solid backdrop for the configuration window

## Configuration

Settings are stored per character at `data/{CharacterName}/settings.json` and managed through `lib/settings`.

| Key        | Type   | Description                                          |
|------------|--------|------------------------------------------------------|
| `text`     | string | The displayed message.                               |
| `pos_x`    | number | On-screen X position of the text overlay.            |
| `pos_y`    | number | On-screen Y position of the text overlay.            |
| `config_x` | number | X position of the configuration window.              |
| `config_y` | number | Y position of the configuration window.              |

Overlay position is changed by dragging the overlay during `//ec config` and the window position by
dragging the window header; both are persisted only on `//ec save`. `//ec discard` reverts to the
pre-config values. The `text` value set with `//ec set` is persisted immediately when not in config.

Settings are scoped per character and follow the login lifecycle: Echo can be loaded before you log in (it simply waits), reloads the correct character's text and position each time you log in or switch characters, and hides the overlay at the character-select screen.
