#!/usr/bin/env bash
# Boot the ROM headless in mGBA and check it reaches the title screen.
# Usage: scripts/smoke_test_nix.sh [rom] [timeout_seconds]
set -euo pipefail
cd "$(dirname "$0")/.."

ROM=${1:-pokeemerald.gba}
TIMEOUT=${2:-60}
MAP=${ROM%.gba}.map

ADDR=$(awk '$2 == "CB2_InitTitleScreen" { print $1; exit }' "$MAP")
if [ -z "$ADDR" ]; then
  echo "FAIL: CB2_InitTitleScreen not found in $MAP"
  exit 1
fi

# mGBA's CLI debugger: break on the title screen, run, and quit once it's hit.
OUT=$( (printf 'break %s\ncontinue\nquit\n' "$ADDR") |
  nix-shell --run "SDL_VIDEODRIVER=dummy SDL_AUDIODRIVER=dummy timeout $TIMEOUT mgba -d $ROM" 2>&1 || true)

if grep -q "Hit breakpoint" <<<"$OUT"; then
  echo "PASS: $ROM reached the title screen"
else
  echo "FAIL: $ROM did not reach the title screen within ${TIMEOUT}s"
  tail -20 <<<"$OUT"
  exit 1
fi
