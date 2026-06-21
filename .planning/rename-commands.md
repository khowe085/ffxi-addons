# Plan: Rename GUI Commands

## Goal

Rename the standard addon GUI commands for clarity:

| Old | New | Aliases |
|-----|-----|---------|
| `setup` | `config` | `c` |
| `exit` | `save` | `s` |
| `exit -d` | `discard` | `d` |

All three new commands need single-letter aliases. The `-d` flag pattern on `exit` is eliminated; `save` and `discard` are now fully separate commands.

## Scope

This is a repo-wide convention change. Every file that documents or implements these command names must be updated.

## Files Affected

**Implementation**
- `echo/echo.lua` — commands table, `print_help`, remove `gui_close` (no longer needed)

**Tests**
- `tests/echo/test_commands.lua` — update command strings in dispatch tests and print_help assertions; add alias coverage tests

**Documentation**
- `echo/README.md`
- `CLAUDE.md`
- `lib/settings/CLAUDE.md`
- `.claude/agents/lua-dev.md`
- `.claude/agents/lua-reviewer.md`
- `.claude/commands/add-command.md`
- `.claude/commands/check-conventions.md`
- `.claude/commands/new-addon.md`

## Tasks

| Task | Files | Agent |
|------|-------|-------|
| A | `echo/echo.lua`, `tests/echo/test_commands.lua` | lua-dev |
| B | All `.md` documentation files listed above | lua-dev |

Tasks A and B can run in parallel.
