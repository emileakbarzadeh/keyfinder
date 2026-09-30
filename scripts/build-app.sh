#!/bin/bash
set -euo pipefail

KEYFINDER_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$KEYFINDER_ROOT"
CONFIGURATION="${1:-release}"
case "$CONFIGURATION" in release|debug) ;; *) echo 'Usage: scripts/build-app.sh [release|debug]' >&2; exit 2 ;; esac

swift build -c "$CONFIGURATION" --product Keyfinder
BIN_DIRECTORY="$(swift build -c "$CONFIGURATION" --show-bin-path)"
STAGING_DIRECTORY="$(mktemp -d "$KEYFINDER_ROOT/.build/keyfinder-package.XXXXXX")"
trap 'rm -rf "$STAGING_DIRECTORY"' EXIT
STAGED_APP="$STAGING_DIRECTORY/Keyfinder.app"
mkdir -p "$STAGED_APP/Contents/MacOS" "$STAGED_APP/Contents/Resources"
cp "$BIN_DIRECTORY/Keyfinder" "$STAGED_APP/Contents/MacOS/Keyfinder"
ditto "$BIN_DIRECTORY/Keyfinder_KeyfinderCore.bundle" "$STAGED_APP/Contents/Resources/Keyfinder_KeyfinderCore.bundle"
cp Packaging/Info.plist "$STAGED_APP/Contents/Info.plist"

"$BIN_DIRECTORY/Keyfinder" --render-icon "$STAGING_DIRECTORY/icon.png"
ICONSET="$STAGING_DIRECTORY/Keyfinder.iconset"
mkdir -p "$ICONSET"
for SIZE in 16 32 128 256 512; do
    sips -z "$SIZE" "$SIZE" "$STAGING_DIRECTORY/icon.png" --out "$ICONSET/icon_${SIZE}x${SIZE}.png" >/dev/null
    DOUBLE_SIZE=$((SIZE * 2))
    sips -z "$DOUBLE_SIZE" "$DOUBLE_SIZE" "$STAGING_DIRECTORY/icon.png" --out "$ICONSET/icon_${SIZE}x${SIZE}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$STAGED_APP/Contents/Resources/Keyfinder.icns"

if [ -n "${KEYFINDER_SIGNING_IDENTITY:-}" ]; then
    codesign --force --options runtime --timestamp --sign "$KEYFINDER_SIGNING_IDENTITY" "$STAGED_APP"
else
    codesign --force --sign - "$STAGED_APP"
fi
codesign --verify --strict "$STAGED_APP"
mkdir -p dist
if [ -d dist/Keyfinder.app ]; then rm -rf dist/Keyfinder.app; fi
mv "$STAGED_APP" dist/Keyfinder.app
ditto -c -k --keepParent dist/Keyfinder.app dist/Keyfinder-macOS.zip
echo "Built $KEYFINDER_ROOT/dist/Keyfinder.app"
if [ -z "${KEYFINDER_SIGNING_IDENTITY:-}" ]; then
    echo 'Signed locally (ad hoc). Developer ID signing and notarization are optional distribution steps.'
fi
