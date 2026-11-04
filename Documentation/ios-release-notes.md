<!--
  The GitHub release text for a release run of .github/workflows/ios-trilogy.yml:
  a manual run of branch master with "release" set to a tag such as ios-v0.1
  (gh workflow run ios-trilogy.yml --ref master -f release=ios-v0.1). The
  workflow publishes this file, as it is in the commit the run builds, as the
  release body. Update it before each release: the run stops before building
  unless this file has a "### What's in <tag>" heading line for that tag (for
  example "### What's in ios-v0.1"), written exactly like that and on a line
  of its own. A '-' in the version after "ios-" (ios-v0.1-beta1) makes a
  prerelease; without one (ios-v0.1) the release is marked as the latest
  release. Links must be absolute: relative links don't resolve on a release
  page. Keep each paragraph and list item on one line: a release page turns
  every line break into a visible one.
-->
**Xash3D FWGS for iOS v0.1-beta1**: an unofficial iPhone build of the Xash3D FWGS engine that plays *Half-Life*, *Half-Life: Opposing Force* and *Half-Life: Blue Shift*, with touch controls.

**You need your own copy of the games; no game files are included.** You copy the game folders from your Steam copy on a computer: Half-Life is needed for all of them, Opposing Force and Blue Shift are optional (each is its own purchase on Steam).

**One app for every game:** download `Xash3D-iOS-unsigned.ipa`; on your home screen it's called **Half-Life**. When it opens, you pick the game.

**Setup guide and developer notes:** https://github.com/sithewok13-dev/xash3d-fwgs/blob/HEAD/Documentation/ios-port.md

**New here?** *Known limitations*, *Requirements* and *Install* are near the bottom of this page, just above the download.

### What's in ios-v0.1-beta1

The first public test release. This is a **beta**: it has been played on one iPhone only, so expect rough edges.

- **Half-Life, Opposing Force and Blue Shift** in one app, picked on its *Choose a game* screen, which says for each game whether it's ready or which folder is missing.
- **Touch controls** in the same style as the owner's other iOS ports (Jedi Knight, Serious Sam): a move stick where your left thumb lands, drag to look, FIRE with DUCK, USE and JUMP around it, ALT fire and RELOAD, quick save and quick load, and a weapon wheel.
- **LIGHT**, the flashlight (in Opposing Force, the night vision).
- **Tilt aiming (gyro)**, off until you switch it on.
- **The camera:** photos, selfies, bursts, a cinematic burst and Action Freeze, a free camera around a frozen moment.
- **The cheat** (`sithewok`): god mode and all weapons, noclip, notarget, and LEVEL to jump to any chapter.
- **Experimental extras, with the least testing:** Half-Life co-op for up to 4 players, Counter-Strike (with your own Steam copy), and Multiplayer Modes (deathmatch variants, with the free Adrenaline Gamer mod's files). See *Playing with friends* below.

---

### How to play: every control explained

The touch controls appear while you're playing and hide in the menus, the console and while a level loads (there you just tap, as you'd click with a mouse). The game runs in landscape, either way round.

Where everything is (on a phone, turn it sideways to see the whole picture):

```
 NEXT  LIGHT          [camera]     λ       QUICK  QUICK  MENU
 WPN                                       SAVE   LOAD
   [GYRO] [SENS] [RUN] [OPACITY] [FPS] [CAMERA] [CHEAT] [LEVEL] [CTRL] [KEYS] [GAMES]
                           (MENU's tray, while it's open)
                                                            RELOAD
                                                     JUMP
                                                            ALT
                                              USE
    ( o )  move stick: appears
           where your left thumb lands   DUCK        FIRE
```

Exact positions shift a little to fit your screen; the buttons stay clear of the corners, the notch or Dynamic Island, and the home bar. The **λ** button only shows once you've switched the cheat on (see *The cheat*).

#### Moving and looking

- **Move:** put your left thumb down anywhere in the left part of the screen and the stick appears there. Pushed a little, you walk. Push it **up**, onto the small `^^` circle above the stick, to run (a haptic tick says you're running). To run all the time instead, turn on **RUN** in MENU's tray.
- **Look:** drag anywhere else on the screen. A drag that starts on FIRE, ALT, DUCK, USE, JUMP or RELOAD also looks, so you can shoot and aim with one thumb.

#### Buttons

- **FIRE** shoots, **ALT** is the weapon's secondary fire, **RELOAD** reloads. Hold them as long as you like.
- **JUMP**, **DUCK** (crouch) and **USE** (doors, buttons, health and suit chargers, scientists and guards) work while held, like the keys on a PC.
- **NEXT WPN** (top left): a tap switches straight to your next weapon that has ammo. For the weapon wheel, see below.
- **LIGHT:** a tap switches the flashlight on or off. In Opposing Force it's the night vision.

#### The weapon wheel (NEXT WPN)

- **Slide** your thumb from NEXT WPN (about 10 points is enough) and the wheel opens at once: slide towards a weapon and lift to take it.
- Or **hold** NEXT WPN for a third of a second: the wheel opens and stays open, and you tap a weapon.
- Each slice is a weapon you have, with its HUD icon. The middle shows the one you're pointing at, its name and its ammo (in the clip | in reserve). Weapons with no ammo are faded.
- The gap at the bottom of the wheel cancels. In single player the game holds still while the wheel is open. You feel a tick for each slice.

#### Quick save and quick load: why the short hold

**QUICK SAVE** makes a quick save and **QUICK LOAD** loads it. Both need you to **hold** the button for about a **third of a second**: a ring fills round it, then it happens. **Why the hold?** So a stray touch near the top of the screen can't save over your quick save, or throw away your progress by loading. Sliding your finger off the button before the ring is full cancels.

#### MENU and its hidden tray

**Tap MENU** for the game's menu (save, load, options, quit). **Hold MENU** until its ring fills (about half a second) and a row of small buttons, the tray, opens under the top row. Tap MENU again to close it. Under the tray, small and grey, is the app's version, for example `v1.0 (76)`, and the build's commit.

- **GYRO:** tilt aiming on or off (see below). **Hold GYRO** for its options.
- **SENS:** how fast a drag turns the view: each tap steps through 0.5x, 0.75x, 1x, 1.25x, 1.5x and 2x. **Hold SENS** for the default, 1x.
- **RUN:** always run (lit) or walk unless the stick is pushed up to `^^` (the default).
- **OPACITY:** a tap opens a slider under the tray to make the controls fainter, from 20% to 100% in 5% steps, live. **Hold OPACITY** for full strength again. The tray itself and the wheel stay at full strength.
- **FPS:** shows the frame rate.
- **CAMERA:** shows or hides the camera button. **Hold CAMERA** for its options (see *The camera*).
- **CHEAT:** switches the cheat on and shows its λ button; tapped again, the cheat goes off and the button goes away.
- **LEVEL** (only while the cheat is on, in single player): the chapter list, see *The cheat*.
- **CTRL:** NORMAL, or SWAP to mirror the FIRE cluster to the left of the screen.
- **KEYS:** opens the console, with the keyboard.
- **GAMES:** *Switch game*, to play another of the games (see *Menus, switching games and the console*).

All these settings are remembered, apart from the cheat itself, which starts off each time you open the app.

#### Tilt aiming (gyro)

Tap **GYRO** in the tray to switch tilt aiming on or off (it's **OFF** to start with). **Hold GYRO** for two more buttons: **MODE** chooses **TOUCH** (the gyro aims only while a thumb is on the move stick, the look area or one of the buttons you can look from; lift them all and the view stays put, so you can rest the phone) or **ALWAYS**; the second steps the gyro's speed through 1x, 1.5x (the default), 2x and 3x. Devices without a gyro don't show these buttons.

#### The camera: photos, selfies, bursts and Action Freeze

The **camera** button sits in the middle of the top row.

- **Tap** it for a photo.
- **Hold it still** for half a second for **selfies**: the camera turns round to face you, and characters near you pose too (3 photos to start with).
- **Slide sideways** for a **burst**: photos one after another while you hold it (up to 10).
- **Slide down** for **Action Freeze**: the game freezes and you move a free camera round the moment (one finger orbits, two move and zoom). Tap the camera button for photos, and **X** (top right) to go back to the game.
- **Slide up** for a **cinematic burst**: 5 photos from different camera angles.
- **Options:** hold **CAMERA** in the tray. **CLEAN** (just the scene), **HUD** (with the HUD) and **HUD+BTNS** (with the HUD and the touch buttons) choose which photos each shot makes (at least one stays on); **SELFIES** sets 1, 3 or 5 selfies; **FREEZE** turns Action Freeze on or off.
- Photos go to your **Photos** app (the app only asks to add photos, not to see yours). Without Photos access they go to the app's folder in Files, in *Screenshots*.
- Selfies and Action Freeze are for single player games only. A selfie or a freeze changes nothing in your game.

#### The cheat (sithewok)

- **Switch it on:** hold MENU and tap **CHEAT** in the tray, or open the console (KEYS) and type `sithewok`. It gives god mode and every weapon, and a gold **λ** button appears in the top row. **Hold λ** for half a second to switch the cheat off (grey) or on again (gold); a tap does nothing.
- **While it's on:** **hold JUMP** still for half a second for **noclip** (fly through walls; **double-tap JUMP** to land), and **hold USE** still for half a second for **notarget** (enemies ignore you). Small labels under JUMP and USE show them. Both end at each new level; god mode stays on.
- **LEVEL**, in the tray: tap it for a list of the game's chapters, numbered, each with its title and first map, the one you're playing ticked. The game holds still while it's open. Tap a chapter to start it (with the suit and all weapons); the X or a tap off the list closes it. Or hold LEVEL and it counts through the chapters: let go to start the one shown. Only chapters whose maps you have are listed.
- **Single player only.** The cheat and LEVEL do nothing in a game with other players.

#### Playing with friends (experimental)

These have had the least testing of anything in the app.

- **Half-Life co-op**, up to 4 players through the campaign: on *Choose a game*, **hold** the Half-Life card for half a second, then pick *Co-op: host a chapter* (and a chapter) or *Co-op: join a friend*. Whoever reaches a level change takes everyone along, and a fallen player comes back next to a teammate. Co-op games can't be saved: host again from the chapter you reached.
- **Multiplayer Modes:** Deathmatch, Team Deathmatch, Arena, Last Man Standing, Instagib, Gun Game, Low Gravity, Crowbars Only, Snarks Only, Rockets Only, Capture the Flag and Domination. They need the `ag` folder from the free *Adrenaline Gamer* mod (AG 6.6 on ModDB, or OpenAG's full package at openag.pro). Hold the *Multiplayer Modes* card to pick a mode, then *Multiplayer › Create game* to host it.
- **Counter-Strike:** with your own Steam copy of Counter-Strike (its `cstrike` folder), using the open-source cs16-client and ReGameDLL_CS, with the game's own bots.
- **Joining:** the *Choose a game* screen shows the addresses friends join you at: your Wi-Fi address and, if Tailscale is running, your Tailscale address (for playing over the internet). In the game, use *Multiplayer › Internet/LAN game*, or add the server by its address. iOS asks once for **Local Network** access: allow it, to host or join. The screen stays on while you host: if the host's phone locks or leaves the app, the game freezes for everyone.

#### Menus, switching games and the console

- **Choose a game** opens with the app. **Tap** a ready game to play it. *Options* (bottom right) takes extra engine command-line options, for experts.
- **One game per launch.** To play another, tap **GAMES** in MENU's tray: pick the next game, and the game you're in ends (unsaved progress is lost) and the app closes. Tap the notification it shows, or open the app again within 10 minutes, and the game you picked starts. *Cancel* goes back to your game.
- **The console:** **KEYS** in the tray opens it, with the keyboard.

#### Small print

- In single player the game holds still while the wheel, LEVEL or *Switch game* is open; a game with other players never holds still.
- The app keeps the screen on while you play.

### Known limitations

- **Beta, tested on one iPhone only:** the app has been played on the owner's own iPhone. Nothing else has been tried: no iPad (the app is marked for iPad, but has never been installed on one), no other iPhone models or iOS versions, no game controllers, keyboards or mice.
- **The experimental extras** (co-op, Multiplayer Modes, Counter-Strike, playing with friends over Wi-Fi or Tailscale) have had much less testing than single player. If something goes wrong, please report it (see *Found a bug?*).
- **Finding games on your Wi-Fi by itself may not work**, because iOS limits broadcasts for apps installed this way: join by address instead.
- **Game data:** only Steam copies are expected to work. The *Choose a game* screen notices Steam's 25th anniversary update data (2023) and then adds its *Uplink* chapter to LEVEL. Other editions (old CDs, non-English versions) haven't been tried.
- **Leaving the app doesn't save your game.** Quick save first.
- **The app's version** shows as `v1.0` and a build number, not `v0.1-beta1`: that's expected.

### Requirements

- An **iPhone on iOS 12 or newer** (the oldest version the app is built for). Only one iPhone, on a recent iOS, has been tried.
- **Your own Steam copy of Half-Life** for its `valve` folder, and a computer with Steam to copy it from. Optional, each its own purchase: *Half-Life: Opposing Force* (the `gearbox` folder), *Half-Life: Blue Shift* (`bshift`) and *Counter-Strike* (`cstrike`). The free *Adrenaline Gamer* mod (`ag`) for Multiplayer Modes.
- A **sideloading tool or signing service** (something that installs apps from outside the App Store) that can install an app file (`.ipa`) you give it, for example AltStore, SideStore or Sideloadly. The `.ipa` isn't signed for your iPhone, so it can't be installed without one. With a free Apple ID, Apple's limits apply: the app has to be signed again every 7 days, and only 3 such apps can be installed at a time.

### Install

1. Download **`Xash3D-iOS-unsigned.ipa`**, below.
2. Install it with your sideloading tool or signing service, following that tool's own instructions (whether iOS asks you to trust a developer or to turn on Developer Mode depends on the tool). On your home screen the app is called **Half-Life** (bundle ID `com.sithewok.xash3d`).
3. **Open the app once.** It shows *Choose a game*, with Half-Life saying *Not installed: copy the "valve" folder*. That's expected: the app has now made its folder in the Files app, **On My iPhone › Half-Life**, with a file in it called *Copy game folders here.txt*.
4. On your computer, in Steam, find the games' folder: right-click Half-Life in your Library, then *Manage › Browse local files*. It's the `Half-Life` folder (in `steamapps › common`), and the game folders are inside it:
   - `valve`: Half-Life, needed by all the others;
   - `gearbox`: Opposing Force (optional);
   - `bshift`: Blue Shift (optional);
   - `cstrike`: Counter-Strike (optional, experimental).
5. Copy the folders you want into **On My iPhone › Half-Life** in the Files app, as they are (not zipped), next to *Copy game folders here.txt*. Copying the whole `Half-Life` folder there works too. Any way into the Files app is fine, for example iCloud Drive: copy them into iCloud Drive on your computer, then move them into the app's folder in the Files app. A big folder takes a while to copy: wait until it has finished.
6. **Open the app again**, or go back to it: *Choose a game* updates by itself and shows **Ready** for each game it found. Opposing Force and Blue Shift also need `valve`; a game that's missing something says what, and a tap on it explains.

**Your saves** are in each game's folder, in its `save` folder (for example *On My iPhone › Half-Life › valve › save*). **Back up** that folder now and then, and always before you delete or reinstall the app: deleting the app deletes its folder, game files and saves included. Installing a newer version over this one with the same tool and Apple ID should keep your files, but that hasn't been tried yet. The touch settings are kept by iOS, not in the folder.

**If something goes wrong:** `engine.log`, `xash-trace.txt` and `xash-trace-previous.txt`, in the app's folder in Files, say what the game was doing. Copy them out before you open the app again.

**Found a bug?** Please report it here, not to the upstream Xash3D FWGS project, and say you're on **ios-v0.1-beta1** (the app shows `v1.0` and a build number under MENU's tray), which iPhone and iOS version you have, which game, and what you were doing, with the log files above: https://github.com/sithewok13-dev/xash3d-fwgs/issues

**Download:** under *Assets* below: `Xash3D-iOS-unsigned.ipa`. The *iOS latest* prerelease, also on the Releases page, is rebuilt automatically after every code change, before anyone has tried it: use this release.

---

Unofficial build. Half-Life, Half-Life: Opposing Force, Half-Life: Blue Shift and Counter-Strike are games by Valve (Opposing Force and Blue Shift with Gearbox Software). This app is not affiliated with or endorsed by Valve or Gearbox Software. No game files are included: you need your own copies.

**Xash3D FWGS** (GNU GPL v3), the engine, by Flying With Gauss and its contributors: https://github.com/FWGS/xash3d-fwgs. This app's source code, iOS changes included, is the `master` branch of https://github.com/sithewok13-dev/xash3d-fwgs (this release is the tag `ios-v0.1-beta1`: https://github.com/sithewok13-dev/xash3d-fwgs/tree/ios-v0.1-beta1). The engine also builds in libraries from its `3rdparty` folder, each under its own licence: https://github.com/sithewok13-dev/xash3d-fwgs/tree/master/3rdparty

**hlsdk-portable** (the game code of Half-Life, Opposing Force and Blue Shift, from its `master`, `opfor` and `bshift` branches), by Flying With Gauss and its contributors: https://github.com/FWGS/hlsdk-portable. It is based on Valve's Half-Life 1 SDK and is under Valve's **Half Life 1 SDK License**, which allows it to be copied, modified and given away in source and object code form, **only for free**, with the licence included: https://github.com/FWGS/hlsdk-portable/blob/master/LICENSE. The co-op and Multiplayer Modes game code comes from this project's own branches of it (`ios-coop`, `ios-ag`), under the same licence: https://github.com/sithewok13-dev/hlsdk-portable

**Counter-Strike:** cs16-client by Velaron and contributors (GNU GPL v2 or later, with an exception for Valve's Half-Life engine and SDK code, and the Half Life 1 SDK License for the SDK parts): https://github.com/Velaron/cs16-client/blob/master/LICENSE. With ReGameDLL_CS by its contributors (see its licence): https://github.com/rehlds/ReGameDLL_CS/blob/master/LICENSE

**SDL2** (zlib licence), by Sam Lantinga and contributors: https://github.com/libsdl-org/SDL/blob/release-2.32.10/LICENSE.txt
