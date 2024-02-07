#!/usr/bin/env bash

d=$(dirname "$0")

exec nix-shell "$@" --run "bash --noprofile --rcfile ${d@Q}/nix-build-debug.env.sh"
