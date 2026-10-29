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
# Dil dosyaları (Locales/*.json). Yoksa uygulama metin yerine anahtar gösterir: paketleme durur.
ls Locales/*.json >/dev/null 2>&1 || { echo "Locales/*.json yok" >&2; exit 1; }
mkdir -p "$APP/Contents/Resources/Locales"
cp Locales/*.json "$APP/Contents/Resources/Locales/"
# macOS'un kendi çizdiği metinler (konum izni penceresi) sistem diline göre.
cp -R Resources/*.lproj "$APP/Contents/Resources/"
# İmza: Developer ID (GitHub'dan dağıtım; Tam Disk Erişimi ve Konum izni kurulumlar arasında korunur), yoksa
# Apple Development, o da yoksa geçici (ad-hoc). Developer ID'de güçlendirilmiş çalışma ortamı ve zaman damgası:
# Apple onayının (notarization) şartı; zaman damgası sertifikanın süresi dolsa da imzayı geçerli tutar.
find_identity() { security find-identity -v -p codesigning 2>/dev/null | grep -m1 "$1" | sed -E 's/.*"(.*)"/\1/' || true; }
IDENTITY="$(find_identity 'Developer ID Application')"
if [ -n "$IDENTITY" ]; then
    codesign --force --options runtime --timestamp --sign "$IDENTITY" "$APP" >/dev/null
else
    IDENTITY="$(find_identity 'Apple Development')"
    codesign --force --sign "${IDENTITY:--}" "$APP" >/dev/null
fi
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
