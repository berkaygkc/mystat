#!/bin/bash
# Sensör değerlerini yan yana yazar (plan 2c, Task 7).
# Kullanım: tools/sensor-check.sh [tur=5] [aralık_sn=10] [--load]
#   DEBUG mystat'ı --log-values --section sys ile başlatır; monitör açık olduğu için GPU sıcaklığı, IOReport gücü ve GPU
#   uygulamaları da okunur. Her turda mystat'ın çip/GPU sıcaklığı, fan, sistem gücü (PSTR), CPU/GPU watt ve GPU
#   kullanımı; yanında `ioreg`'in GPU kullanımı ve `pmset -g therm`. --load: 4 çekirdeği `yes` ile yükler (sonda kapatır).
set -euo pipefail
export LC_ALL=C
cd "$(dirname "$0")/.."
ROUNDS="${1:-5}"
GAP="${2:-10}"
LOAD="${3:-}"
swift build -q
LOG="$(mktemp -t mystat-sensors)"
.build/debug/mystat --log-values --section sys > "$LOG" 2>/dev/null &
PID=$!
disown "$PID"
YES=()
cleanup() { kill "$PID" 2>/dev/null; for y in "${YES[@]:-}"; do [ -n "$y" ] && kill "$y" 2>/dev/null; done; rm -f "$LOG"; }
trap cleanup EXIT
sleep 15   # SMC anahtar keşfi (ilk açılışta) ve iki güç örneği
if [ "$LOAD" = "--load" ]; then
    for _ in 1 2 3 4; do yes > /dev/null & YES+=($!); done
    echo "yük: 4 × yes"
    sleep 10
fi

field() { sed -E "s/.* $1=([0-9.]+).*/\1/" <<< "$2"; }
printf "%-8s | %-5s %-5s | %-6s %-6s | %-6s %-6s | %-5s %-5s | %s\n" saat çip gpuT fan pstr cpuW gpuW gpu ioreg termal
for i in $(seq 1 "$ROUNDS"); do
    M=$(tail -1 "$LOG")
    IO=$(ioreg -r -c IOAccelerator -d 1 | grep -o '"Device Utilization %"=[0-9]*' | head -1 | cut -d= -f2)
    TH=$(pmset -g therm 2>/dev/null | awk -F'= ' '/CPU_Speed_Limit/ { print "hız sınırı %" $2 } /thermal warning level/ { print }' | head -1)
    printf "%-8s | %-5s %-5s | %-6s %-6s | %-6s %-6s | %-5s %-5s | %s\n" "$(date +%T)" "$(field chip "$M")" "$(field gpuT "$M")" \
        "$(field fan "$M")" "$(field pstr "$M")" "$(field cpuW "$M")" "$(field gpuW "$M")" "$(field gpu "$M")" "${IO:-?}" "${TH:-—}"
    [ "$i" -lt "$ROUNDS" ] && sleep "$GAP"
done
