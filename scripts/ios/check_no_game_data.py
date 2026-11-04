#!/usr/bin/env python3
# Fails (exit 1) if an IPA carries game data: Valve's or anyone else's maps,
# sounds, models, sprites, texture WADs, PAK files or bot databases. The IPA
# must hold only the engine, the game libraries and the port's own small
# files; players copy their game folders in themselves.
#
# Usage: check_no_game_data.py <file.ipa>
#
# What it checks: every file in the app (its game folders valve, gearbox,
# bshift, cstrike and ag included), and every file inside any .pk3/.zip
# archive in the app, since the engine mounts a game folder's .pk3 files as
# part of that folder. An archive inside an archive is refused (and checked).
import io
import sys
import zipfile

# Kinds of file that are game content.
BANNED_EXT = (".bsp", ".wav", ".mp3", ".mdl", ".spr", ".wad", ".db", ".pak",
              ".nav", ".gcf", ".avi")

# Archives: opened and checked inside.
ARCHIVE_EXT = (".pk3", ".zip")

# The only archives the app may carry, each the port's own, and both checked
# inside like everything else:
# - valve/extras.pk3: the engine's own extras (3rdparty/extras/xash-extras:
#   fonts, menu art, touch icons made for Xash3D FWGS).
# - cstrike/extras.pk3: built by scripts/ios/build_trilogy.sh from
#   cs16-client's touch layouts and settings only.
ALLOWED_ARCHIVES = {"valve/extras.pk3", "cstrike/extras.pk3"}

# What the allowed archives may hold, by path prefix inside them (None: any
# path, checked only for banned kinds). cstrike/extras.pk3 is only the
# client's own touch layouts, icons and settings (see build_trilogy.sh): this
# also keeps out Counter-Strike's menu art, menu text and launcher sounds,
# which cs16-client's full extras.pk3 carries.
ARCHIVE_CONTENTS = {
    "valve/extras.pk3": None,
    "cstrike/extras.pk3": ("touch/", "touch_default/", "touch_presets/",
                           "userconfig.d/", "touch.cfg"),
}

# Banned-kind files allowed anyway, as app-relative paths (or "<archive>!
# <path inside>"). None are needed today: keep it that way unless a file is
# the port's own work, and say why next to it.
ALLOWED_FILES = set()


def app_relative(name):
    # Payload/<App>.app/<rest> -> <rest>; None for files outside the app.
    parts = name.split("/")
    if len(parts) >= 3 and parts[0] == "Payload" and parts[1].endswith(".app"):
        return "/".join(parts[2:])
    return None


def check_archive(label, data, problems, depth=0, prefixes=None):
    try:
        zf = zipfile.ZipFile(io.BytesIO(data))
    except zipfile.BadZipFile:
        problems.append(f"{label}: not a readable archive")
        return 0
    count = 0
    for info in zf.infolist():
        if info.is_dir():
            continue
        count += 1
        inner = f"{label}!{info.filename}"
        low = info.filename.lower()
        if low.endswith(ARCHIVE_EXT):
            if depth >= 3:
                problems.append(f"{inner}: archives nested too deep")
            else:
                count += check_archive(inner, zf.read(info), problems, depth + 1)
            problems.append(f"{inner}: archive inside an archive")
        elif low.endswith(BANNED_EXT) and inner not in ALLOWED_FILES:
            problems.append(inner)
        elif prefixes and not info.filename.startswith(prefixes):
            problems.append(f"{inner}: not one of this archive's allowed files")
    return count


def main():
    if len(sys.argv) != 2:
        print("usage: check_no_game_data.py <file.ipa>")
        return 2
    problems = []
    checked = 0
    with zipfile.ZipFile(sys.argv[1]) as ipa:
        for info in ipa.infolist():
            if info.is_dir():
                continue
            rel = app_relative(info.filename)
            if rel is None:
                continue
            low = rel.lower()
            if low.endswith(ARCHIVE_EXT):
                if rel not in ALLOWED_ARCHIVES:
                    problems.append(f"{rel}: archive not on the allowlist")
                checked += check_archive(rel, ipa.read(info), problems,
                                         prefixes=ARCHIVE_CONTENTS.get(rel))
            elif low.endswith(BANNED_EXT) and rel not in ALLOWED_FILES:
                problems.append(rel)
            checked += 1
    if problems:
        print(f"::error::Game data found in the IPA ({len(problems)} problems). It must not be published.")
        for p in problems[:60]:
            print("  " + p)
        if len(problems) > 60:
            print(f"  ... and {len(problems) - 60} more")
        return 1
    print(f"No game data: {checked} files checked (archives opened).")
    return 0


if __name__ == "__main__":
    sys.exit(main())
