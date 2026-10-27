#!/bin/bash
# Builds an unsigned iOS IPA holding the engine plus the server and client
# libraries for Half-Life (valve), Opposing Force (gearbox) and Blue Shift
# (bshift). Game data is never bundled: the app reads it from Documents.
#
# Env:
#   HLSDK_REPO   git URL of hlsdk-portable (default FWGS upstream)
#   HLSDK_GAMES  space separated branch:gamedir pairs
#   IPA_NAME     output file name in artifacts/

set -e

ROOT=$(cd "$(dirname "$0")/../.." && pwd)
cd "$ROOT"

HLSDK_REPO=${HLSDK_REPO:-https://github.com/FWGS/hlsdk-portable}
HLSDK_GAMES=${HLSDK_GAMES:-"master:valve opfor:gearbox bshift:bshift"}
IPA_NAME=${IPA_NAME:-Xash3D-iOS-unsigned.ipa}

./waf configure --enable-lto --ios build install --destdir=build/ios || { cat build/config.log; exit 1; }

if [ ! -d build/SDL2.framework ]; then
	cp -R /Library/Frameworks/SDL2.framework build/
fi

LIBSDIR="$ROOT/build/ios/libs"
mkdir -p "$LIBSDIR"

for pair in $HLSDK_GAMES; do
	branch=${pair%%:*}
	gamedir=${pair##*:}
	src="$ROOT/build/hlsdk-$branch"

	echo "::group::hlsdk $branch -> $gamedir"
	rm -rf "$src"
	git clone --recursive --depth 1 -b "$branch" "$HLSDK_REPO" "$src"
	git -C "$src" log -1 --format='hlsdk %h %s'

	# Release builds of hlsdk are broken on iOS upstream, so build Debug,
	# like scripts/gha/build_ios.sh does.
	cmake -S "$src" -B "$src/build" \
		-DCMAKE_SYSTEM_NAME=iOS \
		-DCMAKE_OSX_DEPLOYMENT_TARGET=12.0 \
		-DCMAKE_INSTALL_PREFIX_INITIALIZED_TO_DEFAULT=0 \
		-DCMAKE_INSTALL_PREFIX="$LIBSDIR" \
		-DGAMEDIR="$gamedir" \
		-DCMAKE_BUILD_TYPE=Debug
	cmake --build "$src/build" --target install -j"$(sysctl -n hw.ncpu)"
	echo "::endgroup::"
done

echo "Game libraries:"
find "$LIBSDIR" -name '*.dylib' | sort

./scripts/ios/createipa.sh

mkdir -p artifacts
mv build/xash3d.ipa "artifacts/$IPA_NAME"
