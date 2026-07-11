# XIVGamepad — Crossbar Asset & Feature Port

## Context

User-directed scope addition to XIVGamepad (PR #17, branch `work/xivgamepad`): bring over from the
xivcrossbar fork (1) the `images/` icon assets, (2) the generated-resources pipeline, (3) runtime
icon extraction, (4) mount roulette, and (5) skillchain tracking/display. This **relaxes the
original clean-room rule for these five components only** — they are ported third-party code and
must carry their licenses.

**License facts (verified):** xivcrossbar's repo LICENSE is MIT (© 2020 AliekberFFXI), but the
ported files carry their own BSD-3 headers — `icon_extractor.lua` © 2021 Rubenator,
`libs/skillchain/*` © 2017 Ivaar, `libs/mountroulette/*` © 2020 Dean James (Xurion of Bismarck).
Headers are retained verbatim; a `LICENSES-THIRD-PARTY.md` and README credits section cover
attribution (this also replaces xivcrossbar's in-game credits screen, so `credit_avatars/` is not
ported).

## Approach

**Quarantine + adapt.** Ported files land in `xivgamepad/crossbar/` — a clearly-marked third-party
subtree exempt from style/convention audits — with only enumerated edits (require paths, event-
registration extraction, output-path redirection, Lua 5.1 parse fixes, global hygiene), each marked
with a `PORT:` comment under the retained header. Everything conventional lives in four new thin
**adapter modules** (`gamedata`, `icons`, `mounts`, `skillchain`) that main wires per the existing
architecture: **main owns all Windower event registration**, adapters expose handlers and queries,
and unit tests target the adapters plus every modified ported line.

Two standing conventions get explicit treatment:

- **Runtime files under `data/` only** — xivcrossbar writes generated resources and extracted BMPs
  to the addon root; the port redirects them to `data/generated/` and `data/icons/items/`.
- **io carve-out** — icon extraction must binary-read FFXI ROM DATs under `windower.ffxi_path`,
  which the Windower `files` API cannot do. `crossbar/icon_extractor.lua` becomes the single
  reviewed exception to the no-`io` rule (read-only game DATs, write-only to `data/icons/`),
  documented in the module, the reference docs, and one exception line in repo `CLAUDE.md`
  (needs sign-off, see Open Questions).

### Component summaries

1. **Assets** — copy `images/icons/**` (~7 MB, ~1,520 PNGs: pre-extracted spell/ability/weapon/
   element/skillchain icons + the authored `iconpacks/default/`). Skip `credit_avatars/` and the
   `.svg` sources. Bonus fix: the HUD currently references image paths that ship nowhere — re-point
   its type/empty/sweep art at iconpack equivalents and add the few genuinely missing frames.
   Add explicit `*.png/*.bmp binary` gitattributes.
2. **Generated resources** — port `resource_generator` (+ `kebab_casify`, `ordered_pairs`, `md5`);
   output to `data/generated/crossbar_{spells,abilities}.lua`; loaded via the files API +
   `loadstring` (never `require` — regeneration must not be cache-stale, and tests must stay on the
   in-memory fs). MD5 freshness against Windower's res sources (read-only walk-up, documented).
   The `gamedata` adapter exposes entry/icon/recast/category lookups; the HUD switches its icon and
   tooltip/recast resolution to it (res-scan kept as fallback), and the binder gains job-ability
   category sub-menus from it.
3. **Icon extraction** — port `icon_extractor` (unload-event and mid-write yield removed; adapter
   owns lifecycle); `icons` adapter caches extracted 32×32 BMPs id-keyed under `data/icons/items/`,
   returns nil + one debug log per item on any failure (missing DAT, non-Windows env) so the HUD
   falls back to iconpack art. Tested via an injected in-memory `io` fake with synthetic DAT bytes.
4. **Mount roulette** — port the lib minus its own event registration; `mounts` adapter derives
   owned mounts (key items, category Mounts), refreshed from init and incoming chunk 0x055 (wired
   by main); new frozen system action `mount_roulette` (dismounts if mounted, else random owned
   mount); binder's mount menu lists owned mounts + a Mount Roulette entry.
5. **Skillchain** — port `skillchains.lua` (state machine) + `skills.lua` (static WS/JA property
   data) with event extraction; main forwards action packets, chunks 0x29/0x63, job/zone/login/
   logout, and prerender into the `skillchain` adapter. HUD adds a per-slot **eligible-skillchain
   highlight** (property icon overlay, resolved per tick within the chain window) and a draggable
   `sc_timer` element ("Wait n.n" → "Go! n.n"), position persisted via the existing hud_positions
   machinery. New settings key `skillchain_display` (default true) with a Display-tab toggle.
   Tests drive the real ported lib with fixture action packets over minimal harness shims for
   Windower's `luau`/`pack`/`actions`/`lists`/`sets` libs and a stubbed clock.

## Tasks

- **Wave 0 (sequential, small):** contracts amendment (adapter APIs, `mount_roulette` action,
  `skillchain_display` default, hud/binder opts additions, `sc_timer` element, data paths,
  crossbar require names) + additive harness shims + run_tests manifest (+4 files, warn-skip) +
  gitattributes/styluaignore.
- **Wave 1 (five parallel tasks, disjoint files):** 1A assets + attribution · 1B resource pipeline
  (`crossbar/` generator libs + `gamedata` + tests) · 1C icon extraction (`crossbar/icon_extractor`
  + `icons` + tests) · 1D mounts (`crossbar/mountroulette` + `mounts` + tests) · 1E skillchain
  (`crossbar/skillchain/` + `skillchain` + tests). Adapters only — no edits to existing modules.
- **Wave 2 (three parallel tasks + one sequential):** 2A HUD integration (sole owner of `hud.lua`)
  · 2B action + binder integration · 2C main + config wiring (compiles against Wave-0 frozen
  APIs) · then 2D integration reconciliation (end-to-end no-stub test additions, full suite green).
- **Wave 3:** docs (README credits/config/data-files; wiki page for skillchains & mounts + updates;
  reference docs incl. the io carve-out; integration-test-plan blocks 13–15) + QA loop.

Standard per-task dev → reviewer cycles; squash-merges onto `work/xivgamepad`.

## Verification

Full suite green (`lua tests/xivgamepad/run_tests.lua`, 17 test files after the port) plus
lib/settings and echo suites; license-header diff of `crossbar/` against the submodule (only
enumerated PORT edits may differ); `/check-conventions` clean. In-game: new integration-test-plan
blocks — 13 icons/generated resources (regeneration, extracted-BMP rendering, graceful fallback),
14 mount roulette, 15 skillchain HUD.

## Open Questions (answer with approval)

1. **Base branch:** extend `work/xivgamepad` so this lands in PR #17 (recommended — the features
   depend on unmerged code), or wait for #17 to merge and run a fresh `work/` branch off `main`?
2. **Repo size:** committing the icons adds ~7 MB (~doubles the repo). In-repo recommended
   (zero install friction); alternative is a release-artifact zip + install step.
3. **CLAUDE.md io exception:** OK to add the one-line documented exception for
   `crossbar/icon_extractor.lua` so convention audits stay clean?
4. **skills.lua staleness:** the © 2017 skillchain data lacks post-fork weapon skills (they simply
   never highlight). Ship as-is (recommended), or budget a follow-up refresh against upstream?
5. **Test-shim fidelity:** skillchain tests run against thin fakes of Windower's `actions`/`luau`/
   `pack` libs; real-hardware confirmation stays in integration block 15. Accept (recommended), or
   vendor the real Windower libs into the harness?

## Resources

- Exploration + architecture reports: this session (xivcrossbar inventory, licensing, io usage,
  integration surfaces; adapter/wave design).
- `xivcrossbar/` submodule — the port source; `ui.lua` / `action_binder.lua` / `xivcrossbar.lua`
  for consumption patterns.
- `.planning/xivgamepad.md` + `.planning/xivgamepad-contracts.md` — the base addon's plan and
  frozen contracts (amended in Wave 0).
