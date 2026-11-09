# iOS port: Half-Life, Opposing Force, Blue Shift and Counter-Strike

One app (shown as "Half-Life", bundle ID `com.sithewok.xash3d`, iOS 12 or newer) with
the engine and the game libraries for all three games, plus experimental extras:
Half-Life co-op, Counter-Strike and Multiplayer Modes. No game data is bundled. The
IPA is `Xash3D-iOS-unsigned.ipa`. Releases and the player's guide:
https://github.com/sithewok13-dev/xash3d-fwgs/releases (release text:
[ios-release-notes.md](ios-release-notes.md)).

## Installing the game data

1. On a computer with Steam, open `steamapps/common/Half-Life`.
2. Copy the `valve` folder, and `gearbox` (Opposing Force), `bshift` (Blue Shift) and
   `cstrike` (Counter-Strike) if you own them, into the app's folder: Files › On My
   iPhone › Half-Life. AirDrop to Files, iCloud Drive, a USB drive or Finder's file
   sharing all work. Copying the whole `Half-Life` folder is fine too; the launcher
   finds the games one level down. Multiplayer Modes also need the `ag` folder from the
   free Adrenaline Gamer mod (AG 6.6 on ModDB, or OpenAG's full package).
   Counter-Strike's bots and Training need more of your own files, in `cstrike`:
   see "Counter-Strike 1.6" below.
3. Open the app. The launcher ("Choose a game") marks each game Ready or says which
   folder is missing. Opposing Force, Blue Shift, Counter-Strike and Multiplayer Modes
   also need `valve`. Its first launch writes `Copy game folders here.txt` into the
   folder.

Xash3D FWGS supports data from after Steam's 25th anniversary update (2023); the
launcher says when it sees it (by the `hldemo1` map), and its Uplink chapter then also
shows in LEVEL. Not yet tried on a device with real data. Each game's server library is
picked by name (`-dll @hl`, `@opfor`, `@bshift`), so a `liblist.gam` from any Steam
release loads the right one.

Saves are in each game's `save` folder (e.g. `valve/save`). `engine.log`,
`xash-trace.txt` and `xash-trace-previous.txt` are written to the app's folder.

## Launcher

- Tap a ready game to play it. Hold Half-Life (0.5 s) for co-op (host a chapter, up
  to 4 players, or join), or Multiplayer Modes to pick a mode. Options: extra engine
  command line.
- One game per launch: GAMES in MENU's tray opens "Switch game"; picking one ends the
  game (unsaved progress is lost) and closes the app, and the pick starts at the next
  launch (its notification, or opening the app within 10 minutes). Cancel goes back
  to the paused game.
- The footer shows the addresses friends join this device at (Wi-Fi, Tailscale).

## Controls

The same touch controls as the OpenJKDF2 (Jedi Knight) and Serious Sam iOS ports:

- **Move:** stick where the left thumb lands. It walks; push it up onto the `^^` marker
  to run (or RUN in the tray: always run). Dead zone 0.30.
- **Look:** drag anywhere else. A drag that starts on FIRE, ALT, DUCK, USE, JUMP or
  RELOAD also looks.
- **Buttons:** FIRE with DUCK, USE and JUMP around it, plus ALT (secondary fire) and
  RELOAD. Top row: NEXT WPN, LIGHT (flashlight; Opposing Force's night vision), the
  camera (middle), the cheat's λ (once CHEAT is on), QUICK SAVE and QUICK LOAD (hold
  0.3 s), MENU.
- **NEXT WPN:** tap = next weapon with ammo; a 10 pt slide opens the weapon wheel at
  once; a 0.3 s hold opens it to tap. One slice per weapon (HUD icon, ammo; no ammo
  faded), the bottom gap cancels, a haptic tick per slice, and a single player game
  holds still while it's open.
- **MENU:** tap opens the game menu. Hold 0.45 s for the tray: GYRO (tap OFF/on; hold
  for MODE TOUCH/ALWAYS and gyro speed 1/1.5/2/3x, default 1.5x), SENS (0.5, 0.75, 1,
  1.25, 1.5, 2x; hold for 1x), RUN, OPACITY (tap: a slider, 20-100% in 5% steps; hold:
  100%), FPS (tap shows/hides the counter; hold 0.45 s to switch 60 <-> 120 frames a
  second, default 60: the screen is asked for that rate and fps_max follows it), CAMERA (tap shows/hides the camera button; hold for CLEAN, HUD, HUD+BTNS,
  SELFIES 1/3/5, FREEZE), CHEAT, LEVEL, CTRL (NORMAL or SWAP sides), KEYS (console)
  and GAMES. Settings are remembered; the cheat starts off each launch. Under the tray,
  small and grey, the build stamp, e.g. `build 123 · Nov 9` (the CI run that built it
  and its date, UTC; `build dev` for a local build), also on the game picker. TAPS (touch debugging marks) is off the tray: console `ios_taps`.
- **Cheat:** the tray's CHEAT (shows the λ button and switches the cheat on; again,
  hides it and switches it off), or type `sithewok` in the console. Hold λ 0.5 s to
  switch it off or on; a tap does nothing. It gives god mode and all weapons. While
  it's on, hold JUMP still for noclip (double-tap JUMP to land), hold USE still for
  notarget (both end at each new level), and the tray shows LEVEL. Single player only.
- **LEVEL** (while the cheat is on): tap for the list of the game's chapters, numbered,
  each with its title and its first map, the one being played ticked. The game holds
  still while it's open. Tap a chapter to start it (with the suit and all weapons); the
  X or a tap off the list closes it. Or hold LEVEL to count through the chapters, then
  let go to start one.
- **Camera:**
  - Tap for a photo.
  - Hold for selfies.
  - Slide sideways for a burst.
  - Slide down for Action Freeze, a free camera.
  - Slide up for a cinematic burst.

  Photos go to Photos, or to Files › Screenshots if Photos access is off. Selfies and
  Action Freeze are single player only.

## Building

`.github/workflows/ios-trilogy.yml` runs `scripts/ios/build_trilogy.sh` on a GitHub
macOS runner. It builds the engine, then FWGS hlsdk-portable `master` (valve), `opfor`
(gearbox) and `bshift` (bshift) for iOS, and, as optional parts left out if they fail,
the fork's (sithewok13-dev/hlsdk-portable) `ios-ag` (ag) and `ios-coop` (hlcoop in
valve) and cs16-client with ReGameDLL_CS (cstrike). It writes
`artifacts/Xash3D-iOS-unsigned.ipa`. Pushes to `master` publish it as the `ios-latest`
prerelease for Sithewok-apps/ios-pipeline to sign; other branches keep it as a run
artifact.

Graphics: the `gles3compat` renderer on OpenGL ES 3.0 through ANGLE's Metal backend
(`engine/platform/ios/ios_angle.c`: an EGL surface on SDL's Metal view), not Apple's
deprecated OpenGL ES. The workflow's `angle` job builds ANGLE (`ANGLE_REV`, built for
iOS 18 and newer) and caches it; the IPA carries `libEGL.framework` and
`libGLESv2.framework` next to `SDL2.framework`. The engine opens them at run time:
when they can't load or start (an older iOS, no Metal), the `gles1` renderer draws on
Apple's OpenGL ES as before. `-ref gles1` in the launcher's command line picks that on
purpose. `engine.log` says which runs (`Video: ...`, `ANGLE: ...`), and every 5 s of
play logs a frame-time line (`ios_perf.c`): `iOS: frames 120.0 fps; per frame 6.1 ms
(worst 9.0): game 2.0, drawing 3.5, present 0.6; ANGLE (Metal)` (game = the engine's
own work, drawing = the renderer handing the GPU its work, present = the swap, which
waits when the GPU or the screen is behind).

Numbered releases: a manual run of master with `release=<tag>`
(`gh workflow run ios-trilogy.yml --ref master -f release=ios-v0.1-beta1`, or the REST
call `POST repos/sithewok13-dev/xash3d-fwgs/actions/workflows/ios-trilogy.yml/dispatches`
with `ref` and `inputs[release]`). The tag must look like `ios-v*` and not already be on
another commit, and `Documentation/ios-release-notes.md` must contain the exact line
`### What's in <tag>`. The release is created at the built commit with those notes as
its text; a `-` in the version makes a prerelease that isn't marked latest. A release
run leaves `ios-latest` alone.

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

The IPA ships only cs16-client's own touch layouts, icons and settings, as
`cstrike/extras.pk3`, built by `build_trilogy.sh` from parts of
`3rdparty/cs16client-extras`. cs16-client's full extras.pk3 is not shipped: it
also holds Valve's files (training maps, bot databases and voices,
Counter-Strike's menu art and text, launcher sounds) and YaPB's files (YaPB
isn't built). Counter-Strike's menus use the engine's own menu art
(`valve/extras.pk3`) instead. Players copy the rest from their own games into
their `cstrike` folder, which the engine searches after the app's own
`cstrike` (`FS_AddGameHierarchy`: the read-only app folder, then Documents):

- Bots (ReGameDLL_CS, allowed on a listen server by `UTIL_AreBotsAllowed`):
  `BotProfile.db` (loaded with the engine's `LOAD_FILE_FOR_ME`; without it
  `bot_add` finds no profile and no bot joins), `BotChatter.db` (without it
  bots don't talk) and `sound/radio/bot/*.wav` (a chatter line is only used
  if its file exists). From Counter-Strike: Condition Zero's `czero` folder,
  or a Counter-Strike copy that has them (ReGameDLL_CS's README describes
  adding them to CS 1.6).
- Training: the menu starts the `trainmap` named in the player's own
  `cstrike/liblist.gam`; it needs the maps `tr_1`, `tr_1a`, `tr_2`, `tr_3`
  and `sound/training`. Steam's copy may not have them.

`scripts/ios/check_no_game_data.py` runs in `ios-trilogy.yml` before the IPA
is uploaded or published: it opens the IPA and every .pk3/.zip in it and fails
on maps, sounds, models, sprites, WADs, PAKs or `.db` files, on any archive
other than `valve/extras.pk3` and `cstrike/extras.pk3`, and on anything in
`cstrike/extras.pk3` outside its touch and settings folders.

### Team Fortress Classic

Not possible for now: its game code was never released and there is no
open-source rewrite (FortressOne is the Quake version).
