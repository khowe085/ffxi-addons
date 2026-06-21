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
<lib>/          ← one entry per lib listed in README.md ## Libraries
  ...
```

Files explicitly excluded from the zip: `data/` (runtime/user config), `tests/`.

### Library declaration

Each addon's `README.md` declares its required libs in a `## Libraries` section:

```markdown
## Libraries

- `lib/settings`
```

The packaging step parses this section with `awk` and copies each listed lib directory into the addon staging area. Only libs actually declared are bundled — no implicit dependencies.

## Release versioning and naming

- **Trigger**: `workflow_dispatch` (manual trigger from the GitHub Actions UI)
- **Inputs**:
  - `release_name` (required) — the GitHub Release title
- **Tag**: `v<YYYY.MM.DD>` (e.g., `v2026.06.21`), generated from the current UTC date at run time; if multiple releases land on the same day, append `-2`, `-3`, etc.
- **Release notes**: auto-generated from git history since the previous release tag using GitHub's release-notes API (`gh api repos/{owner}/{repo}/releases/generate-notes`). This pulls merged PR titles and bodies between the last tag and HEAD.
- **Asset filenames**: `<addon-name>-v<_addon.version>.zip` — version extracted from `_addon.version` in the Lua source via grep/sed

## Detecting changed addons

Scan the repository for top-level directories that contain a matching `.lua` entry point (i.e. `<dir>/<dir>.lua` exists), excluding `lib/`, `tests/`, `.github/`, `.planning/`. All qualifying addons are packaged on every manual run.

```bash
for dir in */; do
  dir="${dir%/}"
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
  workflow_dispatch:
    inputs:
      release_name:
        description: 'Release title'
        required: true

jobs:
  release:
    runs-on: ubuntu-latest
    permissions:
      contents: write

    steps:
      - uses: actions/checkout@v4
        with:
          fetch-depth: 0   # full history needed for tag lookup

      - name: Generate tag
        id: tag
        run: |
          base="v$(date -u +%Y.%m.%d)"
          tag="$base"
          n=2
          while git ls-remote --tags origin "refs/tags/$tag" | grep -q .; do
            tag="${base}-${n}"; n=$((n+1))
          done
          echo "tag=$tag" >> $GITHUB_OUTPUT

      - name: Generate release notes
        id: notes
        env:
          GH_TOKEN: ${{ secrets.GITHUB_TOKEN }}
        run: |
          prev=$(git tag --sort=-version:refname | head -1)
          args="--field tag_name=${{ steps.tag.outputs.tag }}"
          [ -n "$prev" ] && args="$args --field previous_tag_name=$prev"
          body=$(gh api repos/${{ github.repository }}/releases/generate-notes \
            $args --jq '.body')
          echo "body<<EOF" >> $GITHUB_OUTPUT
          echo "$body"     >> $GITHUB_OUTPUT
          echo "EOF"       >> $GITHUB_OUTPUT

      - name: Detect addons
        id: addons
        run: |
          addons=$(for d in */; do d="${d%/}"; [ -f "$d/$d.lua" ] && echo "$d"; done | tr '\n' ' ')
          echo "list=$addons" >> $GITHUB_OUTPUT

      - name: Package addons
        run: |
          for addon in ${{ steps.addons.outputs.list }}; do
            mkdir -p staging/$addon/lib/settings
            cp -r $addon/. staging/$addon/
            cp lib/settings/settings.lua staging/$addon/lib/settings/settings.lua
            rm -rf staging/$addon/data
            version=$(grep -m1 "_addon.version" $addon/$addon.lua | grep -oE "'[0-9.]+'" | tr -d "'")
            (cd staging && zip -r ../$addon-v${version}.zip $addon/)
          done

      - name: Create release
        uses: softprops/action-gh-release@v2
        with:
          tag_name: ${{ steps.tag.outputs.tag }}
          name: ${{ github.event.inputs.release_name }}
          body: ${{ steps.notes.outputs.body }}
          files: "*.zip"
```

### Task 3 — Smoke-test the workflow locally (optional but recommended)

Use [`act`](https://github.com/nektos/act) to run the workflow locally against a test PR event payload before pushing.

## Out of scope

- Publishing to any package registry
- Signing or checksumming release artifacts
