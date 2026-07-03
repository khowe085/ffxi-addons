# Steam Input Profile

The profile is a **hybrid**: three controls pass through as a native gamepad (FFXI's own config
handles them — see [Installation and Setup](Installation-and-Setup.md)), and everything the addon
reads is a keyboard key. Build it per-control as below.

## Native passthroughs

| Control | Steam Input binding |
|---|---|
| Left stick | Native gamepad joystick (analog movement) |
| Right stick | Native gamepad joystick (analog camera) — plus the LB zoom layer below |
| D-pad | Native gamepad d-pad (party/alliance and menu targeting) — plus the chords below |

## The LB zoom layer

While **LB is held**, the right stick's **vertical axis** should stop panning the camera and drive
FFXI's native zoom keys instead:

1. Add a **momentary action layer** (or "hold action set layer") activated by holding LB.
2. In that layer, bind the right stick's **up** direction to the `.` (period) key — zoom in — and
   **down** to the `,` (comma) key — zoom out. Leave the horizontal axis as the native camera.

The addon is not involved in zoom at all; Steam sends the keys directly, and FFXI's default `.` and
`,` zoom bindings do the rest. This is why zoom never fights the camera pan.

## The d-pad chords (read this part carefully)

The bare d-pad stays a **native d-pad**. On top of that, while **LT**, **RT**, or **RB** is held,
each d-pad direction must emit a keyboard key instead. That is three chord sets over the same four
directions:

| While held | D-pad Up | D-pad Right | D-pad Down | D-pad Left |
|---|---|---|---|---|
| LT, RT, or RB | `9` | `0` | `` ` `` (backtick) | `=` |

How to set it up in the Steam controller-config UI:

1. Leave the d-pad's **base** binding as the native gamepad d-pad.
2. Open the d-pad's settings and **Add Chorded Command** (Chorded Binding).
3. Set the chord's **activator** to the **Left Trigger**, and bind the four directions to `9`, `0`,
   `` ` ``, `=`.
4. Repeat step 2–3 twice more with the **Right Trigger** and the **Right Bumper** as activators.
5. **Critical:** the chord must **replace** the base d-pad output while the modifier is held — not
   stack on top of it. If your Steam build shows a per-chord "interrupt / replace base" (vs. "add
   to base") toggle, choose **replace**. If the base d-pad also fires during a chord, a trigger-held
   d-pad press will move the hotbar cursor **and** change your party target at the same time.

**Verify in-game:** a **bare** d-pad press must still cycle party/alliance targets, but with LT,
RT, or RB held a d-pad press must move the hotbar only — **the native target must not also move**.
If the target still changes, the chord is stacking on the base; re-create it so the base binding is
interrupted while the modifier is held.

## Key outputs

| Physical control | Steam Input output |
|---|---|
| LT / RT | `1` / `2` |
| LB / RB | `3` / `4` |
| A / B / X / Y | `5` / `6` / `7` / `8` |
| D-pad under LT/RT/RB (chords) | `9` / `0` / `` ` `` / `=` (Up / Right / Down / Left) |
| BACK (View / Select) | `Ctrl+1` |
| START (Menu / Options) | `Ctrl+2` |
| Trackpad zones 1–8 | `Ctrl+3` … `Ctrl+0` |
| Paddles L4 / L5 / R4 / R5 | `F9` / `F10` / `F11` / `F12` |
| Right stick vertical, LB held | `.` / `,` (the zoom layer above) |

Why these keys: the plain number row does nothing in FFXI, so those keys can be pressed and held in
any combination without side effects. The `Ctrl`+number keys are FFXI's macro palette and `F9`–`F12`
have native functions — the addon neutralizes those while it is loaded and restores them on unload.
`F1`–`F8` are deliberately untouched so native target selection keeps working.

## The no-shared-modifier rule

Steam Input does not reference-count modifier keys. If two buttons both emitted, say, `Ctrl`+
something, then releasing one would release `Ctrl` for **both** — collapsing the other while you
are still holding it. The profile is built so this can never happen:

- Everything that can be **held together** (triggers, bumpers, faces, the d-pad chords, the
  paddles) uses **unmodified** keys.
- Only the **discrete** controls — BACK, START, and the trackpad zones, which are pressed one at a
  time and never held with each other — share the `Ctrl` modifier.

Keep this rule if you customize the profile: never give two hold-together controls the same
modifier, and never require two `Ctrl`-riding controls (BACK/START/trackpad) held at once.

After building the profile, run the [Key-Capture Wizard](Installation-and-Setup.md) so the addon
records exactly the keys your profile emits.
