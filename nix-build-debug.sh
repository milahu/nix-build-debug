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

# test arrays
# declare -A test_assoc=([a]=1 [b]=2 [c]=3)
# test_array=(1 2 3 4 5)

nix_build_env_expr='
    with import '"$pkgsPath"' {};
    '"$pkgAttr"'.overrideAttrs (oldAttrs: {
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

echo writing env.json
echo "$env_json" >env.json

echo "FIXME generate rcfile for bash" >&2

bashrc_path="bashrc.sh"
echo "writing $bashrc_path"
{
    # variables
    echo "$env_json" | jq -r '
        .variables | to_entries[] | select(.key != "buildCommand") |
        if .value.type == "exported" then
            "export " + (
                if .key == "buildCommand_bak_nix_build_debug" then "buildCommand" else .key end
            ) + "=" + (.value.value | @sh)
        elif .value.type == "var" then
            .key + "=" + (.value.value | @sh)
        elif .value.type == "array" then
            .key + "=(" + (.value.value | map( @sh "\n    \(.)" ) | join("")) + "\n)"
        elif .value.type == "associative" then
            "declare -A \(.key)=(\(
                .value.value | to_entries | map( @sh "\n    [\(.key)]=\(.value)" ) | join("")
            )\n)"
        else
            "# \(.key) has type \(.value.type)"
        end
    '

    # functions
    echo "$env_json" | jq -r '.bashFunctions | to_entries[] | "\(.key)() {\(.value)}"'

    # FIXME handle .structuredAttrs

} >"$bashrc_path"

exit

exec nix-shell "$@" --run "NIX_BUILD_DEBUG_ROOT=${PWD@Q} bash --noprofile --rcfile ${d@Q}/nix-build-debug.env.sh"
