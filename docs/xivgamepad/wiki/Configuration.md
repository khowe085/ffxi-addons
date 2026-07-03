# Configuration

`//xg config` (or `//xg c`) opens the configuration window — four tabs, a Save / Discard footer,
and a draggable header. Running the command again while it is open does nothing, and clicks over
the window never reach the game.

**Everything you change is staged**: nothing touches your saved settings until you click **Save**
(or type `//xg save`). **Discard** (`//xg discard`) throws the staged changes away — including any
HUD elements you dragged. Closing via command behaves exactly like clicking the button.

While the window is open, the **HUD becomes draggable**: grab either hotbar half or the set label
and move it anywhere. Positions are staged like every other change and persist on Save.

Rows in every tab are edited by **clicking directly on the value** you want to change; each tab's
header row reminds you what its click zones do. Tabs taller than the window scroll with the mouse
wheel.

## Sets tab

One row per set position (1–8) showing its name, source, and cycle flag.

- Click the **left half** of a row to toggle its source between `job` and `shared`.
- Click the **right half** to toggle `[cycle]` / `[skip]` (skip keeps the set out of the RB-tap
  rotation; direct-switch still reaches it).

## Display tab

- One row per WXHB/Expanded view: click the **left half** to cycle the assigned set (1–8), the
  **right half** to flip the assigned half (left/right).
- `hide_empty_slots` — click to toggle. When on, empty slot frames are not drawn (bound slots keep
  their positions).
- Three **transparency** rows — `standard` (no view active), `active` (the displayed half), and
  `inactive` (the other half). Values run 0 (fully visible) to 100 (invisible); click the left
  half of the row to lower by 10, the right half to raise by 10. The default of `inactive = 100`
  makes the non-displayed half vanish while a trigger is held.

## Keys tab

Shows every virtual button with the key code it is mapped to (unmapped buttons say so). The mapping
is not edited by clicking — press the **`[ Capture / Re-learn key mapping ]`** row at the top to
launch the [Key-Capture Wizard](Installation-and-Setup.md#4-first-login--the-key-capture-wizard),
which re-records buttons by pressing them. It pre-loads your current values, so you can fix one
button and cancel out of the rest.

## Gestures tab

Every gesture is listed as **two rows**:

```
[x] wxhb_l_tap     type=double_tap     btn=LT
    ctx=bare        act=activate_wxhb_l  - max_gap=0.33 +
```

- **`[x]`** (start of the first row) — remove the gesture.
- **`type=`** — click to cycle through the six gesture types (button, tap, hold, double_tap,
  hold_then_hold, hold_then_press). Changing type fills in that type's timing parameter if it is
  missing.
- **`btn=`** — click to cycle the host button.
- **`ctx=`** — click to cycle the required context: `bare`, `trigger_held`, `rb_held`, `lb_held`.
- **`act=`** — click to cycle through every registered action (see the gesture table in
  [Controls and Gestures](Controls-and-Gestures.md) for what they do).
- **`-` / `+`** — click to tune the timing value down / up in steps of 0.05 seconds.
- **`[+ add gesture]`** (last row) — append a fresh `custom_N` entry, then cycle its fields into
  shape.

Slot bindings are **not** configured here — use [the Binder](Using-the-Binder.md).
