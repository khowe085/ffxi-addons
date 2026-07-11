# XIVGamepad — In-Game Integration Test Plan

A follow-along checklist for real hardware — the edge cases unit tests can't reach. It assumes the
recommended [Steam Input profile](wiki/Steam-Input-Profile.md) and
[FFXI gamepad configuration](wiki/Installation-and-Setup.md) are in place.

Work one block at a time: each opens with a one-line **SETUP** and ends with a **RESET** so blocks
are independent. Every check is one action and one observable result — tick the box, and report
failures by check number (e.g. "6.3 failed").

## Button legend

| Name | Physical control (Xbox layout) |
|---|---|
| LT / RT | Left / right trigger |
| LB / RB | Left / right bumper |
| A / B / X / Y | Face buttons |
| D-pad | Directional pad |
| BACK | View / Select button |
| START | Menu / Options button |
| L4 / L5 / R4 / R5 | Rear paddles (if your controller has them) |
| Trackpad 1–8 | Trackpad zones (Steam Deck / Steam Controller) |

**Bare** = pressed with no trigger or bumper held. **Tap** = press and release quickly.
`//xg …` commands are typed into Windower's console or the chat line.

## 1. Boot and lifecycle

SETUP: Windower running, not logged in to a character (title / character-select screen).

| # | Do | Expect | ✓ |
|---|----|--------|---|
| 1.1 | Load the addon before login: `//lua load xivgamepad` | Loads silently — no error, no HUD, no crash | ☐ |
| 1.2 | Log in | HUD appears: two cross-shaped slot clusters and a set label | ☐ |
| 1.3 | Read the set label | Shows the active set's name and mode, e.g. `Set 1 [job]` | ☐ |
| 1.4 | `//lua r xivgamepad` | Clean reload; HUD returns with the same set, positions, and icons | ☐ |
| 1.5 | Log out to character select | HUD hides; no errors | ☐ |
| 1.6 | Log back in on the same character | HUD returns; settings unchanged | ☐ |
| 1.7 | Switch to a second character | That character's own settings and hotbars load | ☐ |
| 1.8 | Switch back to the first character | Its settings are intact — nothing overwritten by the switch | ☐ |
| 1.9 | `//lua unload xivgamepad` | HUD disappears; keyboard `Ctrl`+`1` macros and `F9`–`F12` work natively again | ☐ |

RESET: `//lua load xivgamepad`, log in.

## 2. Key-Capture Wizard

SETUP: Logged in, safe area, chat closed, no menu open. For 2.1, use a fresh install (or unload
and delete `data/<Character>/settings.json` first).

| # | Do | Expect | ✓ |
|---|----|--------|---|
| 2.1 | Log in on a fresh install | Wizard opens by itself with a chat notice and the prompt `Step 1/26: press LT` | ☐ |
| 2.2 | `//xg learn cancel` at the first-run wizard | Wizard closes; chat says the current mapping is kept | ☐ |
| 2.3 | Log out and back in | Wizard does not auto-open again | ☐ |
| 2.4 | `//xg learn` | Wizard reopens at step 1 | ☐ |
| 2.5 | `//xg learn skip` at the LT step | Refused: LT is required and cannot be skipped | ☐ |
| 2.6 | Press LT at the LT prompt | Captured; the prompt advances to RT | ☐ |
| 2.7 | Press LT again at the RT prompt | Rejected — the message names LT as that key's owner; the prompt stays on RT | ☐ |
| 2.8 | Capture RT, LB, RB, BACK, START, A, B, X, Y in turn | Each press advances exactly one step | ☐ |
| 2.9 | At the D-pad Up step, press D-pad Up with nothing held | Refused: the prompt asks you to hold LT, RT, or RB first | ☐ |
| 2.10 | Hold LT and press D-pad Up | Captured; the prompt advances | ☐ |
| 2.11 | `//xg learn back` | Returns to the previous button with its earlier key restored | ☐ |
| 2.12 | Re-capture through the remaining d-pad steps (trigger held) | All four d-pad directions captured | ☐ |
| 2.13 | At the L4 step (optional), `//xg learn skip` | Advances, keeping L4's current key | ☐ |
| 2.14 | Capture or skip the remaining optional steps to the end | Wizard closes; the mapping is saved | ☐ |
| 2.15 | `//lua r xivgamepad` | No wizard auto-open; every captured button still works | ☐ |
| 2.16 | `//xg learn`, re-capture LT to a different key, then `//xg learn cancel` | The old mapping is untouched — LT still works via its original key | ☐ |

RESET: if any capture was left wrong, `//xg learn` and re-capture (skip through the rest).

## 3. Display-mode transitions

SETUP: Field, chat closed, no menu. In config → Display, point the WXHB and Expanded views at
distinct sets/halves so each view is recognizable.

| # | Do | Expect | ✓ |
|---|----|--------|---|
| 3.1 | Hold LT | XHB-L: the active set's left half highlights; label shows `XHB-L` | ☐ |
| 3.2 | Release LT | Back to idle — highlight and mode label clear | ☐ |
| 3.3 | Hold RT | XHB-R: the right half, label `XHB-R` | ☐ |
| 3.4 | Hold LT, then also hold RT | Expanded LT→RT view: its configured set and half | ☐ |
| 3.5 | Release RT (keep LT) | Back to XHB-L | ☐ |
| 3.6 | Release all; hold RT, then also hold LT | Expanded RT→LT view | ☐ |
| 3.7 | Release RT (keep LT held) | Falls back to XHB-L — the remaining trigger's view | ☐ |
| 3.8 | Release all; double-tap LT and keep it held | WXHB-L: its configured set and half | ☐ |
| 3.9 | Release; double-tap RT and hold | WXHB-R | ☐ |
| 3.10 | Hold LT, then also hold the L4 paddle | WXHB-L (paddle path) | ☐ |
| 3.11 | Release L4 (keep LT) | Back to XHB-L | ☐ |
| 3.12 | Hold LT, release, and immediately re-hold within the double-tap window | WXHB-L engages — a rapid release-rehold *is* the double-tap | ☐ |
| 3.13 | Release all buttons | Idle: no view active, mode label cleared | ☐ |

RESET: release all buttons.

## 4. Slot addressing and execution

SETUP: Using the Binder, put distinct recognizable actions in the active set's left slots and
right slots, and one in the WXHB-L view's half; leave at least one slot empty. Field, chat closed.

| # | Do | Expect | ✓ |
|---|----|--------|---|
| 4.1 | Hold LT, press D-pad Up | The action shown at the top of the left d-pad cluster fires | ☐ |
| 4.2 | Hold LT, press A | The action in the A position (bottom of the face cluster) fires | ☐ |
| 4.3 | Hold LT, press each remaining button (d-pad right/down/left, B, X, Y) | Each fires exactly the action its on-screen slot shows | ☐ |
| 4.4 | Hold RT, press D-pad Up | The **right** half's d-pad-up action fires — not the left half's | ☐ |
| 4.5 | Hold LT, press a button over an empty slot | Nothing happens; no error | ☐ |
| 4.6 | Hold LT and keep a bound face button held down | The action fires once — it does not repeat while held | ☐ |
| 4.7 | Double-tap-hold LT, press D-pad Up | The WXHB-L view's own slot fires (matches its icon) | ☐ |
| 4.8 | Hold LT+RT, press a face button | The Expanded view's slot fires | ☐ |

RESET: release all buttons.

## 5. Input and synthesis

SETUP: Field, chat closed, no menu open, at least one slot bound under each trigger.

| # | Do | Expect | ✓ |
|---|----|--------|---|
| 5.1 | Hold RT, press a bound face button | The slot fires; **no chat bar opens and no characters are typed** | ☐ |
| 5.2 | Hold LT and RT together, release RT, then press a face button | LT still works — the left slot fires (releasing one held control never breaks another) | ☐ |
| 5.3 | Bare A | Acts like the Enter key — opens the chat entry line (or confirms the highlighted choice) | ☐ |
| 5.4 | Bare B | Acts like Escape — the chat line / menu backs out | ☐ |
| 5.5 | Bare X | The map opens | ☐ |
| 5.6 | Bare Y | Your character jumps | ☐ |
| 5.7 | Bare START | The main menu opens | ☐ |
| 5.8 | Bare BACK (with two game windows open) | The active window focus switches (same as numpad `+`) | ☐ |
| 5.9 | Open the main menu; hold LT and press a bound face button | The slot does **not** fire while the menu is open | ☐ |
| 5.10 | With the menu still open, use bare A and bare B | They confirm and cancel inside the menu normally | ☐ |
| 5.11 | Open chat with bare A, then hold LT and press a bound face button | The slot does **not** fire (a number may appear in the chat line — expected, the keys are real) | ☐ |
| 5.12 | Bare B with the chat line open | Chat line closes; trigger + face fires slots again | ☐ |
| 5.13 | In config → Gestures, bind a spare control (e.g. tap L5) to `inventory`, save, press it | The **Inventory** menu opens (synthesized Ctrl+I) | ☐ |
| 5.14 | Bind another spare control to `equipment` and press it | The **Equipment** menu opens (synthesized Ctrl+E) | ☐ |
| 5.15 | On the physical keyboard, press Ctrl+1 while the addon is loaded | No macro fires — the macro palette is neutralized while loaded | ☐ |
| 5.16 | Start a cutscene (talk to an event NPC) | The HUD hides and all addon gestures stop | ☐ |
| 5.17 | During the cutscene, press A / B / d-pad | Native controller input advances the scene normally; nothing double-fires | ☐ |
| 5.18 | Let the cutscene end | HUD returns; gestures work again | ☐ |
| 5.19 | `//xg test`, then press buttons and make gestures | Tester overlay shows a live button grid and a gesture log; slot actions do **not** fire | ☐ |
| 5.20 | `//xg test` again | Tester closes; slot execution works again | ☐ |

RESET: close menus and chat; remove the temporary gestures (config → Gestures) if unwanted.

## 6. Native pass-throughs

SETUP: In a party (ideally an alliance) in the field; chat and menus closed.

| # | Do | Expect | ✓ |
|---|----|--------|---|
| 6.1 | Bare d-pad up/down | Party member selection cycles natively | ☐ |
| 6.2 | In an alliance, keep pressing the bare d-pad | Alliance members are selectable too | ☐ |
| 6.3 | Hold LT and press a d-pad direction | The hotbar slot fires and the selected party target does **not** change | ☐ |
| 6.4 | Hold RT and press a d-pad direction | Same — slot only, no native target change | ☐ |
| 6.5 | Hold RB and press a d-pad direction | The set switches (block 7) and the native target does **not** change | ☐ |
| 6.6 | Move the right stick | Camera pans natively (smooth analog) | ☐ |
| 6.7 | With no trigger held, hold LB and push the right stick up / down | Camera zooms in / out — and does **not** pan vertically while zooming | ☐ |
| 6.8 | Release LB and move the right stick | Back to normal camera pan | ☐ |
| 6.9 | Move the left stick | Character moves, with analog walking/running speed | ☐ |

If the target **also** changes in 6.3–6.5, your Steam d-pad chord is stacking on the base d-pad —
re-create it with "replace base" per the [profile page](wiki/Steam-Input-Profile.md).

RESET: release all buttons.

## 7. Mode, cycling, and direct switch

SETUP: Configure sets so the job pool has two non-empty cycling sets, one skip-marked set, and one
empty set; the shared pool has at least two non-empty cycling sets. Start in job mode.

| # | Do | Expect | ✓ |
|---|----|--------|---|
| 7.1 | Tap RB (bare) | The label changes to the next non-empty, non-skip job set | ☐ |
| 7.2 | Keep tapping RB through a full rotation | The skip-marked set never appears | ☐ |
| 7.3 | Keep tapping RB | The empty set never appears | ☐ |
| 7.4 | Hold LB, press RB (no trigger held) | Mode switches to shared — label shows `[shared]` and the active set jumps to that pool's first usable set | ☐ |
| 7.5 | Tap RB | Cycling now walks only shared sets | ☐ |
| 7.6 | Hold RB and press Y | Jumps directly to set position 1, even though it is a job set | ☐ |
| 7.7 | Tap RB after the direct switch | Cycling resumes in the **shared** pool — the direct jump did not change mode | ☐ |
| 7.8 | Hold RB and press B, A, X, then D-pad Up, Right, Down, Left | Jumps to set positions 2–8 respectively (faces are sets 1–4, d-pad 5–8) | ☐ |
| 7.9 | Mount up, then hold LB and press RB | You **dismount**; mode does not switch | ☐ |
| 7.10 | On foot, hold LB and press RB | Mode switches normally again | ☐ |
| 7.11 | Hold RB (no trigger) | The set-selector overlay appears: d-pad + face clusters numbered 1–8 (Y=1 … D-pad Left=8) with the active set's number highlighted | ☐ |
| 7.12 | Still holding RB, press B | The highlight moves to set 2 as the set switches | ☐ |
| 7.13 | Still holding RB, press and hold LT | The overlay hides immediately; release LT (RB still held) and it reappears | ☐ |
| 7.14 | Release RB | The overlay disappears immediately | ☐ |
| 7.15 | Hold LT, then press RB | No overlay (trigger-held RB is target-next); the target cycles instead | ☐ |

RESET: switch back to your preferred mode; release all buttons.

## 8. Targeting and taps

SETUP: Field with several targetable NPCs or mobs nearby; chat and menus closed.

| # | Do | Expect | ✓ |
|---|----|--------|---|
| 8.1 | Hold LT and press RB | The **next** target is selected | ☐ |
| 8.2 | Press RB repeatedly (LT held) | Selection keeps cycling forward through nearby targets (this verifies the synthesized Tab key actually cycles) | ☐ |
| 8.3 | Hold LT and press LB | The **previous** target — cycling runs opposite to RB (verifies synthesized Shift+Tab) | ☐ |
| 8.4 | Hold RT instead and press LB / RB | Same previous / next targeting | ☐ |
| 8.5 | While the trigger is held, watch the set label as you press RB | The set does **not** cycle and auto-run does **not** start — targeting always wins while a trigger is held | ☐ |
| 8.6 | Bare LB tap | Auto-run starts; tap again and it stops (verifies the `/autorun` command exists and toggles — if nothing happens, report it: the fix is a key-synthesis fallback) | ☐ |
| 8.7 | Bare RB tap | The set cycles; the target does not change | ☐ |
| 8.8 | Hold LB well past a tap and release it (no RB press) | Nothing happens — a long hold is not a tap | ☐ |

RESET: stop auto-run; clear your target.

## 9. Overlay resolution

SETUP: On SCH (main or sub). In the Binder, give one slot a base binding plus two overlays ordered
**Addendum: White first, Light Arts second**; give another slot a **Subjob** overlay captured with
your current subjob. Field, chat closed.

| # | Do | Expect | ✓ |
|---|----|--------|---|
| 9.1 | Activate Light Arts | The slot's icon swaps to the Light Arts overlay binding within about a second — no reload needed | ☐ |
| 9.2 | Cancel Light Arts | The slot returns to its base binding | ☐ |
| 9.3 | Activate Light Arts, then Addendum: White | The slot shows the **Addendum** binding — it is listed first, and the first matching overlay wins | ☐ |
| 9.4 | Let Addendum drop, keeping Light Arts | The slot falls back to the Light Arts overlay | ☐ |
| 9.5 | In the Binder, reorder so Light Arts is first; re-activate both | The slot now shows **Light Arts** even while Addendum is active — ordering decides | ☐ |
| 9.6 | Change your subjob at a Nomad Moogle | The subjob-conditioned slot switches on/off to match the new subjob | ☐ |
| 9.7 | With arts active, `//lua r xivgamepad` | Within about a second of reloading, the overlay is showing again (buffs already active are picked up) | ☐ |
| 9.8 | With arts active, zone to another area | Overlays still resolve correctly after the zone | ☐ |

RESET: restore your preferred overlay order in the Binder.

## 10. The Binder

SETUP: Field; chat and menus closed; a set with at least one empty and one occupied slot.

| # | Do | Expect | ✓ |
|---|----|--------|---|
| 10.1 | Hold LT (XHB-L showing) and press BACK | The Binder opens, listing the left half's 8 slots | ☐ |
| 10.2 | With the trigger held, press d-pad down / right | The selection moves down the list | ☐ |
| 10.3 | Press d-pad up / left | The selection moves back up, stopping at the ends | ☐ |
| 10.4 | Release the trigger | Status line shows `PAUSED`; buttons do nothing; the Binder stays open | ☐ |
| 10.5 | Hold LT or RT again | Navigation resumes | ☐ |
| 10.6 | Select an empty slot, press A | The binding type menu opens (Magic, Job Ability, Weapon Skill, …) | ☐ |
| 10.7 | Choose Magic | The skill categories list appears (Healing, Enhancing, … Trust) | ☐ |
| 10.8 | Choose a category, then a spell | The target menu appears: `<t>` `<me>` `<st>` `<stnpc>` `<bt>` | ☐ |
| 10.9 | Choose a target, press A on Confirm | The binding is written; back at the slot list, the slot shows it | ☐ |
| 10.10 | Press B inside any sub-menu | Backs up exactly one level | ☐ |
| 10.11 | Select an occupied slot | Slot menu: Overlay / Replace / Remove / Swap / Reorder Overlays | ☐ |
| 10.12 | Choose Overlay | The type list is filtered to what applies to you now (arts types only on SCH; Subjob only with a subjob set) | ☐ |
| 10.13 | Add an overlay choosing `Empty (noop)` | It confirms directly (no action/target step); while its condition holds, the slot renders empty and does nothing | ☐ |
| 10.14 | On a slot with overlays, choose Replace and bind something new | The base **and every overlay** are gone; only the new binding remains | ☐ |
| 10.15 | Choose Remove on a slot | The slot empties immediately | ☐ |
| 10.16 | Choose Swap and pick another slot | The two bindings exchange places | ☐ |
| 10.17 | Choose Reorder Overlays: A to grab, d-pad to move, A to drop | The overlay order changes and sticks | ☐ |
| 10.18 | Grab an overlay, move it, then press B | The working order is discarded — back to the pre-grab order | ☐ |
| 10.19 | Bind a Raw Command slot | The preset list appears (Rest, Sit, Check, Lock On); executing the slot later fires the chosen command | ☐ |
| 10.20 | With a trigger held, press BACK | The Binder closes; normal slot execution works again | ☐ |
| 10.21 | Bare d-pad with the Binder closed | Party targeting works as usual (unaffected by the Binder session) | ☐ |
| 10.22 | Hold RT (XHB-R) and open the Binder | It targets the **right** half's 8 slots | ☐ |
| 10.23 | `//lua r xivgamepad` | All Binder edits survive the reload | ☐ |

RESET: close the Binder; undo any throwaway bindings.

## 11. HUD visuals

SETUP: Bind a spell with a noticeable recast; if your data marks anything unusable or carries a
count, have those slots visible too. Config closed.

| # | Do | Expect | ✓ |
|---|----|--------|---|
| 11.1 | Cast the bound spell | Its slot animates a circular clock-sweep that empties as the recast runs down | ☐ |
| 11.2 | Wait out the recast | The sweep disappears; the icon returns to normal | ☐ |
| 11.3 | View a slot whose binding is marked unusable | Its icon is faded and shows an indicator | ☐ |
| 11.4 | Hover the mouse over a bound slot | A tooltip shows the action's name and type (plus MP / recast where relevant) | ☐ |
| 11.5 | In config → Display, set the three transparencies apart (e.g. 20 / 0 / 80) and save | The idle HUD draws at the *standard* value | ☐ |
| 11.6 | Hold LT | The displayed half draws at the *active* value, the other half at *inactive* | ☐ |
| 11.7 | Set *inactive* back to 100 and hold a trigger | The non-displayed half disappears entirely | ☐ |
| 11.8 | Turn on hide-empty-slots and save | Empty slot frames vanish; the bound slots keep their exact positions | ☐ |
| 11.9 | View a slot whose binding data carries a count | A numeric badge shows in the slot's lower-right corner | ☐ |

RESET: restore your preferred transparency / hide-empty settings.

## 12. Config GUI and commands

SETUP: Logged in, field; config closed.

| # | Do | Expect | ✓ |
|---|----|--------|---|
| 12.1 | `//xg config` | The window opens with Sets / Display / Keys / Gestures tabs and Save / Discard footer buttons | ☐ |
| 12.2 | `//xg config` again while open | Nothing happens — no second window, no reset | ☐ |
| 12.3 | Run the game at 1280×720 and open config | The whole window — **including the footer buttons** — is on screen | ☐ |
| 12.4 | Click on and around the open window | No click reaches the game behind it (no target change, no movement) | ☐ |
| 12.5 | Drag each HUD element (left half, right half, label) | Each moves independently while config is open | ☐ |
| 12.6 | Sets tab: click the left half of a set's row | Its source toggles between `job` and `shared` | ☐ |
| 12.7 | Sets tab: click the right half of a set's row | Its `[cycle]` / `[skip]` flag toggles | ☐ |
| 12.8 | Display tab: click the left, then right half of a view's row | Left cycles the assigned set 1–8; right flips the half | ☐ |
| 12.9 | Display tab: click the `hide_empty_slots` row | The value toggles | ☐ |
| 12.10 | Display tab: click left / right on a transparency row | The value steps down / up by 10, staying within 0–100 | ☐ |
| 12.11 | Open the Keys tab | Every button is listed with its captured key code; unmapped buttons say `(unmapped)` | ☐ |
| 12.12 | Click `[ Capture / Re-learn key mapping ]` | The Key-Capture Wizard opens | ☐ |
| 12.13 | Gestures tab: click the `[x]` at the start of a gesture row | That gesture is removed from the list | ☐ |
| 12.14 | Click the `type=` and `btn=` values on a gesture's first line | Each click cycles to the next value | ☐ |
| 12.15 | Click the `ctx=` and `act=` values on the second line | Each cycles its value | ☐ |
| 12.16 | Click the `-` and `+` around the timing value | The value steps down / up by 0.05 | ☐ |
| 12.17 | Click precisely **on** each field label (`type=`, `btn=`, `ctx=`, `act=`) across several rows | Every click edits the field you clicked — never its neighbor (click zones line up with your actual font rendering) | ☐ |
| 12.18 | Find the gesture with the longest action name and read its second line | The whole line — context, action, and `- value +` — fits inside the window body, nothing cut off | ☐ |
| 12.19 | Click `[+ add gesture]` | A new `custom_N` entry appears, ready to be cycled into shape | ☐ |
| 12.20 | Scroll a tall tab with the mouse wheel | Rows scroll; clicks still land on the row you clicked | ☐ |
| 12.21 | Make several changes and click **Save** | The window closes; the changes are live and still there after `//lua r xivgamepad` | ☐ |
| 12.22 | Reopen config, change things and drag the HUD, click **Discard** | Everything reverts — including the dragged HUD positions | ☐ |
| 12.23 | `//xg save` and `//xg discard` typed while the window is open | Behave exactly like clicking the footer buttons | ☐ |
| 12.24 | Close config and try to drag the HUD | Dragging is disabled | ☐ |
| 12.25 | `//xg debugmode` | Chat says `debug mode on`; debug lines appear in chat **and** in `data/debug.log` | ☐ |
| 12.26 | `//xg debugmode` again | `debug mode off`; the file stops growing but keeps its content | ☐ |
| 12.27 | `//xg debugmode on`, then `//xg debugmode off` | The explicit forms set the state directly | ☐ |
| 12.28 | `//lua r xivgamepad`, then play normally | No debug lines — debug mode always resets to off | ☐ |
| 12.29 | `//xg help`, then an unknown command like `//xg bogus` | Both print the command list | ☐ |

RESET: close config; debug mode off.

## 13. Icons and generated resources

SETUP: Logged in. `//lua unload xivgamepad`, delete the `xivgamepad/data/generated/` folder (and
`xivgamepad/data/icons/` if present), then `//lua load xivgamepad`.

| # | Do | Expect | ✓ |
|---|----|--------|---|
| 13.1 | Load with `data/generated/` deleted | The addon loads and initializes — a brief pause while resources generate is normal; no errors | ☐ |
| 13.2 | Check `xivgamepad/data/generated/` on disk | `crossbar_spells.lua` and `crossbar_abilities.lua` exist | ☐ |
| 13.3 | Bind a spell (`ma`) slot and view the HUD | The slot shows the real game spell icon — not the generic fallback art | ☐ |
| 13.4 | Bind a job ability and a weapon skill | Each slot shows its real ability / weapon icon | ☐ |
| 13.5 | `//lua r xivgamepad` without touching the files | No regeneration pause; the same icons return (the MD5 freshness check passes and the files are reused) | ☐ |
| 13.6 | `//lua unload`, delete `data/generated/` again, `//lua load` | Both files regenerate and the real icons are back | ☐ |
| 13.7 | Bind an Item slot and view the HUD | On a standard install the slot shows the item's **real game icon**, extracted on first display, and `data/icons/items/<id>.bmp` appears on disk (a non-standard FFXI path or missing DATs falls back to the generic item art — cosmetic only) | ☐ |
| 13.8 | `//lua unload`, delete `xivgamepad/data/icons/`, `//lua load`, display the item slot again | Nothing breaks; the icon is **re-extracted** on that next display and the `.bmp` reappears — the cache is safe to delete at any time | ☐ |

RESET: none — the caches rebuild themselves.

## 14. Mount roulette

SETUP: On a character that owns at least two mounts (Mounts-category key items), somewhere
mounting is allowed. Field, chat and menus closed.

| # | Do | Expect | ✓ |
|---|----|--------|---|
| 14.1 | Open the Binder on an empty slot and choose the Mount type | The list shows **only the mounts you own**, alphabetically, with **Mount Roulette** as the final entry | ☐ |
| 14.2 | Select Mount Roulette, confirm | The binding is written; the slot shows the Mount Roulette binding | ☐ |
| 14.3 | Press the slot while on foot | A random mount from your owned list is summoned | ☐ |
| 14.4 | Press the slot while mounted | You dismount | ☐ |
| 14.5 | Repeat the mount / dismount cycle several times | The summoned mount varies across presses (random over owned mounts; repeats are possible) | ☐ |
| 14.6 | Obtain a new mount key item, then reopen the Binder's mount list | The new mount appears **without a reload** (the key-item update refreshes the owned list) | ☐ |
| 14.7 | In config → Gestures, add a gesture on a free control, cycle `act=` to `mount_roulette`, save, press it | Behaves exactly like the slot: random owned mount, or dismount if mounted | ☐ |

RESET: dismount; remove the throwaway binding and gesture if unwanted.

## 15. Skillchain display

SETUP: `skillchain_display` on (the default). A party member or trust able to open a two-step
skillchain, a target to chain on, and a bound weapon skill that can close a known chain (plus, if
available, a weapon skill released after ~2017). Field, chat closed.

| # | Do | Expect | ✓ |
|---|----|--------|---|
| 15.1 | Land the opening weapon skill of a two-step chain | The skillchain timer appears in red: `Wait n.n`, counting down | ☐ |
| 15.2 | Wait out the delay | The timer turns green: `Go! n.n` | ☐ |
| 15.3 | During `Go!`, look at the hotbar halves | Every WS / JA / pet slot that would continue the chain on your current target shows a property-icon highlight — the icon is the chain that would **result** | ☐ |
| 15.4 | Close the chain with a highlighted weapon skill during `Go!` | The skillchain fires in-game; the display moves on to the new resonance | ☐ |
| 15.5 | Open a chain and let the window expire instead | The timer hides and every highlight clears | ☐ |
| 15.6 | Cast a nuke during a `Go!` window | No burst indicator — magic bursts are not shown, and spell slots never highlight | ☐ |
| 15.7 | On BST (a Ready-move pet slot) or SMN (a Blood Pact slot), open a chain it could continue | The pet slot highlights exactly like a weapon-skill slot | ☐ |
| 15.8 | Mid-chain, open config → Display, toggle `skillchain_display` off, save | The timer and every highlight disappear immediately | ☐ |
| 15.9 | Toggle it back on, save, and make a fresh chain | The display returns without a reload (the tracker re-seeds on the save) | ☐ |
| 15.10 | Open config, drag the skillchain timer somewhere new (easiest while a chain is live), save, `//lua r xivgamepad` | The timer keeps its new position | ☐ |
| 15.11 | Try to continue a chain with a weapon skill released after ~2017 | Its slot never highlights — the ported chain data predates it (documented limitation, not a bug; the WS itself still works) | ☐ |

RESET: restore `skillchain_display` and the timer position to taste.
