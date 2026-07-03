# Installation and Setup

Three things must be in place before the cross hotbar works: the addon itself, FFXI's own gamepad
configuration, and a Steam Input profile. Do them in this order.

## 1. Install the addon

1. Copy the `xivgamepad` folder (and the shared `lib` folder) into your Windower `addons/`
   directory.
2. Load it in-game with `//lua load xivgamepad`, or add `lua load xivgamepad` to Windower's
   `init.txt` so it loads automatically.
3. The addon is safe to load before you log in — it simply waits for the login.

## 2. Configure FFXI's gamepad settings

XIVGamepad runs as a **hybrid**: three controls stay native gamepad, everything else reaches the
addon as keyboard keys. FFXI's gamepad config must therefore own exactly three functions and
nothing more.

1. **Enable gamepad support** in FFXI's configuration, **alongside** keyboard input — both must be
   active at the same time. With the gamepad disabled, movement, camera, and d-pad targeting all
   break.
2. Assign **only** these three native functions:
   - **Left stick → character movement**
   - **Right stick → camera**
   - **D-pad → targeting** (party / alliance members and the menu cursor)
3. **Leave every other gamepad button blank / unassigned.** This matters: Steam Input remaps all
   the remaining buttons to keyboard keys the addon reads. If a button also carries a native FFXI
   gamepad action, a single press would **double-fire** — the native action *and* the addon's
   gesture at once.
4. Leave FFXI's **keyboard** bindings at their defaults for the number row and `F1`–`F8`. The
   number row does nothing in FFXI (which is exactly why the addon uses it), and `F1`–`F8` keep
   their native target-selection role. The addon itself neutralizes the `Ctrl`+number macro palette
   and `F9`–`F12` while it is loaded, and restores them when unloaded.

## 3. Set up the Steam Input profile

Follow the [Steam Input Profile](Steam-Input-Profile.md) page. In short: left stick, right stick,
and the bare d-pad pass through as a native gamepad; the triggers, bumpers, face buttons,
BACK/START, paddles, and trigger-held d-pad all emit keyboard keys; LB adds a hold-layer that turns
the right stick's vertical axis into camera zoom.

## 4. First login — the Key-Capture Wizard

The first time you log in, the addon opens the **Key-Capture Wizard** automatically (a chat notice
announces it). The wizard asks you to press each controller button once and records the key your
Steam profile emits, so the profile and the addon can never drift apart.

- The prompt walks the buttons in a fixed order: **LT, RT, LB, RB, BACK, START, A, B, X, Y**, then
  the four **d-pad** directions, then the optional **paddles and trackpad zones**.
- **D-pad steps need a held trigger.** The d-pad only emits keys while LT, RT, or RB is held (see
  the profile page), so the wizard asks you to hold one first — for example "Hold LT, then press
  D-pad Up".
- **A key can only belong to one button.** If a press matches a key captured earlier, the wizard
  refuses it and names the button that owns it.
- Wizard controls are typed commands:
  - `//xg learn skip` — skip the current **optional** button, keeping whatever key it already has.
    Required buttons cannot be skipped.
  - `//xg learn back` — step back one button and re-capture it.
  - `//xg learn cancel` — close the wizard without applying this session's captures.
- The wizard comes **pre-loaded with the shipped default mapping**, which matches the recommended
  Steam profile. If you built the profile exactly as documented, you can simply
  `//xg learn cancel` at the first prompt — that accepts the defaults, and the wizard stops
  auto-opening.
- Finishing the last step saves the mapping. Re-run it any time with `//xg learn` (or the
  **Capture / Re-learn** control on the [Keys tab](Configuration.md)); it pre-loads your current
  values so a single wrong button can be fixed without redoing everything.

## 5. Verify

Run `//xg test` to open the Gamepad Tester: press each button and watch the live grid light up,
and make a few gestures to see them named in the log. Run `//xg test` again to close it. Then work
through [Controls and Gestures](Controls-and-Gestures.md) to learn the layout.
