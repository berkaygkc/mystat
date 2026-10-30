#!/bin/bash
# Renders every snapshot screen with sample data in one language: build/lang-gallery/<lang>/NN.png and index.txt.
# Usage: tools/lang-gallery.sh [lang=en]
# For spotting overflowing or truncated text in a new language by eye (Locales/README.md).
set -euo pipefail
cd "$(dirname "$0")/.."
LANG_CODE="${1:-en}"
swift build -q
BIN=".build/debug/mystat"
OUT="build/lang-gallery/$LANG_CODE"
rm -rf "$OUT"; mkdir -p "$OUT"
i=0
shot() {
    i=$((i + 1)); local n; n=$(printf "%02d" "$i")
    "$BIN" --lang "$LANG_CODE" "$@" --out "$OUT/$n.png" >/dev/null 2>&1
    echo "$n $*" >> "$OUT/index.txt"
}
shot --snapshot menubar --size 900x60
for k in cpu memory disk docker heat battery; do shot --snapshot menubar --size 900x60 --incident --kind "$k"; done
shot --snapshot panel --size 700x900
shot --snapshot panel --size 700x900 --dark
for k in cpu memory disk docker heat battery; do shot --snapshot panel --size 700x900 --incident --kind "$k"; done
for s in overview cpu mem disk net docker sys; do shot --snapshot monitor --section "$s"; done
for s in overview cpu mem disk net docker sys; do shot --snapshot monitor --section "$s" --incident --kind cpu; done
for k in memory disk docker heat battery; do shot --snapshot monitor --section overview --incident --kind "$k"; done
shot --snapshot monitor --section mem --incident --kind memory
shot --snapshot monitor --section disk --incident --kind disk
shot --snapshot monitor --section docker --incident --kind docker
shot --snapshot monitor --section sys --incident --kind heat
shot --snapshot monitor --section sys --incident --kind battery
shot --snapshot monitor --section overview --dark
shot --snapshot monitor --section docker --docker down
shot --snapshot monitor --section disk --scan none
shot --snapshot monitor --section disk --scan scanning
shot --snapshot monitor --section disk --confirm basket
shot --snapshot monitor --section disk --fda none --scan none
shot --snapshot monitor --section disk --inaccessible 3 --fda none
shot --snapshot monitor --section cpu --confirm stop
shot --snapshot monitor --section docker --confirm prune
shot --snapshot monitor --section net --ssid needs
shot --snapshot monitor --section net --ssid denied
shot --snapshot monitor --section overview --caps none
shot --snapshot monitor --section sys --caps none
shot --snapshot monitor --section cpu --select next-web
shot --snapshot charts --size 1000x320
shot --snapshot bubbles --size 900x600
echo "$OUT: $i images"
