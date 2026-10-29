#!/bin/bash
# Ağ ayrıntılarını sistem araçlarıyla karşılaştırır (plan 2e, Task 8). Salt okunur; ağda yalnızca yönlendiriciye ping.
# Kullanım: tools/net-check.sh [tur=3] [aralık_sn=6]
#   DEBUG mystat'ı --log-values --section net ile başlatır (monitör Ağ bölümünde açılır: nettop akışı, ping, bağlantı).
#   Her turda mystat'ın yönlendiricisi, gecikmesi ve en çok indireni; yanında `route -n get default`, `ping -c 3`
#   ortalaması ve aynı anda başvuru olarak `nettop -P -L 2 -d` ile en çok bayt alan süreç. Sonda Ağ bölümü açıkken
#   mystat'ın 30 sn'lik işlemci zamanı ve alt süreci olmadığı (uygulama bazında ağ çekirdek soket sayaçlarından).
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
sleep 10   # nettop'un ilk örneği ve birkaç ping

field() { sed -E "s/.* $1=([^ ]+).*/\1/" <<< "$2"; }
secs() { ps -o time= -p "$1" 2>/dev/null | awk -F'[:.]' '{ if (NF == 3) print $1 * 60 + $2 + $3 / 100; else print 0 }'; }
printf "%-8s | %-13s %-13s | %-6s %-6s | %-22s %s\n" saat mystat_rtr route_gw lat ping top nettop_top
for i in $(seq 1 "$ROUNDS"); do
    M=$(tail -1 "$LOG")
    GW=$(route -n get default 2>/dev/null | awk '/gateway:/ { print $2 }')
    PING=$({ ping -c 3 -q "$GW" 2>/dev/null || true; } | awk -F'/' '/round-trip/ { print $5 }')
    NT=$({ nettop -P -c -L 2 -d -J bytes_in -x 2>/dev/null || true; } | awk -F, '/^,bytes_in/ { n++; next } n == 2 && $2 + 0 > max { max = $2 + 0; name = $1 } END { print name }')
    printf "%-8s | %-13s %-13s | %-6s %-6s | %-22s %s\n" "$(date +%T)" "$(field rtr "$M")" "${GW:-—}" "$(field lat "$M")" "${PING:-—}" \
        "$(field top "$M")" "${NT:-—}"
    [ "$i" -lt "$ROUNDS" ] && sleep "$GAP"
done

# Uygulama bazında ağ çekirdek soket sayaçlarından (alt süreç yok): Ağ bölümü açıkken 30 sn'lik işlemci zamanı.
echo "alt süreçler: $(pgrep -P "$PID" | tr '\n' ' ')(boş olmalı)"
A0=$(secs "$PID"); sleep 30; A1=$(secs "$PID")
awk -v a="$A0" -v A="$A1" 'BEGIN { printf "Ağ bölümü açık, 30 sn işlemci: mystat %.2f sn (dakikaya %.2f sn)\n", A - a, (A - a) * 2 }'
