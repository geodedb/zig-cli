#!/usr/bin/env bash
# Enforce the 800-line guidance for Zig source files (GAP-0096 / #34).
set -euo pipefail
LIMIT=800
status=0
for f in "$@"; do
  case "$f" in
    *.zig) ;;
    *) continue ;;
  esac
  lines=$(wc -l < "$f")
  if [ "$lines" -gt "$LIMIT" ]; then
    echo "ERROR: $f has $lines lines (limit $LIMIT). Split it (see docs/superpowers/plans/2026-06-12-audit-iter1-refactor.md)."
    status=1
  fi
done
exit $status
