# Cheats on a tap menu, not on the control buttons

A design note from the Xash3D FWGS iOS port (Half-Life, Opposing Force, Blue
Shift), written to be reused in the owner's other iOS game ports. The first
part is the design and why; the second is how it was built here, with the
mistakes to avoid.

## The problem

The first version put the cheat's extra switches on the game's own control
buttons: while the cheat was on, **holding JUMP** still for half a second
switched **noclip**, **holding USE** switched **notarget**, and a **double tap
of JUMP** ended noclip ("land"). Small NOCLIP / NOTARGET labels sat under
JUMP and USE.

In play this went wrong all the time. JUMP and USE are pressed constantly,
often held, so noclip and notarget switched on by accident in the middle of
fights and puzzles. A control button should only ever do its one game job.

## The design

One cheat button (**λ** here) carries everything, with two gestures:

| Gesture on λ | Does |
|---|---|
| **Long press** (0.5 s, a ring fills round the button) | The main cheat on or off: god mode, all weapons, endless ammo (full magazines, so no reloading). The button glows gold while it's on. |
| **Tap** | Opens the **cheat menu**, whether the main cheat is on or off. |

The cheat menu:

- A small panel under λ, one row per switch: **Noclip** (fly through walls),
  **Notarget** (enemies ignore you), **Slow motion** (half speed), **Low
  gravity** (a quarter). Each row has its name, a short line saying what it
  does, and ON / OFF.
- **A tap on a row switches it** and the menu stays open, so several can be
  set at once. A row that's on is gold.
- **A tap anywhere off the menu closes it**, and does nothing else (it
  doesn't also fire, jump or look).
- **The game pauses while the menu is open** (single player).
- **The menu's switches are independent of the main cheat.** Turning god mode
  off leaves noclip and the rest as they are, and the menu works without god
  mode. They're separate wants: someone may want to fly around without being
  invincible.
- **They all end at each new level** (and on loading a save), as flying does
  in the owner's other ports, so nobody is stuck in noclip without knowing it.
- **Nothing stays on with no button to turn it off.** The cheat button itself
  is hidden until the player turns it on in the settings tray (CHEAT); hiding
  it again turns every switch off.
- **Single player only.** In multiplayer the menu doesn't open.
- **No status label.** We tried a small gold "NOCLIP · SLOW-MO" label under
  λ; the owner didn't want it. The rows show what's on when the menu is open,
  and the game makes the rest obvious.
- **No reminder toasts.** A tap of λ never pops "long press to turn cheats
  on"; the release notes explain the gestures.

What stays elsewhere: the **chapter / level select** keeps its own place in
the settings tray. It's a different kind of thing (a list you pick from once,
not a switch) and it only appears while the main cheat is on.

### Rules to carry to another port

1. Never put a cheat (or any second job) on a control button the game uses.
2. One cheat button: **long press** for the main cheat, **tap** for the menu.
3. The menu's switches are separate from the main cheat, all end at a level
   change, and all end when the cheat button is hidden.
4. The menu pauses the game, stays open for several taps, and closes on any
   touch outside it without passing that touch to the game.
5. No status labels or reminder toasts unless the owner asks.
6. Endless ammo means **full magazines** (no reloading), not only full
   reserves.

## How it was built here

The files are in `engine/platform/ios/` of this repository.

- **`ios_touch.m`** (the touch overlay, UIKit): λ is a `KIND_CHEAT` button
  with a 0.5 s hold. In `updateHolds` a finished hold calls `setCheat:`; in
  `endTouch:` a release before the hold finished (`tap`) opens the menu,
  after the touch is let go. The menu is `cheat_panel`, built on first use
  like the chapter list: blurred dark glass, gold border, a `UIButton` per
  row. While it's open, `touchesBegan` closes it on any touch that isn't on a
  row and marks that touch ignored. It closes itself if the game stops being
  single player or λ is hidden.
- **`ios_cheats.c`** (engine side): each switch acts directly on the local
  server, with exact on and off values rather than console toggles:
  - noclip: the player's `movetype` (`MOVETYPE_NOCLIP`, back to walking only
    if it's still noclip);
  - notarget: the `FL_NOTARGET` flag;
  - slow motion: `sys_timescale` 0.5, restoring the value it replaced;
  - low gravity: `sv_gravity` 200.

  `IOS_CheatFrame` ends all four when `cl.servercount` changes (a new level
  or a loaded save). Gravity isn't restored there because each level's world
  sets its own. `IOS_CheatExtrasOff` ends them when λ is hidden.
- **Endless ammo is in the game's code**, which the engine can't see into.
  `scripts/ios/patch_hlsdk.sh` adds a few lines to `CBasePlayer::ItemPostFrame`
  in each game's `dlls/player.cpp` at build time (`scripts/ios/build_trilogy.sh`
  calls it after cloning each hlsdk branch). While the engine's
  `ios_cheat_ammo` cvar is 1, in single player, every weapon's magazine is
  set to its maximum, and its spare ammo too, at the start of each frame's
  weapon think, before a weapon could decide to reload. The patch fails the
  build loudly if upstream code moves, and leaves the game branches as
  upstream has them (easy to rebase).

### Mistakes to avoid (they happened)

- **`viewWithTag:` checks the view itself first.** The rows were `UIButton`s
  tagged with their index (0–3) and their labels were tagged 1 and 2, so
  `[row viewWithTag:1]` on row 1 returned the button, not its label. Setting a
  label property on it threw an Objective-C exception and crashed the app the
  first time the menu opened. Give subview tags values no parent can have
  (here 101 and 102), or keep direct references to the labels.
- **Keep the switches out of the main cheat's off path.** The first version
  turned noclip etc. off with god mode and refused them without it, which
  made the menu useless on its own.
- **Read the crash log before guessing.** The engine writes a symbolised
  backtrace to `engine.log` in the app's Documents folder (Files app → On My
  iPhone → the app). The recording made it look like the ammo code; the log
  pointed straight at `-[IOSTouchOverlay updateCheatMenu]`.

## Where it's described for players

- `Documentation/ios-release-notes.md`, section *The cheat*.
- `Documentation/ios-port.md`, the *Cheat* entry.
