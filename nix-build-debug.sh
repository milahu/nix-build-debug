#!/usr/bin/env bash

# start a custom nix-shell with the nix-build-debug command

# the nix-build-debug command allows to
# list phases
# run phases
# continue running a phase from a line number

# example: nix-build-debug '<nixpkgs>' -A hello



this_dir=$(readlink -f "$(dirname "$0")")

# get-env.sh
# based on https://github.com/NixOS/nix/blob/master/src/nix/get-env.sh
get_env_path="$this_dir/get-env.sh"



# parse args

build_root="$PWD"
pkgs_path=""
pkg_attr=""
pure=false
chdir_build_root=false
debug=false
debug2=false

# add some basic tools to make the shell more usable
# TODO remove these extra paths in the phase scripts
# TODO expose CLI option
inherit_tools=(
    $PAGER # less
    $EDITOR # nano
    # TODO more
)

# TODO expose CLI option
inherit_paths=(
)

while (( "$#" )); do
    #echo "arg: ${1@Q}"
    case "$1" in
        --attr|-A)
            pkg_attr="$2"
            shift 2
            ;;
        --tempdir)
            build_root=$(mktemp -d -t nix-build-debug.XXXXXX)
            $debug &&
            echo "using temporary build root path ${build_root@Q}" >&2
            chdir_build_root=true
            shift 1
            ;;
        --debug)
            if $debug; then debug2=true; fi
            debug=true
            shift 1
            ;;
        # TODO more
        #--chroot) # use $build_root as root path
        *)
            pkgs_path="$1"
            shift 1
            ;;
    esac
done

debug_dir="$build_root/.nix-build-debug"
mkdir -p "$debug_dir"

if $debug; then
    echo
    echo "pkgs_path: ${pkgs_path@Q}" >&2
    echo "pkg_attr: ${pkg_attr@Q}" >&2
    echo "build_root: ${build_root@Q}" >&2
fi



function is_clean_path() {
    [ "$build_root" = "$(printf "%q" "$build_root")" ]
}



# check workdir path

#build_root="/path/to/dir with spaces" # test
#build_root="/path/to/dir_no_spaces" # test

if ! is_clean_path "$build_root"; then
    build_root_url="file://$build_root"
    echo
    echo "error: ${build_root_url@Q} is not a valid URL" >&2
    echo
    echo "nix-build requires a clean workdir path: no spaces, no special chars" >&2
    echo "a dirty workdir path can break the build" >&2
    echo "see also https://github.com/NixOS/nixpkgs/issues/177952" >&2
    echo
    echo "hint: use 'nix-build-debug ... --tempdir' to run the build in a tempdir" >&2
    echo "by default, the build will run in the current workdir" >&2
    exit 1
fi



for tool in "${inherit_tools[@]}"; do
    if ! tool_path=$(command -v "$tool"); then
        $debug &&
        echo "adding tool ${tool@Q} failed: not found in \$PATH" >&2
        continue
    fi
    $debug &&
    echo "adding tool ${tool@Q} from tool_path ${tool_path@Q}" >&2
    # resolve /run/current-system/sw/bin/* to /nix/store/*/bin/*
    tool_path=$(readlink -f "$tool_path")
    tool_path="${tool_path%/*}"
    inherit_paths+=("$tool_path")
done



# get the build environment from nix-build

if ! is_clean_path "$get_env_path"; then
    new_get_env_path=$(mktemp --suffix=.get-env.sh)
    echo "using temporary get-env.sh path ${new_get_env_path@Q}" >&2
    cp "$get_env_path" "$new_get_env_path"
    get_env_path="$new_get_env_path"
fi

env_json_start="################ env.json start ################"
env_json_end="################ env.json end ################"

# test arrays
# declare -A test_assoc=([a]=1 [b]=2 [c]=3)
# test_array=(1 2 3 4 5)

nix_build_env_expr=$(

    echo "with import $pkgs_path {};"

    echo "$pkg_attr.overrideAttrs (oldAttrs: {"

    # create backup of buildCommandPath
    echo "  buildCommandPath_bak_nix_build_debug ="
    # test: use this script as builder
    #echo "    let oldAttrs = { buildCommandPath = $0; }; in"
    echo "    if oldAttrs ? buildCommandPath then oldAttrs.buildCommandPath"
    echo "    else null;"

    # create backup of buildCommand
    echo "  buildCommand_bak_nix_build_debug ="
    # test
    #echo "    let oldAttrs = { buildCommand = ''echo hello im a string buildCommand''; }; in"
    echo "    if oldAttrs ? buildCommand then oldAttrs.buildCommand"
    echo "    else null;"

    # test: this should override the buildPhase function
    # env.json: {"variables": {"buildPhase": {"type": "exported", "value": "echo hello im a string buildPhase"}}
    #echo "  buildPhase = ''echo hello im a string buildPhase'';"

    # test
    # prePhases is exported as string
    # weird, because build functions use array syntax "${prePhases[*]}"
    # env.json: {"variables": {"prePhases": {"type": "exported", "value": "prePhaseTest1 prePhaseTest2"}}
    #echo "  prePhases = [ ''prePhaseTest1'' ''prePhaseTest2'' ];"

    echo "  buildCommand = ''"
    # run get-env.sh to write env.json to $out
    echo "    source \${$get_env_path}"
    # print env.json
    echo "    echo ${env_json_start@Q}"
    echo "    cat \$out"
    echo "    echo"
    echo "    echo ${env_json_end@Q}"
    # make the build fail to not pollute the nix store
    echo "    exit 1"
    echo "  '';"

    echo "})"
)

$debug &&
echo "nix_build_env_expr:"$'\n'"$nix_build_env_expr" >&2

# TODO check
# throw Error("'%s' needs to evaluate to a single derivation, but it evaluated to %d derivations",

$debug &&
echo "getting the build environment ..." >&2

# this takes some seconds
nix_build_out=$(nix-build -E "$nix_build_env_expr" 2>&1)

# extract json from build output
env_json=$(echo "$nix_build_out" | awk "/^$env_json_start$/{flag=1; next} /^$env_json_end$/{flag=0} flag")
#echo "env_json: $env_json" >&2

if [ -z "$env_json" ]; then
    echo "error: failed to get the build environment" >&2
    echo "output from nix-build:" >&2
    echo "$nix_build_out" >&2
    exit 1
fi

# cleanup
unset nix_build_env_expr
unset nix_build_out

# write json file
env_json_path="$debug_dir/etc/env.json"
mkdir -p "${env_json_path%/*}"

$debug &&
echo "writing $env_json_path"

echo "$env_json" >"$env_json_path"



# usually this is /bin/bash
builder=$(echo "$env_json" | jq -r '.variables.builder.value')

if ! echo "$builder" | grep -q '/bin/bash$'; then
    # nix/develop.cc
    # throw Error("'nix develop' only works on derivations that use 'bash' as their builder");
    echo "error: unsupported builder ${builder@Q}" >&2
    exit 1
fi

$debug &&
echo "using builder ${builder@Q}" >&2



# get list of build phases

# env.json: {"variables": {"prePhases": {"type": "exported", "value": "prePhaseTest1 prePhaseTest2"}}
# TODO? assert type == "exported"

# based on https://github.com/NixOS/nixpkgs/blob/master/pkgs/stdenv/generic/setup.sh
# note: runPhase also checks variables like "dontBuild"

phases=$(echo $(
    echo "$env_json" | jq -r '
        .variables |
        [
            .prePhases.value,
            "unpackPhase",
            "patchPhase",
            .preConfigurePhases.value, "configurePhase",
            .preBuildPhases.value, "buildPhase",
            "checkPhase",
            .preInstallPhases.value, "installPhase",
            .preFixupPhases.value, "fixupPhase",
            "installCheckPhase",
            .preDistPhases.value, "distPhase",
            .postPhases.value
        ] |
        map(select(. != null)) |
        .[]
    '
))

# test
#phases='badPhase!#/{}[]+-" buildPhase'

if ! echo "$phases" | grep -q -E '^[a-zA-Z0-9_ ]+$'; then
    echo "error: invalid phases ${phases@Q}" >&2
    exit 1
fi

$debug &&
echo "phases: $phases" >&2

phases_json_array="["
for phase in $phases; do
    phases_json_array+="\"$phase\","
done
phases_json_array="${phases_json_array:0: -1}]"

$debug &&
echo "phases_json_array: $phases_json_array" >&2



variables_path="$debug_dir/etc/variables.sh"
#variables_path="$debug_dir/var/variables.sh"
#variables_path="$debug_dir/var/state.sh"
mkdir -p "${variables_path%/*}"

$debug &&
echo "writing $variables_path" >&2

{
    # FIXME handle .structuredAttrs
    echo "$env_json" | jq -r '
        .variables | to_entries |
        map(select(
            (.key != "buildCommand")
            #and
            #(.key | test(".Phase$") == false)
            and
            (. as $val | '"$phases_json_array"' | index($val.key) == null)
        )) |
        map(
            if .key == "buildCommand_bak_nix_build_debug" then
                { key: "buildCommand", value: .value }
            else .
            end
        ) |
        .[] |
        if .value.type == "exported" then
            "export " + .key + "=" + (.value.value | @sh)
        elif .value.type == "var" then
            .key + "=" + (.value.value | @sh)
        elif .value.type == "array" then
            .key + "=(" + (
                .value.value | map( @sh "\n    \(.)" ) | join("")
            ) + "\n)"
        elif .value.type == "associative" then
            "declare -A " + .key + "=(" + (
                .value.value | to_entries | map( @sh "\n    [\(.key)]=\(.value)" ) | join("")
            ) + "\n)"
        else
            "# \(.key) has type \(.value.type)"
        end
    '
} >"$variables_path"



lib_dir="$debug_dir/lib"
mkdir -p "$lib_dir"
$debug &&
echo "writing functions to $lib_dir" >&2
function_name_list=()

while read function_name; do

    function_path="$lib_dir/$function_name.sh"
    function_name_list+=($function_name)

    $debug2 &&
    echo "writing $function_path" >&2

    {
        echo "$function_name() {"
        echo "$env_json" | jq -r ".bashFunctions.$function_name"
        echo
        echo "}"
    } >"$function_path"

done < <(
    # FIXME also use phase string variables as phase functions
    echo "$env_json" | jq -r '.bashFunctions | keys[]'
)



for phase in $phases; do

    # example: buildPhase_from_string
    function_name="${phase}_from_string"

    function_body=$(echo "$env_json" | jq -r ".variables.$phase.value // empty")
    if [ -z "$function_body" ]; then
        # ignore empty strings
        # usually we use the noop command ":" to disable a phase
        #   buildPhase = ":";
        continue
    fi

    # create the function
    #   buildPhase_from_string() { $buildPhase }
    # we cannot overwrite the buildPhase function
    # because the buildPhase string can call the original buildPhase function

    function_path="$lib_dir/$function_name.sh"
    function_name_list+=($function_name)

    $debug &&
    echo "writing $function_path" >&2

    {
        echo "$function_name() {"
        echo "$function_body"
        echo "}"
    } >"$function_path"

done



# patch the runPhase function
#   eval "${!curPhase:-$curPhase}"
# should be
#   if declare -F ${curPhase}_from_string >/dev/null; then ${curPhase}_from_string; else $curPhase; fi

function_path="$lib_dir"/runPhase.sh
$debug &&
echo "patching the runPhase function in ${function_path@Q} to call our \${curPhase}_from_string functions" >&2
sed_script='s/eval "${!curPhase:-$curPhase}";/'
sed_script+='if declare -F ${curPhase}_from_string >\/dev\/null; then '
sed_script+='${curPhase}_from_string; else $curPhase; fi/'
sed -i "$sed_script" "$function_path"



# fix output paths

# the builder should write files only to $build_root
# not to the nix store

outputs=$(echo "$env_json" | jq -r ".variables.outputs.value // empty")
if [ -z "$outputs" ]; then
    echo "error: the derivation has no outputs" >&2
    exit 1
fi
$debug &&
echo "build outputs: $outputs" >&2

# TODO move this up to the jq script
$debug &&
echo "patching the output paths in ${variables_path@Q} so the builder does not write to the nix store" >&2
sed_script=""
is_first=true
for output in $outputs; do
    if $is_first; then
        output_path="$build_root/result"
        is_first=false
    else
        output_path="$build_root/result-$output"
    fi
    $debug &&
    echo "using output path ${output_path@Q}" >&2
    sed_script+="s|^export $output=|export $output=${output_path@Q}\n${output}_bak_nix_build_debug=|; "
done

# env["NIX_BUILD_TOP"] = env["TMPDIR"] = env["TEMPDIR"] = env["TMP"] = env["TEMP"] = *tmp;
nix_build_top_path="$build_root/build"
for name in NIX_BUILD_TOP TMPDIR TEMPDIR TMP TEMP; do
    $debug &&
    echo "using $name path ${nix_build_top_path@Q}" >&2
    sed_script+="s|^export $name='/build'|export $name=${nix_build_top_path@Q}|; "
done

sed -i "$sed_script" "$variables_path"



# auto script = makeRcScript(store, buildEnvironment, (Path) tmpDir);

# TODO merge bashrc and nix-build-debug.env.sh
bashrc_path="$debug_dir/etc/bashrc.sh"
mkdir -p "${bashrc_path%/*}"
$debug &&
echo "writing $bashrc_path"
{
    # always clear PATH.
    # when nix-shell is run impure, we rehydrate it with the `p=$PATH` above
    echo "unset PATH"

    echo "dontAddDisableDepTrack=1"

    # TODO structuredAttrsRC

    #echo "[ -e \"$stdenv_setup\" ] && source \"$stdenv_setup\""
    echo "source ${variables_path@Q}"
    for function_name in ${function_name_list[@]}; do
        function_path="$lib_dir/$function_name.sh"
        echo "source ${function_path@Q}"
    done

    if ! $pure; then
        echo "[ -n \"\$PS1\" ] && [ -e ~/.bashrc ] && source ~/.bashrc"
        echo "p=\"\$PATH\""
    fi

    if ! $pure; then
        echo 'PATH="$PATH:$p"'
        echo "unset p"
    fi

    shell_dir=$(dirname "$shell")
    if [[ "$shell_dir" != "." ]]; then
        echo "PATH=${shell_dir@Q}:\"\$PATH\""
    fi
    echo "SHELL=${shell@Q}"
    echo "BASH=${shell@Q}"

    # dont exit the shell on error
    # "set -e" is used in the phase scripts, to stop on error
    echo "set +e"

    echo 'if [ -n "$PS1" -a -z "$NIX_SHELL_PRESERVE_PROMPT" ]; then'
    prompt_color="1;31m"
    ((UID)) && prompt_color="1;32m"
    #echo "PS1='\nnix-build-debug $ '"
    echo "PS1='\n\[\033[$prompt_color\]nix-build-debug \\$\[\033[0m\] '"
    echo "fi"

    echo "if [ \"\$(type -t runHook)\" = function ]; then runHook shellHook; fi"

    echo "unset NIX_ENFORCE_PURITY"

    echo "shopt -u nullglob"

    echo "unset TZ"
    if [ -n "$TZ" ]; then
        echo "export TZ=${TZ@Q}"
    fi

    echo "shopt -s execfail"

    # the $phases variable is set in nix-build, but not in nix-shell
    echo "phases=${phases@Q}"

    # prepend paths in reverse order to $PATH
    # so the first path in inherit_paths has the highest priority
    for ((idx = ${#inherit_paths[@]} - 1; idx >= 0; idx--)); do
        echo "PATH=${inherit_paths[$idx]@Q}:\"$PATH\""
    done

    # add completions
    echo 'complete -W "$phases" -o nosort runPhase'

    # envCommand is empty when "--command" and "--run" are not used

    if $chdir_build_root; then
        echo "cd ${build_root@Q}"
    fi

    #echo "echo 'starting the nix-build-debug shell'"
    #echo "echo 'next steps:'"
    #echo "echo '  nix-build-debug help'"
    echo "echo 'hint: nix-build-debug help'"

} >"$bashrc_path"



shell="$NIX_BUILD_SHELL"
if [ -z "$shell" ]; then
    # $builder is a non-interactive bash shell
    # which is painful to use for humans
    if shellDrv=$(nix-build '<nixpkgs>' -A bashInteractive); then
        shell="$shellDrv/bin/bash"
    else
        echo "notice: will use bash from your environment" >&2
        shell="bash"
    fi
fi



# TODO? run this in a clean env
# inherit only requires envs

exec "$shell" --noprofile --rcfile "$bashrc_path"
