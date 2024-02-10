#!/usr/bin/env bash

set -x

exec ./nix-build-debug.sh '<nixpkgs>' -A hello "$@"
