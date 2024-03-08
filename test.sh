#!/usr/bin/env bash

set -x

exec ./nix-build-debug.sh '<nixpkgs>' -A hello "$@"

# test buildPhase string
./nix-build-debug.sh '<nixpkgs>' -A openfx

# test buildCommand string
./nix-build-debug.sh '<nixpkgs>' -A rpmextract

# test buildCommandPath
# passAsFile = [ "buildCommand" ];
# this is almost never used

# test preBuild string
./nix-build-debug.sh '<nixpkgs>' -A tsocks
