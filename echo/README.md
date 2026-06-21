# Echo

Echo displays a user-provided string in a persistent, draggable on-screen text overlay. The text is set via command and its position is configured through the standard `config`/`save`/`discard` GUI flow, with both the text and position persisted per character.

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
| `//ec config` / `//ec c`       | Open the positioning GUI; the overlay becomes draggable.                                              |
| `//ec save` / `//ec s`         | Save staged position changes and close config.                                                        |
| `//ec discard` / `//ec d`      | Discard staged position changes and close config.                                                     |
| `//ec help`                    | Print the command list in chat.                                                                       |

## Libraries

- `lib/settings`

## Configuration

Settings are stored per character at `data/{CharacterName}/settings.json` and managed through `lib/settings`.

| Key     | Type   | Description                                  |
|---------|--------|----------------------------------------------|
| `text`  | string | The displayed message.                       |
| `pos_x` | number | On-screen X position of the overlay.         |
| `pos_y` | number | On-screen Y position of the overlay.         |

Position is changed by dragging the overlay during `//ec config` and is only persisted on `//ec save`; `//ec discard` reverts to the pre-config position. The `text` value set with `//ec set` is persisted immediately when not in config.

Settings are scoped per character and follow the login lifecycle: Echo can be loaded before you log in (it simply waits), reloads the correct character's text and position each time you log in or switch characters, and hides the overlay at the character-select screen.
