# Hotbar Sets and Display Modes

## The eight set positions

The addon keeps **8 set positions** in memory. Each position has a **name**, a **source** —
`shared` or `job` — and a **skip cycle** flag, all edited on the [Sets tab](Configuration.md).

- A **shared** position shows the same content on every job.
- A **job** position shows content stored per main job — switch from WHM to SCH and position 1
  becomes your SCH bar automatically.

Each set has **16 slots**, split into a left half (slots 1–8) and a right half (9–16). The default
layout:

| Position | Source | Skip cycle |
|----------|--------|------------|
| 1 | job | no |
| 2 | job | no |
| 3 | job | yes |
| 4 | job | yes |
| 5 | job | yes |
| 6 | shared | no |
| 7 | shared | yes |
| 8 | shared | no |

## Shared mode and job mode

You are always in **shared mode** or **job mode** (shown in the HUD label). Mode decides which pool
the set-cycling gesture walks: job mode cycles the job-sourced positions, shared mode the shared
ones. **Hold LB + press RB** (no trigger held) switches modes and jumps to the new pool's first
usable set. If you are **mounted**, that same gesture **dismounts** you instead — think of it as
FFXIV's weapon draw/sheathe, adapted.

## The six views

| View | Gesture | Set shown | Half shown |
|------|---------|-----------|------------|
| XHB-L | Hold LT | Current cycling set | Left 8 |
| XHB-R | Hold RT | Current cycling set | Right 8 |
| WXHB-L | Hold LT + L4, or double-tap LT | Your assigned set | Your configured half |
| WXHB-R | Hold RT + R4, or double-tap RT | Your assigned set | Your configured half |
| Expanded LT→RT | Hold LT, then also RT | Your assigned set | Your configured half |
| Expanded RT→LT | Hold RT, then also LT | Your assigned set | Your configured half |

WXHB and Expanded views are assigned a set + half on the [Display tab](Configuration.md). By
default both WXHB views show set 2 (left/right halves) and both Expanded views show set 4's right
half.

## Slot addressing

Within whichever half is on screen, the **d-pad directions are slots 1–4** and the **face buttons
are slots 5–8** — always **relative to the displayed half**, never a fixed 1–16 number:

| Button | Slot |
|---|---|
| D-pad Up / Right / Down / Left | 1 / 2 / 3 / 4 |
| A / B / X / Y | 5 / 6 / 7 / 8 |

XHB-L shows the set's left 8, XHB-R the right 8, WXHB/Expanded whatever half you configured — in
every case the same eight physical buttons address the eight slots you are looking at.

## Cycling and direct switch

- **Tap RB (bare)** advances the XHB to the next set in the current mode's pool. Sets that are
  empty, or marked **skip cycle**, are passed over — park situational bars (like a crafting set)
  on skip and they stay out of the rotation.
- **Hold RB + a d-pad direction or face button** jumps straight to set position 1–8 (same button
  order as slot addressing: d-pad Up = set 1 … Y = set 8). A direct jump works across pools and
  does **not** change your mode — cycling afterwards resumes in the pool you were in.

Next: put actions in the slots with [the Binder](Using-the-Binder.md).
