#!/usr/bin/env bash

d=$(readlink -f "$(dirname "$0")")

# get-env.sh
# based on https://github.com/NixOS/nix/blob/master/src/nix/get-env.sh

# FIXME parse args
# example: nix-build-debug '<nixpkgs>' -A hello
pkgsPath="<nixpkgs>"
pkgAttr="hello"

env_json_start="################ env.json start ################"
env_json_end="################ env.json end ################"

nix_build_env_expr='
    with import '"$pkgsPath"' {};
    '"$pkgAttr"'.overrideAttrs (oldAttrs: {
        # TODO better
        name = "${oldAttrs.pname}-${oldAttrs.version}-env.json";
        outputs = ["out"];
        # create backup of buildCommand
        buildCommand_bak_nix_build_debug =
            if oldAttrs ? buildCommand then oldAttrs.buildCommand
            else null;
        buildCommand = '"''"'
            source ${'"$d"/get-env.sh'}
            echo "'"$env_json_start"'"
            cat "$out"
            echo
            echo "'"$env_json_end"'"
            exit 1 # make the build fail to not pollute the nix store
        '"''"';
    })
'
echo "nix_build_env_expr:$nix_build_env_expr" >&2 # debug

env_json=$(nix-build -E "$nix_build_env_expr" 2>&1)
env_json=$(echo "$env_json" | awk "/^$env_json_start$/{flag=1; next} /^$env_json_end$/{flag=0} flag")
echo "env_json: $env_json" >&2 # debug

echo "FIXME generate rcfile for bash" >&2
exit

exec nix-shell "$@" --run "NIX_BUILD_DEBUG_ROOT=${PWD@Q} bash --noprofile --rcfile ${d@Q}/nix-build-debug.env.sh"
