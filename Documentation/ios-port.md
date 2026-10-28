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
  USE still for notarget, and the tray shows LEVEL. Single player only.
- **LEVEL** (while the cheat is on): tap for the list of the game's chapters, numbered,
  each with its title and its first map, the one being played ticked. The game holds
  still while it's open. Tap a chapter to start it (with the suit and all weapons); the
  X or a tap off the list closes it. Or hold LEVEL to count through the chapters, then
  let go to start one.
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

## Multiplayer plan

Decided: play with friends on the same Wi-Fi and over the internet
through Tailscale; all the classic modes plus the popular later ones; a
co-op mode; Counter-Strike 1.6 as a fourth game in the launcher; no bots
for now. Single player stays vanilla, and every multiplayer change must
be revertible.

Order:

1. Classic modes over Wi-Fi and Tailscale (Half-Life deathmatch and team
   deathmatch, Opposing Force deathmatch and CTF). The game's server
   browser adds servers by address and keeps favorites; the launcher
   shows the device's Wi-Fi and Tailscale addresses. LAN discovery
   (broadcast) on iOS 14+ needs Apple's multicast entitlement
   (com.apple.developer.networking.multicast), which changes the signing
   profile: until then, join by address. A phone host freezes the game
   for everyone when its app goes to the background; a Mac or PC on
   Tailscale can run a dedicated server instead.
2. Co-op.
3. The extra modes.
4. Counter-Strike.

How it stays revertible: extra modes live in their own game folder and
library, never in valve/gearbox/bshift; the build script builds them as
optional (HLSDK_OPTIONAL_GAMES, empty to drop them), and a mode that
fails to build is left out instead of failing the build.

### Extra modes

- Adrenaline Gamer (hlsdk-portable's aghl branch, game folder "ag"):
  free for all, team play, arena (1v1, winner stays), last man standing,
  instagib, CTF and domination on Half-Life maps, plus arcade and
  shotgun/crossbow. Needs AG's own data folder (flag model, settings).
- Still to add on top: Gun Game, low gravity (sv_gravity only),
  weapon-restricted deathmatch (crowbar only, snarks only...).

### Co-op

No co-op in hlsdk-portable. The best existing open-source base is
SevenKewp (github.com/wootguy/SevenKewp): a generic co-op mod faithful to
Half-Life, built for Sven Co-op maps, on halflife-updated (2021), under
the Half-Life SDK license. About 320 server source files, Windows-first
CMake. It hooks a custom ReHLDS only as a dedicated server; on a listen
server one helper (sprite lookups through ReHLDS) would crash and needs
a fallback. A port is big but would bring level changes with several
players, respawns and scripted scenes already handled. Alternative: our
own co-op on hlsdk-portable, chapter by chapter. Opposing Force and Blue
Shift co-op come after Half-Life's.

### Counter-Strike 1.6

As a module (a fourth launcher entry): it needs the valve folder too,
which a separate app would make you copy twice. Open-source client for
this engine (cs16-client, used on Android) and server (ReGameDLL_CS);
data from your Steam copy (cstrike). Its own touch layout: buy menu,
team/class choice, scoreboard; plant and defuse on USE; no LIGHT.

### Team Fortress Classic

Not possible for now: its game code was never released and there is no
open-source rewrite (FortressOne is the Quake version).
