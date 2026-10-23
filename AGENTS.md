# Agent notes: pokeemerald-rogue (gooz3 fork)

Pokémon Emerald Rogue, a roguelike ROM hack built on the pret pokeemerald decomp.
`INSTALL.md` and `README.md` are the stock pret docs and don't cover this fork's setup. Use this file instead.

## Repo layout

- `origin` = `xgooz3x/pokeemerald-rogue` (our fork). Work on `gooz3-dev` (the default branch) or feature branches off it.
- `upstream` = `Pokabbie/pokeemerald-rogue`. Local `vanilla` tracks `upstream/vanilla`. To pull upstream changes, run `git switch vanilla && git pull`, then merge into `gooz3-dev`.
- Rogue code is mostly `src/rogue_*.c`, `include/rogue*.h`, `include/constants/rogue.h`, and Poryscript in `data/scripts/Rogue/`.

## Build (NixOS)

The dev machine runs NixOS. `shell.nix` provides the toolchain and mGBA.

```bash
scripts/build_nix.sh             # debug ROM -> pokeemerald.gba (~10s incremental)
scripts/build_nix.sh RELEASE=1   # release ROM
scripts/smoke_test_nix.sh        # headless mGBA boot; PASS = reached title screen
nix-shell --run 'mgba-qt pokeemerald.gba'   # play it
```

Quirks the scripts already handle. Keep them in mind if you build some other way:
- The Makefile hardcodes `MODERN := 1`, so the game is compiled with `arm-none-eabi-gcc`. `DEVKITARM` must point at that toolchain; `shell.nix` sets it.
- The Makefile hardcodes `SHELL := /bin/bash`, which doesn't exist on NixOS. `build_nix.sh` overrides it.
- `hardeningDisable = [ "fortify" ]` in `shell.nix` is required. Without it, QueryBaker (`tools/Pokabbie/Build/QueryBaker`, which runs from the second build onward) loops forever because `BakeHelpers.h` defines `__attribute__` away.
- agbcc isn't used to compile, but its headers must exist in `tools/agbcc/` (gitignored). On a fresh clone:
  ```bash
  cd .. && git clone https://github.com/pret/agbcc && cd agbcc
  nix-shell ../pokeemerald-rogue/shell.nix --run 'unset DEVKITARM; export SHELL=$(command -v bash); ./build.sh && ./install.sh ../pokeemerald-rogue'
  ```
- The first build runs `./init_deps.sh`, which downloads Poryscript and the UPS patcher into `tools/`.
- Rootless podman can't pull images on this machine (no subuid/subgid ranges), so the CI container (`devkitpro/devkitarm`) isn't an option locally.

## Making changes

1. Edit, then run `scripts/build_nix.sh` and `scripts/smoke_test_nix.sh`.
2. Play-test anything gameplay-related in mGBA. The smoke test only proves the game boots.
3. If you change save data layout (`gRogueSaveBlock`, the structs in `include/rogue.h`), bump the save version like upstream does, or old saves break.
4. Don't hand-edit generated files such as `src/data/rogue_bake_data.h` and `rogue_exported_stats.json`. QueryBaker regenerates them during the build.
5. The `vanilla` branch has no unit-test suite. `scripts/launch_build_test.sh` (`TEST=1`) is upstream's and doesn't work here.

## Git / GitHub

- `gh` defaults to the fork. Never push to `upstream`.
- If `git push` fails with `/usr/bin/gh: No such file or directory`, the global credential helper is stale. Run `gh auth setup-git`, or push once with:
  `git -c credential.helper= -c "credential.helper=!$(which gh) auth git-credential" push`
- CI (`.github/workflows/build.yml`) only runs on `vanilla`, `vanilla-dev`, `expansion` and `expansion-dev`, not on `gooz3-dev`.
