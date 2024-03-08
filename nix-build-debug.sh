#!/usr/bin/env bash

# start a custom nix-shell with the nix-build-debug command

# the nix-build-debug command allows to
# list phases
# run phases
# continue running a phase from a line number

# example: nix-build-debug '<nixpkgs>' -A hello



this_dir=$(readlink -f "$0")
this_dir="${this_dir%/*}"

# TODO move to lib/get-env.sh

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
debug3=false

# add some basic tools to make the shell more usable
# TODO remove these extra paths in the phase scripts
# TODO expose CLI option
inherit_tools=(
    $PAGER # less
    $EDITOR # nano
    curl
    git
    realpath # coreutils-full
    man
    clear # ncurses
    # TODO more
)

# TODO expose CLI option
inherit_paths=(
)

inherit_envs=(
    # dont use HOME=/homeless-shelter
    HOME
    # fix: git clone: OpenSSL/3.0.12: error:16000069:STORE routines::unregistered scheme
    # usually these are unset in nix-build because builds run offline
    # /etc/ssl/certs/ca-bundle.crt from pkgs.cacert
    CURL_CA_BUNDLE
    SSL_CERT_FILE
)

ignore_envs=(
    # dont use NIX_SSL_CERT_FILE=/no-cert-file.crt
    NIX_SSL_CERT_FILE
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
        --workdir)
            build_root="$2"
            if ! [ -d "$build_root" ]; then
                echo "error: invalid workdir path: ${build_root@Q}" >&2
                exit 1
            fi
            build_root="$(readlink -f "$2")"
            $debug &&
            echo "using build root path ${build_root@Q}" >&2
            chdir_build_root=true
            shift 2
            ;;
        --debug)
            if $debug2; then debug3=true; fi
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



if [[ "$pkgs_path" == "." ]]; then
    pkgs_path="./."
elif [[ "$pkgs_path" == ".." ]]; then
    pkgs_path="../."
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



function get_json_array() {
    # ideally use jq: jq -c -n '[$v1, $v2]' --arg v1 aa --arg v2 bb
    # but here we have only simple strings, no special chars
    local -n bash_array="$1"
    local res=""
    res="["
    # TODO check if bash_array is array or string
    for str in "${bash_array[@]}"; do
        res+="\"$str\","
    done
    res="${res:0: -1}]"
    echo -n "$res"
}



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

    # test: empty phase
    # this is no error, stdenv will use the default unpackPhase function
    # nix-build -E 'with import <nixpkgs> {}; hello.overrideAttrs (o: { unpackPhase = ""; })'
    #echo '  unpackPhase = "";'

    # test: missing phase
    # nix-build -E 'with import <nixpkgs> {}; hello.overrideAttrs (o: { prePhases = ["missingPhase"]; })'
    #echo '  prePhases = ["missingPhase"];'

    echo "  buildCommand = ''"
    # run get-env.sh to write env.json to $out
    echo "    source \${$get_env_path}"
    # print env.json
    echo "    echo ${env_json_start@Q}"
    #echo '    outputs=""' # test: no outputs
    echo '    read firstOutput _ <<<"$outputs"'
    echo "    if [ -z \"\$firstOutput\" ]; then"
    # $ nix-shell -E 'with import <nixpkgs> {}; stdenv.mkDerivation { outputs = []; }'
    # error: list index 0 is out of bounds
    echo "      echo 'error: the derivation has no outputs'"
    echo "      exit 2"
    echo "    fi"
    #echo "    echo \"# firstOutput = ''\${firstOutput@Q}\"" # debug
    echo "    cat ''\${!firstOutput}"
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

if [ -z "$env_json" ] || ! echo "$env_json" | jq -c >/dev/null 2>&1; then
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
builder=$(echo "$env_json" | jq -r '.variables.builder.value // empty')

if ! echo "$builder" | grep -q '/bin/bash$'; then
    # nix/develop.cc
    # throw Error("'nix develop' only works on derivations that use 'bash' as their builder");
    echo "error: unsupported builder ${builder@Q}" >&2
    exit 1
fi

$debug &&
echo "using builder ${builder@Q}" >&2



if false; then
env_path=$(echo "$env_json" | jq -r '.variables.PATH.value // empty')

if [ -z "$env_path" ]; then
    echo "error: empty path" >&2
    exit 1
fi

$debug &&
echo "env_path: ${env_path@Q}" >&2
fi



# get list of build phases

# env.json: {"variables": {"prePhases": {"type": "exported", "value": "prePhaseTest1 prePhaseTest2"}}
# TODO? assert type == "exported"

# based on https://github.com/NixOS/nixpkgs/blob/master/pkgs/stdenv/generic/setup.sh
# note: runPhase also checks variables like "dontBuild"

# based on genericBuild
# buildCommandPath and buildCommand take precedence

phases=""

buildCommandPath=$(echo "$env_json" | jq -r '.variables.buildCommandPath_bak_nix_build_debug.value // empty')
buildCommand=""

if [ -f "$buildCommandPath" ]; then
    # non-standard
    phases="buildCommandPath"
else
    buildCommand=$(echo "$env_json" | jq -r '.variables.buildCommand_bak_nix_build_debug.value // empty')
fi

if [ -z "$phases" ] && [ -n "$buildCommand" ]; then
    # non-standard
    phases="buildCommand"
fi

if [ -z "$phases" ]; then
    phases=$(echo $(echo "$env_json" | jq -r '
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
    '))
fi

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



# no. this fails to pass the bash environment to the phases
# see also doc/bash-export-arrays.md
# instead, run the phases in subshells like
#   ( unpackPhase )
# where "set -e" and "exit 1" will only exit the subshell



# write variables

variables_path="$debug_dir/etc/variables.sh"
#variables_path="$debug_dir/var/variables.sh"
#variables_path="$debug_dir/var/state.sh"
mkdir -p "${variables_path%/*}"

ignore_envs_json_array=$(get_json_array ignore_envs)
$debug &&
echo "ignore_envs_json_array: $ignore_envs_json_array"

$debug &&
echo "writing $variables_path" >&2

{
    # FIXME handle .structuredAttrs
    echo "$env_json" | jq -r '
        .variables | to_entries |
        map(select(
            (.key != "buildCommand")
            and
            (. as $val | '"$ignore_envs_json_array"' | index($val.key) == null)
        )) |
        .[] |
        if .value.type == "exported" then
            "export " + (
                if .key == "buildCommand_bak_nix_build_debug" then "buildCommand"
                elif .key == "buildCommandPath_bak_nix_build_debug" then "buildCommandPath"
                else .key
                end
            ) + "=" + (.value.value | @sh)
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



# write non-phase functions

# write all stdenv functions to one file
# in most cases, these are read-only
# and creating many files is a waste of inodes

functions_path="$debug_dir/lib/functions.sh"
mkdir -p "${functions_path%/*}"

$debug &&
echo "writing $functions_path" >&2

{
    echo "$env_json" | jq -r '
        .bashFunctions | to_entries |
        map(select(
            (.key != "runPhase")
        ))
        .[] |
        .key + "() { " + (
            if .key == "showPhaseFooter" then
            # always show the phase footer
            # remove "(( delta < 30 )) && return;"
            .value | sub("\\(\\( delta < 30 \\)\\) && return;"; "")
            else
            .value
            end
        ) + "\n}"
    '

    echo "# patched runPhase function"
    cat "$this_dir"/lib/stdenv-generic-runPhase.sh

} >"$functions_path"



lib_dir="$debug_dir/lib"
mkdir -p "$lib_dir"



# TODO also patch genericBuild? does it stop on error?



# TODO add non-standard function setPhases
# to set the global "phases" variable
# which can be lost by running
#   phases="somePhase" genericBuild



# TODO genericBuild should accept command-line arguments
# to select the build phases



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
first_output_path=""
for output in $outputs; do
    if $is_first; then
        output_path="$build_root/result"
        first_output_path="$output_path"
        is_first=false
    else
        output_path="$build_root/result-$output"
    fi
    if [ -e "$output_path" ]; then
        echo "warning: output path exists: ${output_path@Q}" >&2
        echo "hint:" >&2
        echo "  rm -rf ${build_root@Q}/result*" >&2
    fi
    $debug &&
    echo "using output path ${output_path@Q}" >&2
    sed_script+="s|^export $output=|export $output=${output_path@Q}\n${output}_bak_nix_build_debug=|; "
done

# note: "prefix=..." not "export prefix=..."
sed_script+="s|^prefix=|prefix=${first_output_path@Q}\nprefix_bak_nix_build_debug=|; "

# env["NIX_BUILD_TOP"] = env["TMPDIR"] = env["TEMPDIR"] = env["TMP"] = env["TEMP"] = *tmp;
# no. stay in the current workdir
#nix_build_top_path="$build_root/build"
nix_build_top_path="$build_root"
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

    # TODO? source lib/.all_functions.sh from lib/.init-phase.sh

    #echo "[ -e \"$stdenv_setup\" ] && source \"$stdenv_setup\""

    echo "source ${variables_path@Q}"

    # non-standard: set default sourceRoot=.
    # TODO why? this breaks unpackPhase: if [ -z "$sourceRoot" ]; then
    #echo '[ -z "$sourceRoot" ] && sourceRoot=.'

    functions_path="$debug_dir/lib/functions.sh"
    echo "source ${functions_path@Q}"

    if ! $pure; then
        echo '# impure shell: load ~/.bashrc'
        echo 'if [ -n "$PS1" ] && [ -e ~/.bashrc ]; then'
        echo '  p="$PATH"'
        echo '  source ~/.bashrc'
        echo '  PATH="$PATH:$p"' # TODO dedupe path
        echo "  unset p"
        echo 'fi'
    fi

    shell_dir=$(dirname "$shell")
    if [[ "$shell_dir" != "." ]]; then
        echo "PATH=${shell_dir@Q}"':"$PATH"'
    fi
    echo "SHELL=${shell@Q}"
    echo "BASH=${shell@Q}"

    # dont exit the shell on error
    # "set -e" is used in the phase scripts, to stop on error
    echo "set +e"

    # disable job control in the debug shell
    # see doc/bash-trap-exit-try-catch.md
    # "set +m" has no effect here in bashrc
    # also "$shell +m" has no effect
    # -> use a patched version of bash
    #echo "set +m"
    # no. this would disable job control also for the parent shell
    # so Ctrl-Z would not work at all
    #echo "stty susp undef"

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

    for key in ${inherit_envs[@]}; do
        val=${!key}
        echo "export $key=${val@Q}"
    done

    echo "export SHELL=${shell@Q}"

    echo "export GZIP_NO_TIMESTAMPS=1"

    for cmd in jobs fg bg; do
        echo "function $cmd() {"
        echo "    echo '$cmd: command not found' >&2"
        echo "    echo 'note: this shell has no job control, because SIGTSTP (Ctrl-Z) would break subshells' >&2"
        echo "    return 127"
        echo "}"
    done

    # TODO what?
    echo "shopt -s execfail"

    # fix: syntax error near unexpected token `('
    echo "shopt -s extglob"

    # the $phases variable is set in nix-build, but not in nix-shell
    echo "phases=${phases@Q}"

    #echo "PATH=${env_path@Q}"
    # prepend paths in reverse order to $PATH
    # so the first path in inherit_paths has the highest priority
    for ((idx = ${#inherit_paths[@]} - 1; idx >= 0; idx--)); do
        echo "PATH=${inherit_paths[$idx]@Q}:\"\$PATH\""
    done
    #echo "export PATH"
    $debug &&
    echo 'echo bashrc: PATH=${PATH@Q}'

    # add completions
    echo 'complete -W "$phases" -o nosort runPhase'

    # envCommand is empty when "--command" and "--run" are not used

    if $chdir_build_root; then
        echo "cd ${build_root@Q}"
    fi

    echo "export __NIX_BUILD_DEBUG_DIR=${debug_dir@Q}"

    #echo "echo 'starting the nix-build-debug shell'"
    #echo "echo 'next steps:'"
    #echo "echo '  nix-build-debug help'"
    echo "echo 'hint: runPhase [TAB][TAB]'"

} >"$bashrc_path"



shell="$NIX_BUILD_SHELL"
if [ -z "$shell" ]; then
    # $builder is a non-interactive bash shell
    # which is painful to use for humans

    nix_expr='with import <nixpkgs> {}; bashInteractive'

    # use a patched version of bash
    # disable job control in the debug shell
    # with this, Ctrl-Z will stop the debug shell
    # and return to the parent shell
    # see also nixpkgs/pkgs/shells/bash/5.nix
    nix_expr+=$(
        echo '.overrideAttrs (oldAttrs: {'
        echo '  configureFlags = oldAttrs.configureFlags ++ ['
        echo '    "--disable-job-control"'
        echo '  ];'
        echo '})'
    )

    $debug &&
    echo "getting interactive bash shell" >&2

    if shellDrv=$(nix-build -E "$nix_expr" --no-out-link); then
        shell="$shellDrv/bin/bash"
    else
        echo "notice: will use bash from your environment" >&2
        shell="bash"
    fi
fi



# TODO? run this in a clean env
# inherit only requires envs

exec "$shell" --noprofile --rcfile "$bashrc_path"
