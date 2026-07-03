# Controls and Gestures

Every gesture is resolved from *what is held* × *what is pressed*. "Bare" means no trigger or
bumper is held. All of these ship enabled; timing and bindings are editable on the
[Gestures tab](Configuration.md).

## The gesture table

| Input | Action |
|---|---|
| Hold LT | Show **XHB-L** — the current set's left 8 slots |
| Hold RT | Show **XHB-R** — the current set's right 8 slots |
| Hold LT + hold L4 / Hold RT + hold R4 | Show **WXHB-L / WXHB-R** (paddle path) |
| Double-tap LT / RT (and keep holding) | Show **WXHB-L / WXHB-R** (paddle-free alternative) |
| Hold LT, then also RT | Show **Expanded LT→RT** |
| Hold RT, then also LT | Show **Expanded RT→LT** |
| D-pad or face button while a trigger is held | Fire the displayed slot (d-pad = slots 1–4, faces = 5–8) |
| Tap LB (bare) | Toggle **auto-run** |
| Tap RB (bare) | **Cycle** to the next hotbar set |
| Hold LT or RT + press LB | Select the **previous target** |
| Hold LT or RT + press RB | Select the **next target** |
| Hold LB + press RB (bare) | **Switch mode** (shared/job) — **dismounts** instead when mounted |
| Hold RB + d-pad or face (bare) | **Jump directly** to set position 1–8 |
| BACK while a trigger is held (XHB shown) | Open / close the **Binder** |
| Hold LB + right stick up/down (bare) | Camera **zoom** (handled by Steam, not the addon) |
| Bare A | **Confirm** (acts like the Enter key) |
| Bare B | **Cancel** (acts like the Escape key) |
| Bare X | Open the **map** |
| Bare Y | **Jump** |
| Bare START | Open the **main menu** |
| Bare BACK | **Focus** the active window |

You can add your own gestures too — for example "tap L5 → open inventory" — on the
[Gestures tab](Configuration.md). Free hosts include the paddles, the trackpad zones, and any bare
button whose default you are willing to replace.

## Precedence — what wins when

- **While a trigger (LT or RT) is held, LB and RB always mean previous/next target.** Full stop.
  Auto-run, set cycling, mode switch, and direct-switch all require **no trigger held**, so a
  button press never means two things at once.
- The **d-pad is native targeting when bare** and addon input only while LT, RT, or RB is held.
  A bare d-pad gesture is therefore not possible — that's by design, so party and alliance
  targeting always work.
- **BACK is context-split:** bare BACK focuses the active window; BACK with a trigger held (while
  an XHB is shown) toggles the Binder. The two never collide.
- **Mode switch is anchored on LB** (hold LB, then press RB). The reverse — hold RB, then press
  LB — deliberately does nothing; it is free for you to bind.
- Face buttons are context-routed: bare = the menu/command gestures above; trigger held = fire the
  slot; Binder open = Binder navigation.

## What pauses, and when

| Situation | What still works | What is suspended |
|---|---|---|
| A game **menu** is open | Bare A / B / START / BACK (confirm, cancel, menu, focus) | Slot execution and field commands (map, jump, auto-run, …) |
| The **chat line** is open | Bare A / B / START / BACK — so B can dismiss the chat bar the controller opened | Slot execution and field commands. The mapped keys are real keys, so they type into the chat line; your physical keyboard types normally |
| A **cutscene / event** is running | Native controller input (advancing the scene) | Everything the addon does — the HUD hides and all gestures stop until the scene ends |
| The **Binder** is open | Binder navigation (see [Using the Binder](Using-the-Binder.md)) | Normal slot execution |
| The **Gamepad Tester** is open (`//xg test`) | Gestures are displayed in the tester's log | Gesture execution |

Next: [Hotbar Sets and Display Modes](Hotbar-Sets-and-Display-Modes.md).
