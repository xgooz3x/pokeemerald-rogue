#!/usr/bin/env bash
# Build the ROM on NixOS using shell.nix.
# Usage: scripts/build_nix.sh [RELEASE=1] [other make args]
set -euo pipefail
cd "$(dirname "$0")/.."

if [ ! -d tools/poryscript ] || [ ! -d tools/ups ]; then
  nix-shell --run ./init_deps.sh
fi

# Makefile hardcodes SHELL := /bin/bash, which NixOS lacks.
nix-shell --run "make -j\$(nproc) -O SHELL=\$(command -v bash) .SHELLFLAGS=\"-o pipefail -c\" $*"
