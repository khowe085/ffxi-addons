# Using the Binder

The Binder assigns actions to hotbar slots entirely with the controller — no typing, no config
files. It edits the set you are looking at.

## Opening and closing

Hold a trigger so an XHB is displayed, then press **BACK**. The Binder opens on the displayed half
(hold LT for the left 8 slots, RT for the right 8). The same gesture — BACK while a trigger is
held — closes it again; otherwise it stays open until you close it.

## Navigating

Navigation works **while a trigger is held** (the same reason the d-pad emits keys at all):

| Button (trigger held) | Effect |
|---|---|
| D-pad down / right | Move the selection down |
| D-pad up / left | Move the selection up |
| A | Confirm the selection |
| B | Back up one menu level |
| BACK | Close the Binder |

**Releasing the trigger only pauses navigation** — the status line shows `PAUSED`, buttons are
ignored, and the Binder stays open. Hold LT or RT again to resume. While the Binder is open, normal
slot execution is suspended, so pressing A never accidentally casts something.

## Binding an empty slot

Select an empty slot and confirm. The flow is:

1. **Type** — Magic, Job Ability, Weapon Skill, Attack, Ranged Attack, Pet Command, Item, Mount,
   Switch Target, View Map, Raw Command, or Display Mode.
2. **Action** — picking Magic first shows the skill categories (Healing, Enhancing, Enfeebling,
   Elemental, Dark, Ninjutsu, Song, Summoning, Blue, Geomancy, Trust), then the spell list.
3. **Target** — `<t>` current target, `<me>` self, `<st>` select target, `<stnpc>` select NPC, or
   `<bt>` battle target. (Types that need no target skip this step.)
4. **Confirm** — the summary line shows exactly what will be written; A commits it.

Nothing is saved until the final Confirm, so backing out with B abandons the flow cleanly.

### Raw Command presets

A controller cannot type free text, so the **Raw Command** type offers a preset list: **Rest**
(`/heal`), **Sit** (`/sit`), **Check** (`/check <t>`), and **Lock On** (`/lockon`). Anything beyond
these can be typed by hand into the content files (see
[Troubleshooting](Troubleshooting-FAQ.md#where-do-my-files-live)).

## Editing an occupied slot

Selecting an occupied slot opens the slot menu:

| Entry | What it does |
|---|---|
| **Overlay** | Add a conditional overlay on top of the base binding (see below). |
| **Replace** | Bind the slot fresh — clears the base **and every overlay**. |
| **Remove** | Empty the slot immediately. |
| **Swap** | Exchange this slot's binding with another slot in the displayed half. |
| **Reorder Overlays** | Change the order the overlays are checked in. |

Remove and Swap write immediately; Overlay and Replace write on their final Confirm.

## Overlays

An overlay swaps a slot's action automatically while a condition holds — e.g. Cure IV normally,
but a different spell under **Light Arts**. Available overlay types: **Subjob** (matches the
subjob you have set *when you create it*), **Light Arts**, **Dark Arts**, **Addendum: White**, and
**Addendum: Black**. The list only shows types that apply to you right now — the Scholar arts
types only appear on SCH main or sub.

- **Order matters: the first matching overlay wins.** Overlays are checked top-to-bottom and the
  first one whose condition holds replaces the base. Addendum: White implies Light Arts is also
  up, so put **Addendum before Arts** — the other way around, the Arts overlay always matches
  first and the Addendum one never shows. Fix ordering any time with **Reorder Overlays**: A grabs
  the highlighted overlay, the d-pad moves it, A drops and saves, and B while grabbed discards the
  change.
- **The empty-slot trick:** overlay flows offer an extra type — **Empty (noop)**. It blanks the
  slot (shows nothing, does nothing) while its condition holds. Use it to hide a base binding
  under a condition, e.g. hide an ability that is pointless under Dark Arts. It confirms directly,
  with no action or target step.

## Persistence

Binder edits are written to your per-character content files as you confirm them, and survive
reloads and relogs. Shared sets keep their content across jobs; job sets save under the main job
you were on while editing.
