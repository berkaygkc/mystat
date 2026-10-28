#!/bin/bash
# mystat.app paketini oluşturur ve imzalar. Kullanım: scripts/make-app.sh [debug|release]
set -euo pipefail
cd "$(dirname "$0")/.."
CONFIG="${1:-debug}"
swift build -c "$CONFIG"
BIN="$(swift build -c "$CONFIG" --show-bin-path)/mystat"
APP="build/mystat.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/mystat"
cp Resources/Info.plist "$APP/Contents/Info.plist"
IDENTITY="$(security find-identity -v -p codesigning 2>/dev/null | grep -m1 'Apple Development' | sed -E 's/.*"(.*)"/\1/' || true)"
codesign --force --sign "${IDENTITY:--}" "$APP" >/dev/null
echo "$APP (imza: ${IDENTITY:-ad-hoc})"
