Create a new Windower 4 addon scaffold in this repository.

Arguments: `$ARGUMENTS` — expected format: `<addon-name> <alias>` (e.g. `huntbuddy htb`)

Parse `$ARGUMENTS` to extract the addon name (first word) and alias (second word). If either is missing, ask the user before proceeding.

Create the following files, following all conventions in CLAUDE.md and lib/settings/CLAUDE.md:

**`<addon-name>/<addon-name>.lua`** — boilerplate main file using the required file layout:
1. require statements (`lib/settings`)
2. `_addon` metadata (name, author placeholder, version `1.0.0`, commands `{addon-name, alias}`)
3. State block (`live_settings`, `staged_settings`)
4. Forward declarations for any private functions
5. Public functions (alphabetical): `change_pos`, `setup_exit_discard`, `setup_exit_save`, `setup_open`, `print_help`
6. Private functions block (empty, with a comment placeholder)
7. Event registrations: `load`, `unload`, `addon command` (with dispatch table containing `exit`, `help`, `setup`)

The `addon command` handler must check if the first arg to `exit` is `-d` to route to `setup_exit_discard` vs `setup_exit_save`.

Default settings should include `pos_x = 0` and `pos_y = 0`.

**`<addon-name>/README.md`** — per-addon README with:
- One-sentence description placeholder
- Installation section
- Commands table listing `setup`, `exit`, `exit -d`, and `help` with the alias prefix
- Configuration section describing `data/{CharacterName}/settings.json`

**`tests/<addon-name>/mock_windower.lua`** — stubs for `windower`, `texts`, and any other Windower globals the addon uses. The mock must expose:
- `windower.register_event` (captures handlers in a table for tests to invoke)
- `windower.ffxi.get_player()` returning `{ name = 'TestChar' }`
- `windower.add_to_chat` (no-op stub)
- `windower.addon_path` set to a temp path

**`tests/<addon-name>/run_tests.lua`** — discovers and runs all `test_*.lua` files in the same directory; prints pass/fail counts; exits with code 1 if any test fails.

**`tests/<addon-name>/test_commands.lua`** — initial test file covering:
- `help` command does not error
- `setup` opens a staging session (`settings_lib.in_setup()` returns true after)
- `exit -d` discards without writing
- `exit` commits staged settings

After creating all files, print a summary of what was created and remind the user to:
1. Fill in their author name in `_addon.author`
2. Update the description in `README.md`
3. Update the addon table in the root `README.md`
