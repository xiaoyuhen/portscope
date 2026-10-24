#!/usr/bin/env bash
# Build a distributable PortScope.app zip.
#
# The app is ad-hoc signed, which is enough to run on this machine and to hand
# to someone who trusts you. It is NOT notarised: opening it on another Mac
# requires `xattr -dr com.apple.quarantine /Applications/PortScope.app`, or
# System Settings → Privacy & Security → Open Anyway, the first time.
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
# `ditto` preserves the bundle structure; `zip` does not.
#
# The resource-fork flags are load-bearing. Without them `ditto` writes
# `._Foo` AppleDouble files alongside every resource, and those files are not
# covered by the code signature — the app verifies before zipping and fails
# `codesign --verify` after unzipping, which is exactly what a user would hit.
ditto -c -k --keepParent --norsrc --noextattr --noqtn "$APP" "$ZIP"

# Prove it: the zip must survive a round trip with its signature intact.
VERIFY_DIR="$(mktemp -d)"
trap 'rm -rf "$VERIFY_DIR"' EXIT
unzip -q "$ZIP" -d "$VERIFY_DIR"
if ! codesign --verify --deep --strict "$VERIFY_DIR/PortScope.app" 2>/dev/null; then
    echo "    FAILED: the zipped app does not verify after extraction" >&2
    exit 1
fi
echo "    signature survives the zip round trip"

echo "==> $ZIP ($(du -h "$ZIP" | cut -f1))"

# The checksum file must name the zip *relative to itself*, not by its absolute
# path. `shasum` writes whatever path it was given, so the previous version put
# the build machine's directory in the file, and `shasum -c` failed for anyone
# who downloaded it. cd in, so the recorded name is just the filename.
(cd "$OUT" && shasum -a 256 "$(basename "$ZIP")" > "$(basename "$ZIP").sha256")
cat "$ZIP.sha256"

# Prove the published form works the way a user will use it.
(cd "$OUT" && shasum -a 256 -c "$(basename "$ZIP").sha256" >/dev/null) \
    && echo "    checksum verifies from the download directory"
