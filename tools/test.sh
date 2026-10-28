#!/usr/bin/env bash
# Full verification: import (registers class_names), unit tests, end-to-end autoplay.
# Usage: tools/test.sh [seed ...]   (default seeds: 2 = live wire + drive, 99 = other street first)
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
G() { flock /tmp/godot.lock timeout "$1" godot --headless --path "$ROOT/game" "${@:2}"; }
mkdir -p "$ROOT/logs"
G 300 --import > "$ROOT/logs/import.log" 2>&1
if grep -qE "Parse Error|SCRIPT ERROR" "$ROOT/logs/import.log"; then grep -E "Parse Error|SCRIPT ERROR" "$ROOT/logs/import.log" | sort -u; exit 1; fi
G 300 -s res://tests/run_tests.gd > "$ROOT/logs/tests.log" 2>&1; T=$?
grep -E "FAIL|passed" "$ROOT/logs/tests.log"
RC=$T
for s in "${@:-2 99}"; do
  for mode in drive quick; do
    extra=(); [ "$mode" = quick ] && extra=(--quick)
    G 300 --fixed-fps 60 -- --autoplay --seed="$s" "${extra[@]}" > "$ROOT/logs/autoplay_${mode}_$s.log" 2>&1 || RC=1
    echo "autoplay seed=$s $mode: $(grep -E 'AUTOPLAY (PASS|FAIL)' "$ROOT/logs/autoplay_${mode}_$s.log" || echo 'NO RESULT (crash/hang)')"
    grep -E "FAIL:" "$ROOT/logs/autoplay_${mode}_$s.log" | head -5
  done
done
exit $RC
