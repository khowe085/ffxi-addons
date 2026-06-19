Run the test suite for one or all addons in this repository.

Arguments: `$ARGUMENTS` — optional addon name (e.g. `huntbuddy`). If omitted, run all test suites.

**If an addon name is given:**

Run `lua tests/<addon-name>/run_tests.lua` using the Bash tool. Report pass/fail output. If the test file does not exist, say so clearly and do not attempt to run it.

Also run `lua tests/lib/settings/run_tests.lua` if it exists.

**If no argument is given:**

1. Find all `run_tests.lua` files under the `tests/` directory.
2. Run each one with `lua` and collect results.
3. Print a summary table: addon name, number of tests passed, number failed, overall status.
4. Exit with a clear PASS or FAIL verdict.

Report any Lua errors (syntax errors, missing requires, etc.) as test failures, not as tool errors — include the error message in the summary so the user can act on it.
