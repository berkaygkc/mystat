#!/bin/bash
# Builds and signs the mystat.app bundle.
# Usage: scripts/make-app.sh [release|debug|install]
#   release (default): build/mystat.app; idle measurements are made with this
#   debug:             debug bundle
#   install:           installs the release bundle to ~/Applications/mystat.app and opens it (the login item path stays fixed)
set -euo pipefail
cd "$(dirname "$0")/.."
MODE="${1:-release}"
case "$MODE" in
    release|install) CONFIG=release ;;
    debug) CONFIG=debug ;;
    *) echo "usage: $0 [release|debug|install]" >&2; exit 64 ;;
esac
swift build -c "$CONFIG"
BIN="$(swift build -c "$CONFIG" --show-bin-path)/mystat"
APP="build/mystat.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/mystat"
cp Resources/Info.plist "$APP/Contents/Info.plist"
# Locale files (Locales/*.json). Without them the app shows keys instead of text, so packaging stops.
ls Locales/*.json >/dev/null 2>&1 || { echo "Locales/*.json missing" >&2; exit 1; }
mkdir -p "$APP/Contents/Resources/Locales"
cp Locales/*.json "$APP/Contents/Resources/Locales/"
# Texts macOS draws itself (the location permission dialog), per system language.
cp -R Resources/*.lproj "$APP/Contents/Resources/"
# App icon: Resources/AppIcon.png (1024, Apple icon grid) → 16…1024 px icon set → AppIcon.icns.
ICONSET="build/AppIcon.iconset"
rm -rf "$ICONSET"; mkdir -p "$ICONSET"
for s in 16 32 128 256 512; do
    sips -z "$s" "$s" Resources/AppIcon.png --out "$ICONSET/icon_${s}x${s}.png" >/dev/null
    sips -z $((s * 2)) $((s * 2)) Resources/AppIcon.png --out "$ICONSET/icon_${s}x${s}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"
# Signing: Developer ID (distribution via GitHub; Full Disk Access and Location permissions persist across installs), otherwise
# Apple Development, otherwise ad-hoc. Developer ID uses the hardened runtime and a timestamp, which
# notarization requires; the timestamp keeps the signature valid even after the certificate expires.
find_identity() { security find-identity -v -p codesigning 2>/dev/null | grep -m1 "$1" | sed -E 's/.*"(.*)"/\1/' || true; }
IDENTITY="$(find_identity 'Developer ID Application')"
if [ -n "$IDENTITY" ]; then
    codesign --force --options runtime --timestamp --sign "$IDENTITY" "$APP" >/dev/null
else
    IDENTITY="$(find_identity 'Apple Development')"
    codesign --force --sign "${IDENTITY:--}" "$APP" >/dev/null
fi
echo "$APP ($CONFIG, signature: ${IDENTITY:-ad-hoc})"

if [ "$MODE" = install ]; then
    DEST="$HOME/Applications/mystat.app"
    pkill -x mystat 2>/dev/null && sleep 0.5 || true
    mkdir -p "$HOME/Applications"
    rm -rf "$DEST"
    cp -R "$APP" "$DEST"
    open "$DEST"
    echo "installed: $DEST"
fi
