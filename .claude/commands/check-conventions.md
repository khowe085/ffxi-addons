Audit one or all addons against the conventions defined in CLAUDE.md and lib/settings/CLAUDE.md.

Arguments: `$ARGUMENTS` — optional addon name. If omitted, audit all addon directories.

For each addon being checked, read its files and verify every rule below. Report findings as a checklist — a checkmark for each passing rule and a clear failure description for each violation.

---

**Directory structure**
- [ ] `<addon-name>/<addon-name>.lua` exists
- [ ] `<addon-name>/README.md` exists
- [ ] `<addon-name>/data/` directory exists
- [ ] `tests/<addon-name>/run_tests.lua` exists
- [ ] `tests/<addon-name>/mock_windower.lua` exists
- [ ] At least one `tests/<addon-name>/test_*.lua` file exists

**`_addon` metadata (in main .lua)**
- [ ] `_addon.name` is set
- [ ] `_addon.author` is set and not a placeholder
- [ ] `_addon.version` is set
- [ ] `_addon.commands` has exactly two entries (full name + short alias)

**Required commands**
- [ ] `setup` command is present in the dispatch table
- [ ] `exit` command is present and routes to a save function
- [ ] `exit -d` (the `-d` flag) is handled and routes to a discard function
- [ ] `help` command is present in the dispatch table

**Settings library usage**
- [ ] Main .lua file requires `lib/settings` (or a path resolving to it)
- [ ] Main .lua file does NOT directly `require('config')` or call `config.load` / `config.save`
- [ ] Staged settings pattern is used: a separate staged table is populated on `setup_open` and nil'd on exit

**Data folder rules**
- [ ] No file write operations target the addon root or `lib/` — all writes reference a path under `data/`
- [ ] Per-character settings path includes the character name subdirectory

**GUI rules (if any `texts` or UI library is used)**
- [ ] GUI callbacks delegate to named functions rather than containing logic directly
- [ ] A `change_pos` (or equivalent) function exists if the addon has a repositionable element

**File layout order**
- [ ] `require` statements appear before `_addon` metadata
- [ ] State variables are declared before function definitions
- [ ] Event registrations (`windower.register_event`) appear at the bottom of the file

**Per-addon README**
- [ ] README contains a Commands section with a markdown table
- [ ] Commands table includes `setup`, `exit`, `exit -d`, and `help` rows
- [ ] Commands table uses the correct alias prefix
- [ ] README contains a Configuration section

---

After checking all rules, print a summary:
- Total checks, passed, failed
- If any failures: list them grouped by addon with the specific rule that failed
- If all pass: confirm the addon is convention-compliant

Do not auto-fix violations — report only. If the user wants fixes applied, they should follow up explicitly.
