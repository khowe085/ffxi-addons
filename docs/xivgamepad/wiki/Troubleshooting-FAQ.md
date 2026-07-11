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
4. If specifically the **bare** face buttons, START, and BACK are dead while everything works with
   a trigger held, the Steam profile is emitting their keys only inside trigger action layers —
   see [Steam Input Profile: Troubleshooting](Steam-Input-Profile.md#troubleshooting-bare-face-buttons--start--back-do-nothing).
   Also note bare A/B are Enter/Escape by design (A opens the chat line, B closes it).

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

## Skillchain highlights never appear

In order of likelihood:

1. The `skillchain_display` toggle is off — check the Display tab of `//xg config`.
2. The chain window expired — highlights only show during the green `Go!` phase, and only for
   your **current target**.
3. The weapon skill is newer than the ported chain data (~2017) — post-2017 weapon skills never
   highlight. Known limitation, not a bug.
4. The slot is a spell — magic never highlights, and magic bursts are not shown. See
   [Skillchains and Mounts](Skillchains-and-Mounts.md).

## The game pauses briefly at login after a Windower update

Normal. The addon keeps a generated resource cache (`data/generated/`) keyed to Windower's own
resource files; when those change — typically a Windower update — the cache is rebuilt once at the
next login. Subsequent logins are instant again.

## Item slots show a generic icon

Item icons are extracted from your FFXI install's DAT files the first time an item slot is shown,
then cached under `data/icons/items/`. Falling back to the built-in generic item art means the
extraction failed — usually a non-standard FFXI install path or missing/unreadable DAT files. It
is purely cosmetic: the slot still fires correctly. Deleting `data/icons/` is always safe — the
icons are re-extracted the next time the slot is displayed.

## Where do my files live?

Everything is under the addon folder — per character, plus two character-independent caches:

| File | Contents |
|---|---|
| `data/<Character>/settings.json` | Addon settings: key mapping, sets metadata, display assignments, gestures, HUD positions. |
| `data/<Character>/shared.json` | Shared hotbar set contents (slot bindings + overlays). |
| `data/<Character>/job.json` | Job hotbar set contents, keyed by main-job abbreviation. |
| `data/debug.log` | The debug trace, only written while `//xg debugmode` is on. |
| `data/generated/` | Generated spell/ability resource cache — rebuilt automatically; **safe to delete**. |
| `data/icons/items/` | Extracted item-icon cache — regenerable; **safe to delete**. |

## How do I reset?

Unload the addon (`//lua unload xivgamepad`), delete the file you want reset —
`settings.json` for configuration (the Key-Capture Wizard will re-offer on next login),
`shared.json` / `job.json` for hotbar contents — then load again. Delete just one file to keep the
rest.

## Something else is wrong

Turn on `//xg debugmode` and reproduce the problem: every button event, gesture, and action is
traced to chat and `data/debug.log`. Attach the log to your report. Debug mode always starts off
after a reload, so it cannot be left on by accident.
