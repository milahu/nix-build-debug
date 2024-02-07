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



# run build in tempdir
# no. user should do this manually
#cd $(mktemp -d)

# dont install to /nix/store
for n in $outputs; do eval export $n=$PWD/result-$n; done

# https://github.com/NixOS/nixpkgs/blob/master/pkgs/stdenv/generic/setup.sh
phases="${prePhases[*]:-} unpackPhase patchPhase ${preConfigurePhases[*]:-} \
    configurePhase ${preBuildPhases[*]:-} buildPhase checkPhase \
    ${preInstallPhases[*]:-} installPhase ${preFixupPhases[*]:-} fixupPhase installCheckPhase \
    ${preDistPhases[*]:-} distPhase ${postPhases[*]:-}";

# based on genericBuild
if [ -f "${buildCommandPath:-}" ]; then
    #source "$buildCommandPath"
    #buildCommand=$(<"$buildCommandPath")
    phases="buildCommandPath"
fi
if [ -n "${buildCommand:-}" ]; then
    #eval "$buildCommand"
    #eval "function buildCommand() { $buildCommand ; }"
    phases="buildCommand"
fi

phasesArray=($phases)

phasesCount=${#phasesArray[@]}
idxFormat="%0${#phasesCount}d"

#body_start_line="######## nix build phase body start ########"

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

mkdir -p .nix
for funcName in $(declare -F | cut -d' ' -f3); do
  declare -f $funcName >.nix/$funcName.sh
done
{
  echo "__d=\$(dirname \"\$BASH_SOURCE\")"
  declare -F | cut -d' ' -f3 | sed 's/.*/source "$__d"\/&.sh/'
} >.nix/.all_functions.sh

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
    echo "shopt -s extglob" # fix: syntax error near unexpected token `('
    #echo "source \"\$__d\"/_nix_functions.sh" # import bash functions: runHook, ...
    #echo "source \"\$__d\"/.nix/.all_functions.sh" # import bash functions: runHook, ...
    echo "source \"\$__d\"/.all_functions.sh" # import bash functions: runHook, ...

    echo "export GZIP_NO_TIMESTAMPS=1"

    #echo "export PS4='+ Line \${LINENO}: '"
    #echo "export PS4='+ \${BASH_SOURCE} \${LINENO} \${FUNCNAME[0]:+\${FUNCNAME[0]}: }'"
    #echo "export PS4='+ \${BASH_SOURCE#*/} \${LINENO} \${FUNCNAME[0]:+\${FUNCNAME[0]}: }'"
    #echo "export PS4='+ \${BASH_SOURCE} \${LINENO}: '"
    #echo "export PS4='\n# \${BASH_SOURCE} \${LINENO}\n# '"
    #echo "export PS4='\n# \$(realpath --relative-to=\$PWD \${BASH_SOURCE}) \${LINENO}\n# '"
    echo "export PS4='\n# \$(realpath --relative-to=\$PWD \${BASH_SOURCE} | sed -E 's/\.line[0-9]+\.sh$//') \${LINENO}\n# '"
    #echo "set -x" # trace all commands
    # FIXME runHook: command not found
    # inherit bash functions of parent shell

} >.nix/.init_phase.sh
