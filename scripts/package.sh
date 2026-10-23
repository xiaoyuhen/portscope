#!/usr/bin/env bash
# Build a distributable PortScope.app zip.
#
# The app is ad-hoc signed, which is enough to run on this machine and to hand
# to someone who trusts you. It is NOT notarised: opening it on another Mac
# requires right-click → Open the first time, or
# `xattr -dr com.apple.quarantine /Applications/PortScope.app`.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VERSION="$(cat "$ROOT/VERSION")"
OUT="$ROOT/dist"

cd "$ROOT"
./scripts/build.sh --release

echo "==> Verifying bundle"
APP="$OUT/PortScope.app"
test -x "$APP/Contents/MacOS/PortScope"
/usr/libexec/PlistBuddy -c "Print :CFBundleIdentifier" "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$APP/Contents/Info.plist"
# Both localizations must be present, or the language switch silently falls
# back to English for Chinese users.
for lang in en.lproj zh-Hans.lproj; do
    test -d "$APP/Contents/Resources/$lang" || { echo "missing $lang"; exit 1; }
done

echo "==> Zipping"
ZIP="$OUT/PortScope-$VERSION.zip"
rm -f "$ZIP"
# `ditto` preserves the bundle structure and resource forks; `zip` does not.
ditto -c -k --keepParent "$APP" "$ZIP"
echo "==> $ZIP ($(du -h "$ZIP" | cut -f1))"
shasum -a 256 "$ZIP" | tee "$ZIP.sha256"
