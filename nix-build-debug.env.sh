# debug nix-build in a nix-shell

# run the build phases explicitly
# modify the build phases (they are stored in *.sh files)
# continue running build phases from specified line number

# 1. start a nix-shell
#   nix-shell -E 'with import <nixpkgs> {}; callPackage ./default.nix {}'
# or
#   nix-shell '<nixpkgs>' -A some-package

# 2. source this script
#   source /path/to/nix-shell-debug.sh
# running the script fails
# because bash functions like makeWrapper are missing

# 3. run phases
#   ls nix*
#   ./nix.00*
#   ./nix.01*
#   ./nix.02*

# when a phase fails, fix the phase script in nix.*.sh
# then continue running the phase, for example from line 123
#   ./nix.02* 123

# the build result will be installed to result-out/ etc

# see also
# https://unix.stackexchange.com/questions/498435/how-do-i-diagnose-a-failing-nix-build
# https://github.com/NixOS/nixpkgs/blob/master/doc/stdenv/stdenv.chapter.md # sec-building-stdenv-package
# https://discourse.nixos.org/t/nix-build-phases-run-nix-build-phases-interactively/36090
# https://nixos.wiki/wiki/Development_environment_with_nix-shell#stdenv.mkDerivation
# https://github.com/NixOS/nixpkgs/blob/master/pkgs/stdenv/generic/setup.sh



# FIXME add a phase runner function to call the phase scripts
# and to apply state changes like
#   cd $sourceRoot
#   someGlobalArray+=(someValue)



# this script is sourced, so we cannot call "exit 1"
# instead, check $__rc before every step
__rc=0

__get_bin_path() {
  if ! command -v "$1"; then
    __rc=1
    echo "error: missing dependency ${1@Q}" >&2
    return 1
  fi
  return 1
}

[ $__rc = 0 ] &&
__realpath=$(__get_bin_path realpath)

[ $__rc = 0 ] &&
__sed=$(__get_bin_path sed)

#__get_bin_path no-such-bin-$RANDOM # test

# run build in tempdir
# no. user should do this manually
#cd $(mktemp -d)

# dont install to /nix/store
[ $__rc = 0 ] &&
for n in $outputs; do eval export $n=$PWD/result-$n; done

# https://github.com/NixOS/nixpkgs/blob/master/pkgs/stdenv/generic/setup.sh
[ $__rc = 0 ] &&
phases="${prePhases[*]:-} unpackPhase patchPhase ${preConfigurePhases[*]:-} \
    configurePhase ${preBuildPhases[*]:-} buildPhase checkPhase \
    ${preInstallPhases[*]:-} installPhase ${preFixupPhases[*]:-} fixupPhase installCheckPhase \
    ${preDistPhases[*]:-} distPhase ${postPhases[*]:-}";

# based on genericBuild
[ $__rc = 0 ] &&
if [ -f "${buildCommandPath:-}" ]; then
    #source "$buildCommandPath"
    #buildCommand=$(<"$buildCommandPath")
    phases="buildCommandPath"
fi

[ $__rc = 0 ] &&
if [ -n "${buildCommand:-}" ]; then
    #eval "$buildCommand"
    #eval "function buildCommand() { $buildCommand ; }"
    phases="buildCommand"
fi

[ $__rc = 0 ] &&
phasesArray=($phases)

[ $__rc = 0 ] &&
phasesCount=${#phasesArray[@]}

[ $__rc = 0 ] &&
idxFormat="%0${#phasesCount}d"

#body_start_line="######## nix build phase body start ########"

[ $__rc = 0 ] &&
for ((idx = 0; idx < phasesCount; idx++)); do
    curPhase="${phasesArray[$idx]}"
    #curPhase="testPhase"; testPhase=$'echo hello\necho world\nexit 0' # test
    phaseFile=nix.$(printf "$idxFormat" "$idx").$curPhase.sh
    body_start_line="################ $curPhase ################"
    echo "writing $phaseFile"
    #echo "eval \"\${$curPhase:-$curPhase}\""
    if [ "$curPhase" = "buildCommandPath" ]; then
        s="$body_start_line"$'\n'$(< "$buildCommandPath")
    elif [ "$curPhase" = "buildCommand" ]; then
        s="$body_start_line"$'\n'"$buildCommand"
    elif s=$(declare -f $curPhase); then
        # $curPhase is a function
        # declare the function
        s=$(
            echo "$s" | head -n2
            echo "$body_start_line"
            echo "$s" | tail -n+3
        )
        # call the function
        s+=$'\n'"runPhase $curPhase"
    else
        # $curPhase is bash code
        #s="$curPhase"
        s="$body_start_line"$'\n'"${!curPhase}"
        # no. eval breaks tracing
        if false; then
        # declare
        #s="$curPhase=${!curPhase@Q}" # $'...\n...'
        #s="$curPhase=$(printf %q "${!curPhase}")" # $'...\n...'
        eof="__EOF_$curPhase"
        s="$curPhase=\$(cat <<'$eof'"$'\n'"${!curPhase}"$'\n'"$eof"$'\n)'
        # call
        s+=$'\n'"runPhase $curPhase"
        fi
    fi
    # no. this is done by runPhase
    if false; then
    #if [ "$curPhase" = "unpackPhase" ]; then
        s+=$'\n'
        s+='[ -n "${sourceRoot:-}" ] && chmod +x "${sourceRoot}"'$'\n'
        s+='cd "${sourceRoot:-.}"'$'\n'
    fi
    {
        echo '#!/usr/bin/env bash'
        #echo -n 'set -x; ' # debug the debugger
        echo -n "source \"\$(dirname \"\$BASH_SOURCE\")\"/.nix/.init_phase.sh; "
        # TODO trap exit. dump all shell state: variables + history
        echo -n "__goto_script_line \"\$1\"; "
        echo "set -x" # trace all commands

        echo "$s"
    } >$phaseFile
    chmod +x $phaseFile
done

# export bash options: set -x, ...
#export SHELLOPTS

# export bash functions: runHook, _eval, ...
#export -f $(declare -F | cut -d' ' -f3)

#declare -f >_nix_functions.sh
#. _nix_functions.sh

[ $__rc = 0 ] &&
mkdir -p .nix

[ $__rc = 0 ] &&
for funcName in $(declare -F | cut -d' ' -f3); do
  declare -f $funcName >.nix/$funcName.sh
done

[ $__rc = 0 ] &&
{
  echo "__d=\$(dirname \"\$BASH_SOURCE\")"
  declare -F | cut -d' ' -f3 | sed 's/.*/source "$__d"\/&.sh/'
} >.nix/.all_functions.sh

[ $__rc = 0 ] &&
function __echo_init_code() {
    # based on https://github.com/NixOS/nixpkgs/blob/master/pkgs/stdenv/generic/setup.sh
    # aka /nix/store/v5irq7wvkr7kih0hhnch5nnv2dcq8c4f-stdenv-linux/setup
    cat <<'EOF'
######################################################################
# Initialisation.

# If using structured attributes, export variables from `env` to the environment.
# When not using structured attributes, those variables are already exported.
if [[ -n $__structuredAttrs ]]; then
    for envVar in "${!env[@]}"; do
        declare -x "${envVar}=${env[${envVar}]}"
    done
fi


# Set a fallback default value for SOURCE_DATE_EPOCH, used by some build tools
# to provide a deterministic substitute for the "current" time. Note that
# 315532800 = 1980-01-01 12:00:00. We use this date because python's wheel
# implementation uses zip archive and zip does not support dates going back to
# 1970.
export SOURCE_DATE_EPOCH
: "${SOURCE_DATE_EPOCH:=315532800}"


# Wildcard expansions that don't match should expand to an empty list.
# This ensures that, for instance, "for i in *; do ...; done" does the
# right thing.
shopt -s nullglob


# quickfix: _defaultUnpack: tar: No such file or directory
if false; then
# Set up the initial path.
PATH=
HOST_PATH=
for i in $initialPath; do
    if [ "$i" = / ]; then i=; fi
    addToSearchPath PATH "$i/bin"

    # For backward compatibility, we add initial path to HOST_PATH so
    # it can be used in auto patch-shebangs. Unfortunately this will
    # not work with cross compilation.
    if [ -z "${strictDeps-}" ]; then
        addToSearchPath HOST_PATH "$i/bin"
    fi
done
fi

unset i

if (( "${NIX_DEBUG:-0}" >= 1 )); then
    echo "initial path: $PATH"
fi


# Check that the pre-hook initialised SHELL.
if [ -z "${SHELL:-}" ]; then echo "SHELL not set"; exit 1; fi
BASH="$SHELL"
export CONFIG_SHELL="$SHELL"


# Execute the pre-hook.
if [ -z "${shell:-}" ]; then export shell="$SHELL"; fi
runHook preHook


# Allow the caller to augment buildInputs (it's not always possible to
# do this before the call to setup.sh, since the PATH is empty at that
# point; here we have a basic Unix environment).
runHook addInputsHook

# Package accumulators

declare -a pkgsBuildBuild pkgsBuildHost pkgsBuildTarget
declare -a pkgsHostHost pkgsHostTarget
declare -a pkgsTargetTarget

declare -a pkgBuildAccumVars=(pkgsBuildBuild pkgsBuildHost pkgsBuildTarget)
declare -a pkgHostAccumVars=(pkgsHostHost pkgsHostTarget)
declare -a pkgTargetAccumVars=(pkgsTargetTarget)

declare -a pkgAccumVarVars=(pkgBuildAccumVars pkgHostAccumVars pkgTargetAccumVars)


# Hooks

declare -a envBuildBuildHooks envBuildHostHooks envBuildTargetHooks
declare -a envHostHostHooks envHostTargetHooks
declare -a envTargetTargetHooks

declare -a pkgBuildHookVars=(envBuildBuildHook envBuildHostHook envBuildTargetHook)
declare -a pkgHostHookVars=(envHostHostHook envHostTargetHook)
declare -a pkgTargetHookVars=(envTargetTargetHook)

declare -a pkgHookVarVars=(pkgBuildHookVars pkgHostHookVars pkgTargetHookVars)

# those variables are declared here, since where and if they are used varies
declare -a preFixupHooks fixupOutputHooks preConfigureHooks postFixupHooks postUnpackHooks unpackCmdHooks
EOF
} # end of __echo_init_code

[ $__rc = 0 ] &&
{
    echo "set -e" # stop on error

    # bash goto: continue script execution from line N
    echo "__goto_script_line() {"
    echo "    # goto line number"
    echo "    if [ -z \"\$1\" ]; then return; fi"
    #echo "    echo \"0 = \$0\""
    #echo "    echo \"BASH_SOURCE = \$BASH_SOURCE\""
    echo "    __L=\"\$1\""
    echo "    __phaseFile=\$(basename \"\$0\")"
    echo "    __curPhase=\"\${__phaseFile%.*}\""
    echo "    __curPhase=\"\${__curPhase##*.}\""
    echo "    body_start_line=\"################ \$__curPhase ################\""
    echo "    echo \"# \$__phaseFile: continuing script execution from line \$__L\""
    echo "    {"
    echo "        __body_start=\$(grep -m1 -n \"^\$body_start_line\" \"\$0\")"
    echo "        __body_start=\${__body_start%%:*}"
    echo "        head -n\$__body_start \"\$0\""
    #echo "        sed -n \"s/^/# /; \$((__body_start + 1)),\${__L}p; \${__L}q\" \"\$0\""
    #echo "        sed -n \"s/^/# /; s/^# $/#/; \$((__body_start + 1)),\${__L}p; \${__L}q\" \"\$0\""
    # no. comments show up in trace
    #echo "        sed -n \"s/^/# /; s/^# $/#/; \$((__body_start + 1)),\$((__L - 1))p; \$((__L - 1))q\" \"\$0\""
    # print N empty lines
    #echo "        seq \$((__body_start + 1)) \$((__L - 1)) | sed 's/^/# /'"
    echo "        seq \$((__body_start + 1)) \$((__L - 1)) | sed 's/^.*$//'"
    echo "        tail -n+\$__L \"\$0\""
    # TODO path?
    echo "    } >\"\$__phaseFile.line\${__L}.sh\""
    echo "    chmod +x \"\$__phaseFile.line\${__L}.sh\""
    echo "    exec ./\"\$__phaseFile.line\${__L}.sh\""
    # TODO write to file, chmod +x, exec
    #echo "    echo \"# \$__phaseFile: continuing script execution from line \$__L\" eval"
    #echo "    eval \"\$s\""
    #echo "    exit \$?"
    echo "}"

    #echo "__d=\$(dirname \"\$0\")"
    echo "__d=\$(dirname \"\$BASH_SOURCE\")"
    echo "__workdir=\"\$PWD\""
    echo "shopt -s extglob" # fix: syntax error near unexpected token `('
    #echo "source \"\$__d\"/_nix_functions.sh" # import bash functions: runHook, ...
    #echo "source \"\$__d\"/.nix/.all_functions.sh" # import bash functions: runHook, ...
    echo "source \"\$__d\"/.all_functions.sh" # import bash functions: runHook, ...

    echo "export GZIP_NO_TIMESTAMPS=1"

    echo "export PS4='\n# \$($__realpath --relative-to=\"\$__workdir\" --relative-base=\"\$__workdir\" \"\$__workdir/\${BASH_SOURCE}\" | $__sed -E \"s/\.line[0-9]+\.sh$//\") \${LINENO} # \${FUNCNAME[0]}\n# cwd: \$($__realpath --relative-to=\$__workdir --relative-base=\$__workdir \"\$PWD\")\n# '"
    #echo "set -x" # trace all commands

    # FIXME this should run only once before all phases
    # not before each phase
    # so each phase can modify this global state
    # and pass it to following phases
    __echo_init_code

    # fix: do not know how to unpack source archive
    echo "unpackCmdHooks+=(_defaultUnpack)"

    # fix: default is $TMP but the build root is $PWD
    echo "export NIX_BUILD_TOP=\"\$PWD\""

    # trap exit, both "exit 0" and "exit 1" (etc)
    # we need this to export state-changes from phase scripts to the current shell
    # example: "cd $sourceRoot"
    # https://unix.stackexchange.com/a/322213/295986
    echo "__cleanup() {"
    echo "    err=\$?"
    echo "    set +x" # stop tracing
    echo "    echo cleanup..."
    echo "    echo cleanup: writing \$__workdir/.todo-export-phase-state"
    echo "    echo \"PWD=\${PWD@Q}\" >\"\$__workdir\"/.todo-export-phase-state"
    echo "    trap '' EXIT INT TERM"
    echo "    exit $err"
    echo "}"
    echo "__sig_cleanup() {"
    echo "    set +x" # stop tracing
    echo "    trap '' EXIT" # some shells will call EXIT after the INT handler
    echo "    false" # sets $?
    echo "    __cleanup"
    echo "}"
    echo "trap __cleanup EXIT"
    echo "trap __sig_cleanup INT QUIT TERM"

} >.nix/.init_phase.sh
