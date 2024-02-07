#!/usr/bin/env bash

d=$(readlink -f "$(dirname "$0")")

# get-env.sh
# based on https://github.com/NixOS/nix/blob/master/src/nix/get-env.sh.gen.hh

# FIXME parse args
# example: nix-build-debug '<nixpkgs>' -A hello
pkgsPath="<nixpkgs>"
pkgAttr="hello"

nix_build_env_expr='
    with import '"$pkgsPath"' {};
    '"$pkgAttr"'.overrideAttrs (oldAttrs: {
        # TODO better
        name = "${oldAttrs.pname}-${oldAttrs.version}-env.json";
        outputs = ["out"];
        builder = '"$d"/get-env.sh';
    })
'
echo "nix_build_env_expr:$nix_build_env_expr" >&2 # debug

env_json_path=$(nix-build -E "$nix_build_env_expr")
echo "env_json_path=$env_json_path" >&2 # debug

echo "FIXME generate rcfile for bash" >&2
exit

exec nix-shell "$@" --run "NIX_BUILD_DEBUG_ROOT=${PWD@Q} bash --noprofile --rcfile ${d@Q}/nix-build-debug.env.sh"
