# Build environment for NixOS. Usage: nix-shell --run 'make -j$(nproc)'
# Replaces devkitARM: the Makefile builds with MODERN=1 using arm-none-eabi-gcc.
# agbcc must still be installed into tools/agbcc (its headers are scanned).
{ pkgs ? import <nixpkgs> { } }:

pkgs.mkShell {
  packages = with pkgs; [
    gcc-arm-embedded
    gnumake
    gcc
    pkg-config
    libpng
    zlib
    elfutils
    git
    wget
    unzip
    mgba
  ];

  # QueryBaker defines __attribute__ away, which breaks glibc fortify wrappers
  # (memcpy recurses forever). NixOS enables fortify by default; Ubuntu CI does not.
  hardeningDisable = [ "fortify" ];

  # Makefile uses $(DEVKITARM)/bin as its toolchain dir.
  shellHook = ''
    export DEVKITARM=${pkgs.gcc-arm-embedded}
  '';
}
