#!/usr/bin/env bash

curl -L -o lib/stdenv-generic-setup.sh \
  https://github.com/NixOS/nixpkgs/raw/master/pkgs/stdenv/generic/setup.sh

awk '/^runPhase\(\) \{$/,/^\}$/' lib/stdenv-generic-setup.sh \
  >lib/stdenv-generic-runPhase.sh.bak
