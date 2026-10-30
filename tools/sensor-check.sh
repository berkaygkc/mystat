#!/bin/bash
# Prints sensor values side by side.
# Usage: tools/sensor-check.sh [rounds=5] [interval_secs=10] [--load]
#   Starts the DEBUG mystat with --log-values --section sys; because the monitor is open, GPU temperature, IOReport power and GPU
#   apps are read as well. Each round prints mystat's chip/GPU temperature, fan, system power (PSTR), CPU/GPU watts and GPU
#   usage, next to `ioreg`'s GPU usage and `pmset -g therm`. --load: loads 4 cores with `yes` (stopped at the end).
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
sleep 15   # SMC key discovery (on first launch) and two power samples
if [ "$LOAD" = "--load" ]; then
    for _ in 1 2 3 4; do yes > /dev/null & YES+=($!); done
    echo "load: 4 × yes"
    sleep 10
fi

field() { sed -E "s/.* $1=([0-9.]+).*/\1/" <<< "$2"; }
printf "%-8s | %-5s %-5s | %-6s %-6s | %-6s %-6s | %-5s %-5s | %s\n" time chip gpuT fan pstr cpuW gpuW gpu ioreg thermal
for i in $(seq 1 "$ROUNDS"); do
    M=$(tail -1 "$LOG")
    IO=$(ioreg -r -c IOAccelerator -d 1 | grep -o '"Device Utilization %"=[0-9]*' | head -1 | cut -d= -f2)
    TH=$(pmset -g therm 2>/dev/null | awk -F'= ' '/CPU_Speed_Limit/ { print "speed limit %" $2 } /thermal warning level/ { print }' | head -1)
    printf "%-8s | %-5s %-5s | %-6s %-6s | %-6s %-6s | %-5s %-5s | %s\n" "$(date +%T)" "$(field chip "$M")" "$(field gpuT "$M")" \
        "$(field fan "$M")" "$(field pstr "$M")" "$(field cpuW "$M")" "$(field gpuW "$M")" "$(field gpu "$M")" "${IO:-?}" "${TH:-—}"
    [ "$i" -lt "$ROUNDS" ] && sleep "$GAP"
done
