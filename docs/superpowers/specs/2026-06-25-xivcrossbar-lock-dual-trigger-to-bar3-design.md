# Design: xivcrossbar — Lock Dual-Trigger to Hotbar 3

**Date:** 2026-06-25

## Summary

Add a `Controls.LockDualTriggerToBar3` boolean setting to xivcrossbar. When `true`, pressing both triggers (LT+RT) always activates Hotbar 3 regardless of which trigger was pressed second. Hotbar 4 becomes inaccessible while the flag is enabled. Default is `false`, preserving existing order-dependent behavior.

## Background

When both triggers are held, xivcrossbar determines which hotbar to show based on which trigger was pressed second:

- Right-held, then Left → Hotbar 3
- Left-held, then Right → Hotbar 4

This only applies when `Hotbar.Number > 3`; if the user has 3 or fewer hotbars configured, Hotbar 3 is always shown unconditionally.

Some users find the order-dependent distinction unreliable or disorienting and prefer a single, predictable result for any dual-trigger press.

## Design

### Files changed

| File | Change |
|------|--------|
| `xivcrossbar/defaults.lua` | Add `defaults.Controls.LockDualTriggerToBar3 = false` |
| `xivcrossbar/theme.lua` | Map `settings.Controls.LockDualTriggerToBar3` → `options.lock_dual_trigger_to_bar3` |
| `xivcrossbar/xivcrossbar.lua` | Add `and not theme_options.lock_dual_trigger_to_bar3` to the order-dependent guard |

### Behavioral change

```lua
-- Before (line 749):
if (theme_options.hotbar_number > 3) then

-- After:
if (theme_options.hotbar_number > 3 and not theme_options.lock_dual_trigger_to_bar3) then
```

When the flag is `true`, the `else` branch is taken, which calls `change_active_hotbar(3)` — the identical code path already used when `hotbar_number <= 3`.

### Behavior matrix

| `hotbar_number` | `LockDualTriggerToBar3` | Trigger order | Result   |
|----------------|------------------------|---------------|----------|
| > 3            | `false` (default)       | R → L         | Hotbar 3 |
| > 3            | `false` (default)       | L → R         | Hotbar 4 |
| > 3            | `true`                  | either        | Hotbar 3 |
| ≤ 3            | either                  | either        | Hotbar 3 (unchanged) |

## Constraints

- xivcrossbar is a third-party fork submodule (`khowe085/xivcrossbar`); it is exempt from monorepo lib/settings and lifecycle conventions.
- No new files. No UI changes. No test harness exists for this addon.
- The change is verified by simulation (luac syntax check + manual review of the condition logic).

## Out of scope

- A corresponding `LockDualTriggerToBar4` flag (not requested).
- Exposing the flag via an in-game command (not requested; user edits the settings XML directly).
