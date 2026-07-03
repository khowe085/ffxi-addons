# Skillchains and Mounts

Two quality-of-life features ported from the xivcrossbar addon lineage: a live skillchain display
on the hotbar, and a Mount Roulette binding. Both work out of the box — this page explains what
you are seeing and how to bind them.

## The skillchain display

When a skillchain is opened on your current target, two things appear:

- **The window timer** — a small text element that reads **`Wait n.n`** (red) while resonance is
  set but chaining now would misfire, then **`Go! n.n`** (green) counting down the open chain
  window. It hides itself when nothing is resonating.
- **Slot highlights** — while the window is open (`Go!`), every hotbar slot whose weapon skill,
  job ability, or pet command would **continue the active chain** on your current target shows an
  icon overlay. The icon is the skillchain property that would **result** (Fusion, Light,
  Darkness, …), so you can pick the follow-up by outcome.

Details worth knowing:

- Highlights follow your **current target** — the chain is tracked per enemy, and slots light up
  for the enemy you have targeted.
- Pet actions chain too: BST Ready moves and SMN Blood Pacts carry chain properties and highlight
  exactly like weapon skills.
- The timer is a normal HUD element: open `//xg config` and **drag it** wherever you like; the
  position saves with everything else (it only renders while a chain is live).

### Turning it off

The **Display tab** of `//xg config` has a `skillchain_display` toggle. Turning it off hides the
timer and every highlight immediately and stops the tracking; turning it back on mid-session works
without a reload.

### Limitations

- **The chain data dates from ~2017.** Weapon skills added to the game after that never highlight
  — using them still works, the display just cannot predict them. This is a known limitation of
  the ported data, not a bug.
- **Magic bursts are not shown.** The display only predicts chain *continuations*; spell slots
  never highlight and there is no burst-window indicator.

## Mount Roulette

The addon tracks which mounts you actually own by reading your **key items**, and keeps that list
current automatically — obtaining a new mount updates it on the spot, no reload needed.

### Binding it

In [the Binder](Using-the-Binder.md), choose the **Mount** type: the list shows only the mounts
you own, with a final **Mount Roulette** entry. Bind Mount Roulette to a slot and pressing it
will:

- **summon a random mount you own** when you are on foot, or
- **dismount** when you are already mounted.

So one slot covers mount up and mount down.

### Binding it to a gesture

Mount Roulette is also a system action (`mount_roulette`), so it does not need to occupy a hotbar
slot: in `//xg config` → **Gestures tab**, add a gesture on a free control and cycle its `act=`
field to `mount_roulette`. Pressing that control then behaves exactly like the slot —
random owned mount, or dismount.
