# Troubleshooting / FAQ

## The hotbar cursor moves AND my party target changes when I use the d-pad under a trigger

Your Steam d-pad chord is **stacking** on top of the native d-pad instead of replacing it, so one
press fires both. Re-create the chord in Steam Input so the base d-pad binding is **interrupted /
replaced** while the modifier is held — see
[the d-pad chords](Steam-Input-Profile.md#the-d-pad-chords-read-this-part-carefully) for the exact
steps and the in-game verification.

## Buttons type numbers into my chat bar

Expected while the chat line is open. The controller buttons are real number-row keys, and open
chat accepts them as text; the addon suspends slot execution the whole time so nothing fires.
Press bare **B** (Escape) to dismiss the chat line and everything resumes. Your physical keyboard
types normally throughout.

## My macro palette (Ctrl+number) stopped working

Intentional. `Ctrl`+number is how BACK, START, and the trackpad zones reach the addon, and FFXI
would otherwise fire macros on those presses. The addon neutralizes the `Ctrl`+number palette (and
`F9`–`F12`) while it is loaded and **restores them when you unload it**
(`//lua unload xivgamepad`). `F1`–`F8` and the macro book itself are untouched.

## Nothing happens when I press a button

1. Run `//xg test` and press the button. If the grid does not light up, the addon is not receiving
   the key — your Steam profile and the key mapping disagree. Run `//xg learn` and re-capture.
2. If the grid lights up but nothing fires in-game, check the suspend conditions: a menu or the
   chat line is open (slot execution pauses), a cutscene is running (everything pauses), or the
   Binder / Tester is open.
3. Remember the d-pad only reaches the addon while LT, RT, or RB is held.

## The wizard captured the wrong key

`//xg learn back` steps back one button and re-captures it (the previous key is restored first).
Or finish/cancel and re-run `//xg learn` later — it pre-loads your current mapping, so re-capture
just the wrong button and cancel out of the rest... but note **cancel discards the whole
session's captures**: to keep a fix you must finish the wizard (skip through the optional steps
with `//xg learn skip`).

## Zoom doesn't work

Zoom is **not an addon gesture** — it is the LB layer inside your Steam Input profile sending the
`.` / `,` keys while LB is held. If holding LB and pushing the right stick up/down does nothing,
fix the layer in Steam (see [the LB zoom layer](Steam-Input-Profile.md#the-lb-zoom-layer)), and
check FFXI's keyboard config still has `.` / `,` as zoom. `//xg test` will show nothing for the
right stick — that is normal; the addon never sees it.

## Auto-run does nothing

The bare-LB tap issues FFXI's `/autorun` command. If your client does not accept `/autorun`,
please report it — the planned fix is synthesizing the native auto-run key instead.

## Where do my files live?

Everything is under the addon folder, per character:

| File | Contents |
|---|---|
| `data/<Character>/settings.json` | Addon settings: key mapping, sets metadata, display assignments, gestures, HUD positions. |
| `data/<Character>/shared.json` | Shared hotbar set contents (slot bindings + overlays). |
| `data/<Character>/job.json` | Job hotbar set contents, keyed by main-job abbreviation. |
| `data/debug.log` | The debug trace, only written while `//xg debugmode` is on. |

## How do I reset?

Unload the addon (`//lua unload xivgamepad`), delete the file you want reset —
`settings.json` for configuration (the Key-Capture Wizard will re-offer on next login),
`shared.json` / `job.json` for hotbar contents — then load again. Delete just one file to keep the
rest.

## Something else is wrong

Turn on `//xg debugmode` and reproduce the problem: every button event, gesture, and action is
traced to chat and `data/debug.log`. Attach the log to your report. Debug mode always starts off
after a reload, so it cannot be left on by accident.
