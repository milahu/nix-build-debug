#!/usr/bin/env bash

d=$(dirname "$0")

exec nix-shell "$@" --run "NIX_BUILD_DEBUG_ROOT=${PWD@Q} bash --noprofile --rcfile ${d@Q}/nix-build-debug.env.sh"
