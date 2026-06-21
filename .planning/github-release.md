# Plan: github-release

## Goal

Create a single GitHub Actions workflow that fires on every PR merge to `main` and produces a GitHub Release containing a self-contained zip for each addon that changed in the PR, with the PR title as the release name and PR body as the release notes.

## Self-contained packaging

The user should be able to drop a zip into `addons/<addon-name>/` and have a working addon — no separate lib install step.

### Why the require path must change

The addon source currently uses `require('../../lib/settings')`. In a deployed Windower tree the addon lives at `addons/<addon-name>/`, so `../../lib/settings` resolves to `<Windower-root>/lib/settings` — outside the addon folder. To bundle the lib inside the addon, the require path must become `require('lib.settings.settings')`, which Windower resolves relative to the addon directory (i.e., `addons/<addon-name>/lib/settings/settings.lua`).

The test suite is unaffected: tests already call `require('lib.settings.settings')` and run from the repo root where `lib/settings/settings.lua` is on the default package path.

### Zip contents (extracted into `addons/<addon-name>/`)

```
<addon-name>.lua
README.md
lib/
  settings/
    settings.lua    ← copy of repo-root lib/settings/settings.lua
```

Files explicitly excluded from the zip: `data/` (runtime/user config), `tests/`.

## Release versioning and naming

- **Trigger**: `pull_request` event, `types: [closed]`, `if: github.event.pull_request.merged == true`
- **Tag**: `v<YYYY.MM.DD>-pr<PR-number>` (e.g., `v2026.06.21-pr7`), created by the workflow
- **Release name**: `${{ github.event.pull_request.title }}`
- **Release body**: `${{ github.event.pull_request.body }}`
- **Asset filenames**: `<addon-name>-v<_addon.version>.zip` — version extracted from `_addon.version` in the Lua source via grep/sed

## Detecting changed addons

Diff between `github.event.pull_request.base.sha` and `HEAD` (the merge commit), extract top-level directory names, filter to directories that contain a matching `.lua` entry point (excluding `lib/`, `tests/`, `.github/`, `.planning/`).

```bash
git diff --name-only $BASE_SHA $HEAD_SHA \
  | grep -E '^[^/]+/' \
  | cut -d/ -f1 \
  | sort -u \
  | while read dir; do
      [ -f "$dir/$dir.lua" ] && echo "$dir"
    done
```

## Tasks

### Task 1 — Update require path in addon sources

**File**: `echo/echo.lua`

Change:
```lua
local settings_lib = require('../../lib/settings')
```
to:
```lua
local settings_lib = require('lib.settings.settings')
```

Run `lua tests/echo/run_tests.lua` to confirm tests still pass. Apply the same change to any future addons.

This is the only source-code change required.

### Task 2 — Write the GitHub Actions workflow

**File**: `.github/workflows/release.yml`

Workflow outline:

```yaml
name: Release

on:
  pull_request:
    types: [closed]
    branches: [main]

jobs:
  release:
    if: github.event.pull_request.merged == true
    runs-on: ubuntu-latest
    permissions:
      contents: write

    steps:
      - uses: actions/checkout@v4
        with:
          fetch-depth: 0

      - name: Detect changed addons
        id: addons
        run: |
          # list addon dirs changed in this PR
          ...

      - name: Package addons
        run: |
          for addon in $CHANGED_ADDONS; do
            # copy lib into addon staging area
            mkdir -p staging/$addon/lib/settings
            cp -r $addon/. staging/$addon/
            cp lib/settings/settings.lua staging/$addon/lib/settings/settings.lua
            rm -rf staging/$addon/data   # never ship runtime data
            # extract version from _addon.version = 'x.y.z'
            version=$(grep -m1 "_addon.version" $addon/$addon.lua | grep -oE "'[0-9.]+'" | tr -d "'")
            (cd staging && zip -r ../$addon-v${version}.zip $addon/)
          done

      - name: Create release
        uses: softprops/action-gh-release@v2
        with:
          tag_name: v${{ github.event.pull_request.merged_at && '...' }}-pr${{ github.event.pull_request.number }}
          name: ${{ github.event.pull_request.title }}
          body: ${{ github.event.pull_request.body }}
          files: "*.zip"
```

Exact tag generation: use `${{ github.run_id }}` or format the merge date from `github.event.pull_request.merged_at` via a `date` step.

### Task 3 — Smoke-test the workflow locally (optional but recommended)

Use [`act`](https://github.com/nektos/act) to run the workflow locally against a test PR event payload before pushing.

## Out of scope

- Publishing to any package registry
- Changelog generation beyond the PR body
- Signing or checksumming release artifacts
- Releasing unchanged addons when only lib changes (future: could trigger a re-release of all addons if `lib/settings/settings.lua` changes)
