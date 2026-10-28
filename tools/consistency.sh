#!/bin/bash
# Menü çubuğu değerlerini sistem araçlarıyla yan yana yazar (plan Review Focus #5: fark ≤ 3 puan).
# Kullanım: tools/consistency.sh [tur=10] [aralık_sn=30]
#   DEBUG mystat'ı --log-values ile başlatır. Her turda: mystat satırı, top'un CPU satırı, vm_stat'tan
#   Activity Monitor tanımıyla kullanılan bellek (uygulama + kablolu + sıkıştırılmış), memory_pressure ve
#   birincil arayüzün netstat -ib sayaçlarından tur ortalaması hız. CPU için mystat ve `top -l 0 -s 2` tüm süre
#   boyunca 2 sn'de bir yazar; sonda iki akışın ortalaması karşılaştırılır (tek tek turlar zamanlama yüzünden oynar,
#   top'un her açılışı da kendi penceresine düşmeyen bir yük yaratır).
set -euo pipefail
export LC_ALL=C
cd "$(dirname "$0")/.."
ROUNDS="${1:-10}"
GAP="${2:-30}"
swift build -q
LOG="$(mktemp -t mystat-values)"
.build/debug/mystat --log-values > "$LOG" 2>/dev/null &
PID=$!
disown "$PID"
TOPLOG="$(mktemp -t mystat-top)"
top -l 0 -n 0 -s 2 | grep --line-buffered "CPU usage" > "$TOPLOG" &
TPID=$!
disown "$TPID"
trap 'kill $PID 2>/dev/null; pkill -P $$ top 2>/dev/null; rm -f "$LOG" "$TOPLOG"' EXIT
sleep 6

TOTAL=$(sysctl -n hw.memsize)
IF=$(route -n get default 2>/dev/null | awk '/interface:/ {print $2}')
net() { netstat -ib -I "$IF" | awk 'NR == 2 { print $7, $10 }'; }
read -r IN0 OUT0 < <(net)
T0=$(date +%s)
INS=$IN0; OUTS=$OUT0; TS=$T0; SKIP=$(wc -l < "$LOG")
printf "%-8s | %-6s %-6s | %-6s %-6s | %-8s | %-13s %-13s\n" saat "cpu" "top" "mem" "vm" "baskı" "ağ (mystat)" "ağ (netstat)"
SUM_CPU=0; SUM_MEM=0; BIAS_CPU=0; BIAS_MEM=0
for i in $(seq 1 "$ROUNDS"); do
    TOP=$(tail -1 "$TOPLOG")
    M=$(tail -1 "$LOG")
    VM=$(vm_stat)
    PRESS=$(memory_pressure -Q | awk -F': ' '/free percentage/ { print $2 }')
    read -r IN1 OUT1 < <(net); T1=$(date +%s)

    mcpu=$(sed -E 's/.*cpu=([0-9.]+).*/\1/' <<< "$M")
    mmem=$(sed -E 's/.* mem=([0-9.]+).*/\1/' <<< "$M")
    mnet=$(sed -E 's/.*down=([0-9.]+) up=([0-9.]+).*/\1↓ \2↑/' <<< "$M")
    tcpu=$(awk '{ gsub("%", ""); print $3 + $5 }' <<< "$TOP")
    vmem=$(awk -v total="$TOTAL" '
        /page size of/ { page = $8 }
        /Anonymous pages/ { gsub("\\.", "", $3); anon = $3 }
        /Pages purgeable/ { gsub("\\.", "", $3); purg = $3 }
        /Pages wired down/ { gsub("\\.", "", $4); wired = $4 }
        /occupied by compressor/ { gsub("\\.", "", $5); comp = $5 }
        END { printf "%.1f", (anon - purg + wired + comp) * page / total * 100 }' <<< "$VM")
    dt=$(( T1 - T0 > 0 ? T1 - T0 : 1 ))
    nnet=$(awk -v a="$IN0" -v b="$IN1" -v c="$OUT0" -v d="$OUT1" -v t="$dt" 'BEGIN { printf "%.2f↓ %.2f↑", (b - a) / t / 1e6, (d - c) / t / 1e6 }')
    IN0=$IN1; OUT0=$OUT1; T0=$T1

    printf "%-8s | %-6s %-6s | %-6s %-6s | %-8s | %-13s %-13s\n" "$(date +%T)" "$mcpu" "$tcpu" "$mmem" "$vmem" "$PRESS" "$mnet" "$nnet"
    SUM_CPU=$(awk -v s="$SUM_CPU" -v a="$mcpu" -v b="$tcpu" 'BEGIN { d = a - b; print s + (d < 0 ? -d : d) }')
    SUM_MEM=$(awk -v s="$SUM_MEM" -v a="$mmem" -v b="$vmem" 'BEGIN { d = a - b; print s + (d < 0 ? -d : d) }')
    BIAS_CPU=$(awk -v s="$BIAS_CPU" -v a="$mcpu" -v b="$tcpu" 'BEGIN { print s + a - b }')
    BIAS_MEM=$(awk -v s="$BIAS_MEM" -v a="$mmem" -v b="$vmem" 'BEGIN { print s + a - b }')
    [ "$i" -lt "$ROUNDS" ] && sleep "$GAP"
done
MAVG=$(awk 'NR > 2 { sub(/.*cpu=/, ""); s += $1; n++ } END { printf "%.1f", s / n }' "$LOG")
TAVG=$(awk 'NR > 2 { gsub("%", ""); s += $3 + $5; n++ } END { printf "%.1f", s / n }' "$TOPLOG")
echo "tüm süre CPU ortalaması: mystat %$MAVG, top %$TAVG ($(awk -v a="$MAVG" -v b="$TAVG" 'BEGIN { printf "%+.1f", a - b }') puan)"
# Ağ patlamalıdır (tek tek turlar anlık 2 sn'yi tur ortalamasıyla karşılaştırır); tüm süre ortalaması asıl ölçüt.
NAVG=$(awk -v skip="$SKIP" 'NR > skip { sub(/.*down=/, ""); sub(/ up=/, " "); d += $1; u += $2; n++ } END { printf "%.3f↓ %.3f↑", d / n, u / n }' "$LOG")
read -r INE OUTE < <(net); TE=$(date +%s)
echo "tüm süre ağ ortalaması (MB/s): mystat $NAVG, netstat $(awk -v a="$INS" -v b="$INE" -v c="$OUTS" -v d="$OUTE" -v t="$(( TE - TS ))" 'BEGIN { printf "%.3f↓ %.3f↑", (b - a) / t / 1e6, (d - c) / t / 1e6 }')"
awk -v c="$SUM_CPU" -v m="$SUM_MEM" -v bc="$BIAS_CPU" -v bm="$BIAS_MEM" -v n="$ROUNDS" 'BEGIN {
    printf "turlarda ortalama fark (mystat − araç): CPU %+.1f puan, bellek %+.1f puan\n", bc / n, bm / n
    printf "turlarda ortalama mutlak fark:          CPU %.1f puan, bellek %.1f puan (anlık zamanlama oynaması dahil)\n", c / n, m / n }'
