#!/bin/bash
# Ev klasörü taramasını `du` ile karşılaştırır (plan 2d, Task 8). Salt okunur; hiçbir şey silinmez.
# Kullanım: tools/disk-check.sh
#   DEBUG mystat'ı --scan-home ile çalıştırır (arayüzsüz tarama, geçici önbellek): toplam, süre, işlemci zamanı,
#   erişilemeyen klasör, bellek (önce / tepe / hazır / ağaç bırakılınca; RSS ve Etkinlik Monitörü'nün ayak izi). Ardından en büyük 10 kalemi ve toplamı
#   `du -sk` ile yan yana yazar (fark %). `du` korumalı klasörleri aynı şekilde atlar.
set -euo pipefail
export LC_ALL=C
export MallocLargeCache=0   # paketteki LSEnvironment ile aynı
cd "$(dirname "$0")/.."
swift build -q
OUT="$(.build/debug/mystat --scan-home)"
head -1 <<< "$OUT" | tr ' ' '\n'
echo
printf "%-28s %12s %12s %8s\n" kalem mystat_GB du_GB fark_%
pct() { awk -v a="$1" -v b="$2" 'BEGIN { if (b == 0) print "—"; else printf "%+.2f", (a - b) / b * 100 }'; }
gb() { awk -v v="$1" 'BEGIN { printf "%.2f", v / 1e9 }'; }
while IFS=$'\t' read -r _ name bytes; do
    du_b=$(( $( { du -sk "$HOME/$name" 2>/dev/null || true; } | cut -f1) * 1024 ))   # korumalı alt klasörde du 1 döner
    printf "%-28s %12s %12s %8s\n" "$name" "$(gb "$bytes")" "$(gb "$du_b")" "$(pct "$bytes" "$du_b")"
done < <(grep '^kalem' <<< "$OUT")
total=$(head -1 <<< "$OUT" | sed -E 's/.*toplam_gb=([0-9.]+).*/\1/')
du_total=$(( $( { du -sk "$HOME" 2>/dev/null || true; } | cut -f1) * 1024 ))
printf "%-28s %12s %12s %8s\n" "~ (toplam)" "$total" "$(gb "$du_total")" "$(pct "$(awk -v t="$total" 'BEGIN { printf "%.0f", t * 1e9 }')" "$du_total")"
