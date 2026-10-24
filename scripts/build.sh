#!/usr/bin/env bash
# Build PortScope.app from the SwiftPM target and ad-hoc sign it.
#
# Xcode is not required: the app is a SwiftUI executable wrapped in a bundle
# by this script.
#
#   scripts/build.sh              # debug, current machine's architecture
#   scripts/build.sh --release    # optimised, universal (arm64 + x86_64)
#   scripts/build.sh --release --native   # optimised, this architecture only
#
# The release build is universal by default because the README promises Apple
# silicon and Intel, and a binary that only runs on the machine that built it
# would make that promise false for half the audience. `--native` exists for
# iterating: a universal build compiles everything twice.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIG="debug"
ARCH_FLAGS=()
for argument in "$@"; do
    case "$argument" in
        --release) CONFIG="release"; ;;
        --native) ARCH_FLAGS=(); ;;
        --universal) ARCH_FLAGS=(--arch arm64 --arch x86_64); ;;
    esac
done
# Universal for release unless --native was passed; debug stays native.
if [[ "$CONFIG" == "release" && ${#ARCH_FLAGS[@]} -eq 0 && " $* " != *" --native "* ]]; then
    ARCH_FLAGS=(--arch arm64 --arch x86_64)
fi

APP_NAME="PortScope"
DIST="$ROOT/dist"
APP="$DIST/$APP_NAME.app"
VERSION="$(cat "$ROOT/VERSION" 2>/dev/null || echo 0.1.0)"
BUILD="$(date +%Y%m%d%H%M)"

echo "==> Building ($CONFIG${ARCH_FLAGS:+ universal})"
cd "$ROOT"
swift build -c "$CONFIG" --product "$APP_NAME" "${ARCH_FLAGS[@]+"${ARCH_FLAGS[@]}"}"
BIN="$(swift build -c "$CONFIG" --show-bin-path)/$APP_NAME"

echo "==> Assembling bundle"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/$APP_NAME"

# SwiftPM emits the resource bundle next to the binary; copy the localizations
# into the app bundle where Bundle.main will find them at runtime.
RES_BUNDLE="$(dirname "$BIN")/${APP_NAME}_${APP_NAME}.bundle"
if [[ -d "$RES_BUNDLE" ]]; then
    cp -R "$RES_BUNDLE" "$APP/Contents/Resources/"
fi
for lproj in "$ROOT"/Sources/PortScope/Resources/*.lproj; do
    [[ -d "$lproj" ]] && cp -R "$lproj" "$APP/Contents/Resources/"
done

# Icons are generated from Support/Icon/*.svg by scripts/make-icons.sh. The
# build regenerates them only when missing, so a normal build stays fast.
ICON_BUILD="$ROOT/Support/Icon/build"
if [[ ! -f "$ICON_BUILD/AppIcon.icns" ]]; then
    echo "==> Generating icons"
    "$ROOT/scripts/make-icons.sh" >/dev/null
fi
cp "$ICON_BUILD/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"
cp "$ICON_BUILD/MenuBarIcon.png" "$APP/Contents/Resources/MenuBarIcon.png"
cp "$ICON_BUILD/MenuBarIcon@2x.png" "$APP/Contents/Resources/MenuBarIcon@2x.png"

sed -e "s/__VERSION__/$VERSION/" -e "s/__BUILD__/$BUILD/" \
    -e "s|__TELEMETRY_URL__|${PORTSCOPE_TELEMETRY_URL:-}|" \
    "$ROOT/Support/Info.plist" > "$APP/Contents/Info.plist"
printf 'APPL????' > "$APP/Contents/PkgInfo"

echo "==> Signing (ad-hoc)"
# Ad-hoc signing is enough for local use. A Developer ID signature is only
# needed to hand the app to another machine.
codesign --force --deep --sign - "$APP" 2>/dev/null || echo "    (codesign unavailable, continuing unsigned)"

echo "==> Done: $APP"
