Add a new in-game command to an existing addon.

Arguments: `$ARGUMENTS` — expected format: `<addon-name> <command-name> "<description>"` (e.g. `huntbuddy toggle "Toggle hunting mode on or off"`)

Parse `$ARGUMENTS` to extract:
- `addon_name` — first word
- `command_name` — second word (must be lowercase, snake_case if multi-word)
- `description` — remaining text (used in README and help output)

If any argument is missing, ask the user before proceeding.

Read the existing `<addon-name>/<addon-name>.lua` before making any changes.

**Changes to make:**

1. **Add a public function stub** in the public functions block (maintain alphabetical order):
   ```lua
   local function <command_name>(...)
     -- TODO: implement
   end
   ```

2. **Register the command in the dispatch table** inside `windower.register_event('addon command', ...)`. Add an entry `<command_name> = <command_name>` in alphabetical order among the existing commands.

3. **Update `print_help`** to include the new command in its output so `//alias help` lists it.

4. **Update `<addon-name>/README.md`**: add a new row to the Commands table:
   ```
   | `//alias <command_name>` | <description> |
   ```
   Insert it in the table in a logical position (after `config`/`save`/`discard`/`help` if unrelated, or near related commands).

After making changes, print a brief summary of what was added and remind the user to implement the function body.
