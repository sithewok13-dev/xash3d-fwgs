#!/bin/bash
# Builds an unsigned iOS IPA holding the engine plus the server and client
# libraries for Half-Life (valve), Opposing Force (gearbox) and Blue Shift
# (bshift). Game data is never bundled: the app reads it from Documents.
#
# Env:
#   HLSDK_REPO   git URL of hlsdk-portable (default FWGS upstream)
#   HLSDK_GAMES  space separated branch:gamedir pairs
#   HLSDK_OPTIONAL_GAMES  the same, built from HLSDK_OPTIONAL_REPO and left
#                out if they fail ("" for none); default: the fork's ios-ag
#                branch (Adrenaline Gamer and our multiplayer modes) as "ag"
#   IPA_NAME     output file name in artifacts/

set -e

ROOT=$(cd "$(dirname "$0")/../.." && pwd)
cd "$ROOT"

HLSDK_REPO=${HLSDK_REPO:-https://github.com/FWGS/hlsdk-portable}
HLSDK_GAMES=${HLSDK_GAMES:-"master:valve opfor:gearbox bshift:bshift"}
# optional extra game libraries: a failure leaves them out of the IPA
# instead of failing the build (empty: none)
# (from the fork, where our multiplayer modes live)
HLSDK_OPTIONAL_REPO=${HLSDK_OPTIONAL_REPO:-https://github.com/sithewok13-dev/hlsdk-portable}
HLSDK_OPTIONAL_GAMES=${HLSDK_OPTIONAL_GAMES-"ios-ag:ag"}
IPA_NAME=${IPA_NAME:-Xash3D-iOS-unsigned.ipa}

mkdir -p build
./waf configure --enable-lto --ios build install --destdir=build/ios 2>&1 | tee build/waf.log
if [ "${PIPESTATUS[0]}" -ne 0 ]; then
	# compiler errors first, then the end of the log (configure failures show there)
	grep -E "error:|Error" build/waf.log | head -60 || true
	tail -40 build/waf.log
	exit 1
fi

if [ ! -d build/SDL2.framework ]; then
	cp -R /Library/Frameworks/SDL2.framework build/
fi

LIBSDIR="$ROOT/build/ios/libs"
mkdir -p "$LIBSDIR"

# builds one hlsdk branch's libraries for one game folder
build_hlsdk() {
	branch=$1
	gamedir=$2
	prefix=$3
	repo=$4
	src="$ROOT/build/hlsdk-$branch"

	rm -rf "$src"
	git clone --recursive --depth 1 -b "$branch" "$repo" "$src" || return 1
	git -C "$src" log -1 --format='hlsdk %h %s'

	# Release builds of hlsdk are broken on iOS upstream, so build Debug,
	# like scripts/gha/build_ios.sh does.
	cmake -S "$src" -B "$src/build" \
		-DCMAKE_SYSTEM_NAME=iOS \
		-DCMAKE_OSX_DEPLOYMENT_TARGET=12.0 \
		-DCMAKE_INSTALL_PREFIX_INITIALIZED_TO_DEFAULT=0 \
		-DCMAKE_INSTALL_PREFIX="$prefix" \
		-DGAMEDIR="$gamedir" \
		-DCMAKE_BUILD_TYPE=Debug || return 1
	cmake --build "$src/build" --target install -j"$(sysctl -n hw.ncpu)" || return 1
}

for pair in $HLSDK_GAMES; do
	echo "::group::hlsdk ${pair%%:*} -> ${pair##*:}"
	build_hlsdk "${pair%%:*}" "${pair##*:}" "$LIBSDIR" "$HLSDK_REPO"
	echo "::endgroup::"
done

# optional ones go to their own folder first, so a half-built one can't
# leave pieces in the IPA
for pair in $HLSDK_OPTIONAL_GAMES; do
	echo "::group::hlsdk ${pair%%:*} -> ${pair##*:} (optional)"
	staged="$ROOT/build/ios/optional-${pair##*:}"
	rm -rf "$staged"
	if ( build_hlsdk "${pair%%:*}" "${pair##*:}" "$staged" "$HLSDK_OPTIONAL_REPO" ); then
		cp -R "$staged"/. "$LIBSDIR"/
		echo "Optional game ${pair##*:}: built"
	else
		echo "::warning::Optional game ${pair##*:} (hlsdk ${pair%%:*}) failed to build; left out of the IPA"
	fi
	echo "::endgroup::"
done

# Counter-Strike 1.6 (optional, as above): cs16-client's client, menus and
# ReGameDLL_CS server (with the game's own bots), in "cstrike". It has no iOS
# naming of its own, so its libraries are renamed to <name>_ios_arm64.dylib.
CS16_REPO=${CS16_REPO-https://github.com/Velaron/cs16-client}
build_cs16() {
	cssrc="$ROOT/build/cs16-client"
	staged=$1
	rm -rf "$cssrc" "$staged"
	git clone --recursive --depth 1 --shallow-submodules "$CS16_REPO" "$cssrc" || return 1
	git -C "$cssrc" log -1 --format='cs16-client %h %s'
	cmake -S "$cssrc" -B "$cssrc/build" \
		-DCMAKE_SYSTEM_NAME=iOS \
		-DCMAKE_OSX_ARCHITECTURES=arm64 \
		-DCMAKE_OSX_DEPLOYMENT_TARGET=12.0 \
		-DCMAKE_BUILD_TYPE=Release \
		-DCMAKE_INSTALL_PREFIX="$staged" || return 1
	cmake --build "$cssrc/build" -j"$(sysctl -n hw.ncpu)" || return 1
	cmake --install "$cssrc/build" || return 1
	find "$staged" -name '*.dylib' | while read -r lib; do
		base=$(basename "$lib" .dylib)
		case "$base" in
			*_ios_arm64) ;;
			*_arm64) mv "$lib" "$(dirname "$lib")/${base%_arm64}_ios_arm64.dylib" ;;
			*) mv "$lib" "$(dirname "$lib")/${base}_ios_arm64.dylib" ;;
		esac
	done
	echo "cs16-client files (only the libraries go in the IPA):"
	find "$staged" -type f | sort
	test -n "$(find "$staged" -name 'client_ios_arm64.dylib')"
}

if [ -n "$CS16_REPO" ]; then
	echo "::group::cs16-client -> cstrike (optional)"
	staged="$ROOT/build/ios/optional-cstrike"
	if ( build_cs16 "$staged" ); then
		mkdir -p "$LIBSDIR/cstrike"
		( cd "$staged" && find . -name '*.dylib' -exec sh -c 'mkdir -p "$1/$(dirname "$2")" && cp "$2" "$1/$2"' _ "$LIBSDIR" {} \; )
		echo "Optional game cstrike: built"
	else
		echo "::warning::Optional game cstrike (cs16-client) failed to build; left out of the IPA"
	fi
	echo "::endgroup::"
fi

echo "Game libraries:"
find "$LIBSDIR" -name '*.dylib' | sort

./scripts/ios/createipa.sh

mkdir -p artifacts
mv build/xash3d.ipa "artifacts/$IPA_NAME"

# our iOS sources, compiled: shown at the end where the log is easy to read
echo "Compiled iOS sources:"
grep -oE "platform/ios/[a-z_]+\.(m|c)" build/waf.log | sort -u || true
echo "Warnings in iOS code:"
grep -E "platform/ios|input/input\.c" build/waf.log | grep -iE "warning|error" || echo "none"
