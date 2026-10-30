#!/bin/bash
# Compares the home folder scan with `du`. Read-only; nothing is deleted.
# Usage: tools/disk-check.sh
#   Runs the DEBUG mystat with --scan-home (scan without UI, temporary cache): total, duration, CPU time,
#   inaccessible folders, memory (before / peak / ready / after the tree is released; RSS and the Activity Monitor footprint). Then prints the 10 largest items and the total
#   side by side with `du -sk` (difference %). `du` skips protected folders the same way.
set -euo pipefail
export LC_ALL=C
export MallocLargeCache=0   # same as the bundled LSEnvironment
cd "$(dirname "$0")/.."
swift build -q
OUT="$(.build/debug/mystat --scan-home)"
head -1 <<< "$OUT" | tr ' ' '\n'
echo
printf "%-28s %12s %12s %8s\n" item mystat_GB du_GB diff_%
pct() { awk -v a="$1" -v b="$2" 'BEGIN { if (b == 0) print "—"; else printf "%+.2f", (a - b) / b * 100 }'; }
gb() { awk -v v="$1" 'BEGIN { printf "%.2f", v / 1e9 }'; }
while IFS=$'\t' read -r _ name bytes; do
    du_b=$(( $( { du -sk "$HOME/$name" 2>/dev/null || true; } | cut -f1) * 1024 ))   # du returns 1 for a protected subfolder
    printf "%-28s %12s %12s %8s\n" "$name" "$(gb "$bytes")" "$(gb "$du_b")" "$(pct "$bytes" "$du_b")"
done < <(grep '^item' <<< "$OUT")
total=$(head -1 <<< "$OUT" | sed -E 's/.*total_gb=([0-9.]+).*/\1/')
du_total=$(( $( { du -sk "$HOME" 2>/dev/null || true; } | cut -f1) * 1024 ))
printf "%-28s %12s %12s %8s\n" "~ (total)" "$total" "$(gb "$du_total")" "$(pct "$(awk -v t="$total" 'BEGIN { printf "%.0f", t * 1e9 }')" "$du_total")"
