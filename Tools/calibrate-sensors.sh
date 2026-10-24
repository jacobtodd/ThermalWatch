#!/bin/bash
# Finds which SMC temperature sensors are CPU cores: dump at idle, load every core
# for 30 s, dump again, print the biggest risers.
set -e
cd "$(dirname "$0")/.."
OUT=$(mktemp -d)
cp Tools/dump-temps.swift "$OUT/main.swift"
swiftc -O Shared/SMC.swift "$OUT/main.swift" -o "$OUT/dump"
"$OUT/dump" > "$OUT/idle.txt"
CORES=$(sysctl -n hw.ncpu)
for _ in $(seq "$CORES"); do yes > /dev/null & done
sleep 30
"$OUT/dump" > "$OUT/load.txt"
kill $(jobs -p) 2>/dev/null || true
join <(sort "$OUT/idle.txt") <(sort "$OUT/load.txt") | awk '{printf "%s %.1f -> %.1f (+%.1f)\n", $1, $2, $3, $3-$2}' | sort -t+ -k2 -rn
