#!/usr/bin/env bash

curl -LO https://github.com/NixOS/nix/raw/master/src/nix/get-env.sh

diff=$(git diff get-env.sh)

if [ -z "$diff"]; then
    echo "no change"
    exit
fi

echo "get-env.sh has changed"
set -x
git add get-env.sh
git commit -m "up get-env.sh"
