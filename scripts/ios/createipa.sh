#!/bin/bash

#cd into script directory
cd "${0%/*}" || exit 1

BUILDDIR=$(realpath ../../build)

cd "../../engine/platform/ios/bundle" || exit 1

if [ -d "$BUILDDIR" ]; then
    mkdir -p "$BUILDDIR/ios/xash3d.app"

    cp -r "$BUILDDIR/ios/libs/"* "$BUILDDIR/ios/xash3d.app"
    cp Info.plist "$BUILDDIR/ios/xash3d.app"
    # on CI, the build number is the run number, and the build stamp the app
    # shows (MENU's tray, the launcher) is that and today's date (UTC):
    # "build 123 · Nov 9". Local builds have no stamp: "build dev".
    if [ -n "$GITHUB_RUN_NUMBER" ]; then
        plutil -replace CFBundleVersion -string "$GITHUB_RUN_NUMBER" "$BUILDDIR/ios/xash3d.app/Info.plist"
        plutil -replace SWBuildNumber -string "$GITHUB_RUN_NUMBER" "$BUILDDIR/ios/xash3d.app/Info.plist"
        plutil -replace SWBuildDate -string "$(date -u +%F)" "$BUILDDIR/ios/xash3d.app/Info.plist"
    fi
    if [ ! -d "$BUILDDIR/SDL2.framework" ]; then
        echo "Couldn't find SDL2.framework, place it in the build directory"
        exit 1
    fi
    cp -r "$BUILDDIR/SDL2.framework" "$BUILDDIR/ios/xash3d.app"
    # ANGLE (OpenGL ES on Metal): engine/platform/ios/ios_angle.c opens its
    # frameworks at run time; without them the app draws with Apple's OpenGL
    # ES as before. They must be in the app's Frameworks folder: ANGLE's
    # libEGL opens <app>/Frameworks/libGLESv2.framework/libGLESv2 itself.
    if [ -n "$ANGLE_ROOT" ]; then
        mkdir -p "$BUILDDIR/ios/xash3d.app/Frameworks"
        for f in libGLESv2 libEGL; do
            if [ ! -f "$ANGLE_ROOT/out/ios/$f.framework/$f" ]; then
                echo "ANGLE_ROOT is set but $ANGLE_ROOT/out/ios/$f.framework is missing"
                exit 1
            fi
            cp -R "$ANGLE_ROOT/out/ios/$f.framework" "$BUILDDIR/ios/xash3d.app/Frameworks/"
        done
    else
        echo "ANGLE_ROOT isn't set: no ANGLE in the app (Apple's OpenGL ES only)"
    fi

    cd ../../../../ || exit 1

    ./waf build install --destdir="$BUILDDIR/ios/xash3d.app"
    #echo "Generating dSYMs"
    #find "$BUILDDIR/ios/xash3d.app" -name "*.dylib" -type f -exec dsymutil {} \;
    #dsymutil "$BUILDDIR/ios/xash3d.app/xash"

    cd "$BUILDDIR" || exit 1

    rm -r "$BUILDDIR/ios/Payload/"
    mkdir "$BUILDDIR/ios/Payload"

    cp -r "$BUILDDIR/ios/xash3d.app" ios/Payload/
    rm -r "$BUILDDIR/ios/xash3d.app"
    cd ios || exit 1
    # nested code first: the app's signature covers theirs
    for f in libGLESv2 libEGL; do
        if [ -d "Payload/xash3d.app/Frameworks/$f.framework" ]; then
            codesign --force --sign "-" --timestamp=none "Payload/xash3d.app/Frameworks/$f.framework" || exit 1
        fi
    done
    codesign --entitlements "$(realpath ../../engine/platform/ios/bundle/entitlements.plist)" --sign "-" --force Payload/xash3d.app
    if [ -e ../xash3d.ipa ]; then
        rm ../xash3d.ipa
    fi
    zip -q -r ../xash3d.ipa Payload
else
    echo "Couldn't find the build directory, compile the engine before running this script!"
    exit 1
fi

exit 0
