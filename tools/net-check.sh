#!/bin/bash
# Compares network details with system tools. Read-only; the only network traffic is a ping to the router.
# Usage: tools/net-check.sh [rounds=3] [interval_secs=6]
#   Starts the DEBUG mystat with --log-values --section net (the monitor opens on the Network section: nettop stream, ping, connection).
#   Each round prints mystat's router, latency and top downloader, next to `route -n get default`, the `ping -c 3`
#   average and, as a reference, the process receiving the most bytes according to `nettop -P -L 2 -d`. At the end, with the
#   Network section open, mystat's CPU time over 30 s and a check that it has no child processes (per-app network comes from kernel socket counters).
set -euo pipefail
export LC_ALL=C
cd "$(dirname "$0")/.."
ROUNDS="${1:-3}"
GAP="${2:-6}"
swift build -q
LOG="$(mktemp -t mystat-net)"
.build/debug/mystat --log-values --section net > "$LOG" 2>/dev/null &
PID=$!
disown "$PID"
cleanup() { kill "$PID" 2>/dev/null || true; rm -f "$LOG"; }
trap cleanup EXIT
sleep 10   # nettop's first sample and a few pings

field() { sed -E "s/.* $1=([^ ]+).*/\1/" <<< "$2"; }
secs() { ps -o time= -p "$1" 2>/dev/null | awk -F'[:.]' '{ if (NF == 3) print $1 * 60 + $2 + $3 / 100; else print 0 }'; }
printf "%-8s | %-13s %-13s | %-6s %-6s | %-22s %s\n" time mystat_rtr route_gw lat ping top nettop_top
for i in $(seq 1 "$ROUNDS"); do
    M=$(tail -1 "$LOG")
    GW=$(route -n get default 2>/dev/null | awk '/gateway:/ { print $2 }')
    PING=$({ ping -c 3 -q "$GW" 2>/dev/null || true; } | awk -F'/' '/round-trip/ { print $5 }')
    NT=$({ nettop -P -c -L 2 -d -J bytes_in -x 2>/dev/null || true; } | awk -F, '/^,bytes_in/ { n++; next } n == 2 && $2 + 0 > max { max = $2 + 0; name = $1 } END { print name }')
    printf "%-8s | %-13s %-13s | %-6s %-6s | %-22s %s\n" "$(date +%T)" "$(field rtr "$M")" "${GW:-—}" "$(field lat "$M")" "${PING:-—}" \
        "$(field top "$M")" "${NT:-—}"
    [ "$i" -lt "$ROUNDS" ] && sleep "$GAP"
done

# Per-app network comes from kernel socket counters (no child processes): CPU time over 30 s with the Network section open.
echo "child processes: $(pgrep -P "$PID" | tr '\n' ' ')(should be empty)"
A0=$(secs "$PID"); sleep 30; A1=$(secs "$PID")
awk -v a="$A0" -v A="$A1" 'BEGIN { printf "Network section open, 30 s CPU: mystat %.2f s (%.2f s per minute)\n", A - a, (A - a) * 2 }'
