Create a new Windower 4 addon scaffold in this repository.

Arguments: `$ARGUMENTS` — expected format: `<addon-name> <alias>` (e.g. `huntbuddy htb`)

Parse `$ARGUMENTS` to extract the addon name (first word) and alias (second word). If either is missing, ask the user before proceeding.

Create the following files, following all conventions in CLAUDE.md and lib/settings/CLAUDE.md:

**`<addon-name>/<addon-name>.lua`** — boilerplate main file using the required file layout:
1. require statements (`lib.settings.settings`, `lib.settings.config_gui`, `texts`, `images`)
2. `_addon` metadata (name, author placeholder, version `1.0.0`, commands `{addon-name, alias}`)
3. State block (`live_settings`, `staged_settings`, `gui`)
4. Forward declarations for any private functions
5. Public functions (alphabetical): `change_pos`, `setup_close_discard`, `setup_close_save`, `setup_open`, `print_help`
6. Private functions block (a `build_tabs(s)` returning the body as a one-element tab list `{ { title = '<Addon>', lines = {...} } }`, plus a comment placeholder)
7. Event registrations: `load`, `login`, `logout`, `unload`, `addon command` (dispatch table with `c`, `config`, `d`, `discard`, `help`, `s`, `save`), and `mouse` (delegated to `gui:handle_mouse`)

The config GUI **must** be built on `lib/settings/config_gui`. In `init()`, create the `gui`
controller once (idempotent) with `texts`/`images` injected, `title = _addon.name`, the
save/discard callbacks, `on_move`, `pos`, and an addon-defined `size`. `setup_open` is a no-op when
`gui:is_open()`; otherwise it opens staging and calls `gui:show(build_tabs(staged_settings))`.
`setup_close_save`/`setup_close_discard` commit/discard and `gui:hide()`. The `mouse` handler must
return `gui:handle_mouse(...)`'s result so clicks over the window never reach the game. See
[lib/settings/CLAUDE.md](../../lib/settings/CLAUDE.md) for the full `config_gui` API and `echo` for
the reference wiring.

Default settings should include `pos_x = 0`, `pos_y = 0`, and the config-window anchor
`config_x` / `config_y`.

**`<addon-name>/README.md`** — per-addon README with:
- One-sentence description placeholder
- Installation section
- Commands table listing `config`/`c`, `save`/`s`, `discard`/`d`, and `help` with the alias prefix
- Configuration section describing `data/{CharacterName}/settings.json`

**`tests/<addon-name>/mock_windower.lua`** — stubs for `windower`, `texts`, `images`, and any other Windower globals the addon uses. The mock must expose:
- `windower.register_event` (captures handlers in a table for tests to invoke)
- `windower.ffxi.get_player()` returning `{ name = 'TestChar' }`
- `windower.add_to_chat` (no-op stub)
- `windower.addon_path` set to a temp path
- a `texts` mock (elements track pos/size/visibility; `pos/pos_x/pos_y/text/show/hide/draggable/destroy`) and an `images` mock (`pos/size/show/hide/destroy`), each bridged via `package.loaded`

**`tests/<addon-name>/run_tests.lua`** — discovers and runs all `test_*.lua` files in the same directory; prints pass/fail counts; exits with code 1 if any test fails.

**`tests/<addon-name>/test_commands.lua`** — initial test file covering:
- `help` command does not error
- `config` opens a staging session (`settings_lib.in_setup()` returns true after)
- `discard` discards without writing
- `save` commits staged settings

After creating all files, print a summary of what was created and remind the user to:
1. Fill in their author name in `_addon.author`
2. Update the description in `README.md`
3. Update the addon table in the root `README.md`
