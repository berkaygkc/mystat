#!/bin/bash
# mystat.app paketini oluşturur ve imzalar.
# Kullanım: scripts/make-app.sh [release|debug|install]
#   release (varsayılan): build/mystat.app; boşta ölçümler bununla yapılır
#   debug:                hata ayıklama paketi
#   install:              release paketi ~/Applications/mystat.app'e kurar ve açar (giriş öğesinin yolu sabit kalır)
set -euo pipefail
cd "$(dirname "$0")/.."
MODE="${1:-release}"
case "$MODE" in
    release|install) CONFIG=release ;;
    debug) CONFIG=debug ;;
    *) echo "kullanım: $0 [release|debug|install]" >&2; exit 64 ;;
esac
swift build -c "$CONFIG"
BIN="$(swift build -c "$CONFIG" --show-bin-path)/mystat"
APP="build/mystat.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/mystat"
cp Resources/Info.plist "$APP/Contents/Info.plist"
IDENTITY="$(security find-identity -v -p codesigning 2>/dev/null | grep -m1 'Apple Development' | sed -E 's/.*"(.*)"/\1/' || true)"
codesign --force --sign "${IDENTITY:--}" "$APP" >/dev/null
echo "$APP ($CONFIG, imza: ${IDENTITY:-ad-hoc})"

if [ "$MODE" = install ]; then
    DEST="$HOME/Applications/mystat.app"
    pkill -x mystat 2>/dev/null && sleep 0.5 || true
    mkdir -p "$HOME/Applications"
    rm -rf "$DEST"
    cp -R "$APP" "$DEST"
    open "$DEST"
    echo "kuruldu: $DEST"
fi
