# windower-addons

A collection of Lua addons for **Final Fantasy XI** running on the [Windower 4](https://www.windower.net/) framework.

## Repository layout

```
lib/
  settings/       # Shared settings library used by all addons

<addon-name>/     # One directory per addon
  README.md       # Addon-specific docs and command reference

tests/
  lib/            # Tests for shared libraries
  <addon-name>/   # Tests for each addon
```

## Addons

| Addon | Description |
|-------|-------------|
| [echo](echo/) | Displays a user-provided string in a persistent, draggable on-screen text overlay; alias `ec`. Reference implementation of the shared config GUI. |

<!-- Add a row here whenever a new addon is created -->

## Shared Libraries

### `lib/settings`

Handles per-character configuration (load, stage, save, discard) for all addons. See [lib/settings/CLAUDE.md](lib/settings/CLAUDE.md) for the API.

### `lib/settings/config_gui`

Reusable configuration-window chrome (header, tabs, scrollable body, Save/Discard footer, dragging, click-blocking) so each addon only supplies its body content. See [lib/settings/CLAUDE.md](lib/settings/CLAUDE.md) for the API.

## Installation

1. Clone or download this repository.
2. Copy the desired addon folder(s) into your Windower `addons/` directory.
3. Load an addon in-game:
   ```
   //lua load <addon-name>
   ```
4. Open the configuration GUI:
   ```
   //<alias> config
   ```
5. When finished configuring, save or discard your changes:
   ```
   //<alias> save
   //<alias> discard
   ```

## Development

See [CLAUDE.md](CLAUDE.md) for project conventions, code style, and contribution guidelines.

### Running tests

```bash
lua tests/<addon-name>/run_tests.lua
lua tests/lib/settings/run_tests.lua
```

## Source control

Hosted on a local Forgejo instance.
