# iOS port: Half-Life, Opposing Force and Blue Shift

One app (shown as "Half-Life", bundle ID `com.sithewok.xash3d`) with the engine and
the game libraries for all three games. No game data is bundled.

## Installing the game data

1. On a computer with Steam, open `steamapps/common/Half-Life`.
2. Copy the `valve` folder, and `gearbox` (Opposing Force) and/or `bshift` (Blue Shift)
   if you own them, into the app's folder: Files › On My iPhone › Half-Life. AirDrop to
   Files, iCloud Drive, a USB drive or Finder's file sharing all work. Copying the whole
   `Half-Life` folder is fine too; the launcher finds the games one level down.
3. Open the app. The launcher marks each game Ready or says which folder is missing.
   Opposing Force and Blue Shift also need `valve`.

Xash3D FWGS supports data from after Steam's 25th anniversary update (2023); the
launcher says when it sees it (by the `hldemo1` map), and its Uplink chapter then also
shows in LEVEL. Not yet tried on a device with real data. Each game's server library is picked by name (`-dll @hl`, `@opfor`, `@bshift`),
so a `liblist.gam` from any Steam release loads the right one.

## Controls

The same touch controls as the OpenJKDF2 (Jedi Knight) and Serious Sam iOS ports:

- **Move:** stick where the left thumb lands. It walks; push it up onto the `^^` marker
  to run. Dead zone 0.30.
- **Look:** drag anywhere else. A drag that starts on FIRE, ALT, DUCK, USE, JUMP or
  RELOAD also looks.
- **Buttons:** FIRE with DUCK, USE and JUMP around it, plus ALT (secondary fire) and
  RELOAD. Top row: NEXT WPN, LIGHT, PHOTO, QUICK SAVE and QUICK LOAD (hold 0.3 s), MENU.
- **MENU:** tap opens the game menu. Hold 0.45 s for the tray: GYRO (hold for MODE and
  gyro SENS), SENS, FPS, CAMERA (hold for photo options), CHEAT, LEVEL, CONTROLS
  (NORMAL or SWAP sides) and KEYS (console).
- **Cheat:** the tray's CHEAT, or type `sithewok` in the console. It gives god mode and
  all weapons. While it's on, hold JUMP still for noclip (double-tap JUMP to land), hold
  USE still for notarget, and hold LEVEL to count through the chapters, then let go to
  start one. Single player only.
- **PHOTO:**
  - Tap for a photo.
  - Hold for selfies.
  - Slide sideways for a burst.
  - Slide down for Action Freeze, a free camera.
  - Slide up for a cinematic burst.

  Photos go to Photos, or to Files › Screenshots if Photos access is off.

## Building

`.github/workflows/ios-trilogy.yml` runs `scripts/ios/build_trilogy.sh` on a GitHub
macOS runner. It builds the engine, then hlsdk-portable `master` (valve), `opfor`
(gearbox) and `bshift` (bshift) for iOS, and writes `artifacts/Xash3D-iOS-unsigned.ipa`.
Pushes to `master` publish it as the `ios-latest` release for Sithewok-apps/ios-pipeline
to sign; other branches keep it as a run artifact.

The iOS code is in `engine/platform/ios` (launcher, touch overlay, cheats, photo mode).
The engine hooks are small and marked `#if XASH_IOS`, in `engine/client/input/input.c`,
`engine/client/cl_view.c` and `engine/client/client.h`.

## Ideas, not implemented

Possible additions to the cheat tray, all built into the engine or the
game libraries (no gameplay changes needed). On hold until decided.

- Long Jump Module: `give item_longjump`. Half-Life only; `impulse 101`
  doesn't include it.
- Slow motion: `sys_timescale` (e.g. 0.3), a switch; pairs with the photo
  mode.
- Low gravity: `sv_gravity` (800 normally), a switch.
- Spawn a soldier: `impulse 76`, a human grunt in front of the player.
- Remove what's under the crosshair: `impulse 203`, a way out when stuck
  on something or a scripted scene breaks.

Left out: infinite ammo (no built-in cheat; it would mean changing the
game libraries) and the debugging impulses (AI, textures, node graph).
