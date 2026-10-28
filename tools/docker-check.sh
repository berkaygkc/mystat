#!/bin/bash
# Docker değerlerini docker CLI ile yan yana yazar (plan 2b, Task 10).
# Kullanım: tools/docker-check.sh [tur=5] [aralık_sn=20]
#   DEBUG mystat'ı --log-values ile başlatır. Her turda: container toplam CPU'su (%100 = 1 çekirdek) ve belleği (GiB)
#   `docker stats --no-stream` ile; sonda image ve volume geri kazanılabilirleri `docker system df` ile karşılaştırılır.
#   İki taraf da anlık değer verir (mystat 15 sn tempoyla, docker stats kendi ~2 sn penceresiyle); ölçüt tur ortalaması.
set -euo pipefail
export LC_ALL=C
cd "$(dirname "$0")/.."
ROUNDS="${1:-5}"
GAP="${2:-20}"
swift build -q
LOG="$(mktemp -t mystat-docker)"
.build/debug/mystat --log-values > "$LOG" 2>/dev/null &
PID=$!
disown "$PID"
trap 'kill $PID 2>/dev/null; rm -f "$LOG"' EXIT
sleep 35   # ilk iki Docker okuması (kapalı panelde 15 sn tempo) ve ilk disk okuması

field() { sed -E "s/.* $1=([0-9.]+).*/\1/" <<< "$2"; }
# "1.5GB" / "300MB" / "12kB" → ondalık GB
gb() { awk '{ n = $1; u = $1; sub(/[A-Za-z]+$/, "", n); sub(/^[0-9.]+/, "", u)
              f = u == "GB" ? 1 : u == "MB" ? 1e-3 : u == "kB" ? 1e-6 : u == "B" ? 1e-9 : u == "TB" ? 1e3 : 0; printf "%.2f", n * f }' <<< "$1"; }

printf "%-8s | %-4s | %-7s %-7s | %-8s %-8s\n" saat adet "cpu" "docker" "bellek" "docker"
SUM_C=0; SUM_M=0; SUM_DC=0; SUM_DM=0
for i in $(seq 1 "$ROUNDS"); do
    CLI=$(docker stats --no-stream --format '{{.CPUPerc}} {{.MemUsage}}')
    M=$(tail -1 "$LOG")
    dcpu=$(awk '{ gsub("%", "", $1); s += $1 } END { printf "%.1f", s }' <<< "$CLI")
    dmem=$(awk '{ v = $2; n = v; u = v; sub(/[A-Za-z]+$/, "", n); sub(/^[0-9.]+/, "", u)
                  f = u == "KiB" ? 1 / 1048576 : u == "MiB" ? 1 / 1024 : u == "GiB" ? 1 : u == "B" ? 1 / 1073741824 : 0; s += n * f }
                END { printf "%.2f", s }' <<< "$CLI")
    mcpu=$(field dockerCPU "$M"); mmem=$(field dockerMem "$M"); n=$(field containers "$M")
    printf "%-8s | %-4s | %-7s %-7s | %-8s %-8s\n" "$(date +%T)" "$n" "$mcpu" "$dcpu" "$mmem" "$dmem"
    SUM_C=$(awk -v s="$SUM_C" -v a="$mcpu" 'BEGIN { print s + a }'); SUM_DC=$(awk -v s="$SUM_DC" -v a="$dcpu" 'BEGIN { print s + a }')
    SUM_M=$(awk -v s="$SUM_M" -v a="$mmem" 'BEGIN { print s + a }'); SUM_DM=$(awk -v s="$SUM_DM" -v a="$dmem" 'BEGIN { print s + a }')
    [ "$i" -lt "$ROUNDS" ] && sleep "$GAP"
done
awk -v c="$SUM_C" -v dc="$SUM_DC" -v m="$SUM_M" -v dm="$SUM_DM" -v n="$ROUNDS" 'BEGIN {
    printf "ortalama: CPU mystat %%%.1f, docker %%%.1f (%+.1f puan) · bellek mystat %.2f GiB, docker %.2f GiB (%+.1f%%)\n",
           c / n, dc / n, (c - dc) / n, m / n, dm / n, (dm > 0 ? (m - dm) / dm * 100 : 0) }'

M=$(tail -1 "$LOG")
DF=$(docker system df --format '{{.Type}}|{{.Reclaimable}}')
img=$(gb "$(awk -F'|' '$1 == "Images" { split($2, a, " "); print a[1] }' <<< "$DF")")
vol=$(gb "$(awk -F'|' '$1 == "Local Volumes" { split($2, a, " "); print a[1] }' <<< "$DF")")
printf "geri kazanılabilir: image mystat %s, docker %s GB · volume mystat %s, docker %s GB · adsız volume (mystat) %s GB\n" \
    "$(field imgReclaim "$M")" "$img" "$(field volReclaim "$M")" "$vol" "$(field volAnon "$M")"
