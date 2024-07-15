__showPhaseFooterError() {
    # based on showPhaseFooter
    local phase="$1";
    local startTime="$2";
    local endTime="$3";
    local rc="$4";
    local xtrace_on="$5";
    local delta=$(( endTime - startTime ));
    # no. always show the phase footer
    #(( delta < 30 )) && return;
    local H=$((delta/3600));
    local M=$((delta%3600/60));
    local S=$((delta%60));
    echo -n "$phase failed with status $rc in ";
    (( H > 0 )) && echo -n "$H hours ";
    (( M > 0 )) && echo -n "$M minutes ";
    echo "$S seconds"
    if ! $xtrace_on; then
      echo 'hint: enable xtrace with "set -x"'
    fi
}

__runPhaseHelp() {
    echo "usage: runPhase <phaseName> [options]"
    echo "example: runPhase buildPhase"
    echo "hint: runPhase [TAB][TAB]"
    echo
    echo "options:"
    echo
    echo "    -e"
    echo "    --edit"
    echo "        edit the phase, then run it"
    echo "        example: runPhase buildPhase -e"
    echo "        to edit only, use editPhase"
    echo
    echo "    -f"
    echo "    --force"
    echo "        force editing"
    # todo...
}

# non-standard
editPhase() {
    # parse args
    local curPhase=""
    local doForce=false
    while (( "$#" )); do
        case "$1" in
            --force|-f)
                doForce=true
                shift
                ;;
            *)
                if [ -n "$curPhase" ]; then
                    echo "error: unrecognized argument: ${1@Q}"
                    return 1
                fi
                curPhase="$1"
                shift
                ;;
        esac
    done

    # no. phases can have arbitrary names:
    # qtPreHook qtOwnPathsHook postPatchMkspecs
    if false; then
    # validate phase name
    # also allow hook names
    if ! echo "$curPhase" | grep -q -E '^([a-zA-Z0-9]+Phase|(pre|post)[A-Z][a-zA-Z0-9]+|buildCommand(Path)?)$'; then
        echo "editPhase: error: not a phase name: ${curPhase@Q}" >&2
        return 1
    fi
    fi

    if [ "$curPhase" = "buildCommandPath" ]; then
        echo "error: not implemented: editing phase ${curPhase@Q}" >&2
        return 1
    fi

    local isPhaseString=true
    if [ -z "${!curPhase}" ] && [ "${curPhase: -5}" = "Phase" ]; then
        # curPhase is not a custom phase string
        isPhaseString=false
    fi

    if ! $isPhaseString && ! $doForce; then
        local phaseName="${curPhase:0: -5}"
        echo "error: $curPhase is not a custom phase string, but the default $curPhase function from stdenv" >&2
        echo "probably you want to edit hooks:" >&2
        echo "  editPhase pre${phaseName^}" >&2
        echo "  editPhase post${phaseName^}" >&2
        echo "if you really want to edit the default $curPhase function, then run:" >&2
        echo "  editPhase $curPhase -f" >&2
        return 1
    fi

    local curPhasePath="$__NIX_BUILD_DEBUG_DIR/lib/$curPhase.sh"
    if $isPhaseString; then
        echo "${!curPhase}" >"$curPhasePath"
    else
        declare -f "$curPhase" >"$curPhasePath"
    fi

    local curPhasePathBak="$curPhasePath.bak"
    if ! [ -e "$curPhasePathBak" ]; then
        echo "writing the original $curPhase to ${curPhasePathBak@Q}"
        cp "$curPhasePath" "$curPhasePathBak"
    fi

    if ! $EDITOR "$curPhasePath"; then
        echo "error: failed to run: ${EDITOR@Q} ${curPhasePath@Q}" >&2
        return 1
    fi

    echo "loading the modified $curPhase from ${curPhasePath@Q}"
    if $isPhaseString; then
        # always trace this
        echo "# declare $curPhase=\"\$( < ${curPhasePath@Q} )\""
        declare -g $curPhase="$( < "$curPhasePath" )"
    else
        # always trace this
        echo "# source ${curPhasePath@Q}"
        source "$curPhasePath"
    fi
}

runPhase() {

    # https://stackoverflow.com/questions/14564746/in-bash-how-to-get-the-current-status-of-set-x
    _x=${-//[^x]/}
    set +x # disable xtrace

    if [ -n "$_x" ]; then xtrace_on=true; else xtrace_on=false; fi

    if [ "$#" = "0" ]; then
        echo "error: no arguments" >&2
        __runPhaseHelp
        return 1
    fi

    # parse args
    local curPhase=""
    local doEdit=false
    local doForce=false
    while (( "$#" )); do
        #echo "arg: ${1@Q}"
        case "$1" in
            --help|-h)
                __runPhaseHelp
                return 1
                ;;
            --list|-l)
                printf "%s\n" $phases
                return
                ;;
            --edit|-e)
                doEdit=true
                shift
                ;;
            --force|-f)
                doForce=true
                shift
                ;;
            *)
                if [ -n "$curPhase" ]; then
                    echo "error: unrecognized argument: ${1@Q}"
                    return 1
                fi
                curPhase="$1"
                shift
                ;;
        esac
    done

    # no. phases can have arbitrary names:
    # qtPreHook qtOwnPathsHook postPatchMkspecs
    if false; then
    # non-standard: validate phase name
    if ! echo "$curPhase" | grep -q -E '^([a-zA-Z0-9]+Phase|buildCommand(Path)?)$'; then
        echo "runPhase: error: not a phase name: ${curPhase@Q}" >&2
        return 1
    fi
    fi

    if $doEdit; then
        local args
        if $doForce; then args="-f"; fi
        if ! editPhase "$curPhase" $args; then
            echo "error: failed to run: editPhase ${curPhase@Q}" >&2
            return 1
        fi
    fi

    if [[ "$curPhase" = unpackPhase && -n "${dontUnpack:-}" ]]; then return; fi
    if [[ "$curPhase" = patchPhase && -n "${dontPatch:-}" ]]; then return; fi
    if [[ "$curPhase" = configurePhase && -n "${dontConfigure:-}" ]]; then return; fi
    if [[ "$curPhase" = buildPhase && -n "${dontBuild:-}" ]]; then return; fi
    if [[ "$curPhase" = checkPhase && -z "${doCheck:-}" ]]; then return; fi
    if [[ "$curPhase" = installPhase && -n "${dontInstall:-}" ]]; then return; fi
    if [[ "$curPhase" = fixupPhase && -n "${dontFixup:-}" ]]; then return; fi
    if [[ "$curPhase" = installCheckPhase && -z "${doInstallCheck:-}" ]]; then return; fi
    if [[ "$curPhase" = distPhase && -z "${doDist:-}" ]]; then return; fi

    if [[ -n $NIX_LOG_FD ]]; then
        echo "@nix { \"action\": \"setPhase\", \"phase\": \"$curPhase\" }" >&"$NIX_LOG_FD"
    fi

    showPhaseHeader "$curPhase"
    dumpVars

    local startTime=$(date +"%s")

    subshell_temp=$(mktemp -u -t "$([ -d /run/user/$UID ] && echo "-p/run/user/$UID" || echo "-p$__NIX_BUILD_DEBUG_DIR")" shell.$$.subshell.XXXXXXXXXX)
    #subshell_id=${subshell_temp##*.}

    # run the phase function in a subshell to catch exit
    # aka: try/catch in bash

    # Ctrl-Z breaks this. Ctrl-Z only suspends the subshell, and the runPhase function continues running
    # fixed by using bash with disable-job-control

    #echo "# runPhase: starting subshell"

    # FIXME __handle_exit: command not found

    (
        #echo "# runPhase subshell: running $curPhase"
        __handle_exit() {
            # this is always reached, success or error
            rc=$?
            set +x # disable xtrace
            set +e # disable errexit
            unset __handle_exit
            # return new state to parent shell
            { declare -p; declare -p -f; } >$subshell_temp.env.2.sh
            echo -n "$PWD" >$subshell_temp.cwd.2.txt
        }
        trap __handle_exit EXIT
        trap __handle_exit ERR

        # save current state
        { declare -p; declare -p -f; } >$subshell_temp.env.1.sh
        echo -n "$PWD" >$subshell_temp.cwd.1.txt

        # Evaluate the variable named $curPhase if it exists, otherwise the
        # function named $curPhase.
        #eval "${!curPhase:-$curPhase}"

        # enable errexit
        # exit subshell on error to stop runPhase on error
        set -e

        # non-standard
        if [ "$curPhase" = "buildCommandPath" ]; then
            $xtrace_on && set -x
            "${!curPhase}"
            exit $?
        fi

        # non-standard: run custom phase strings via ${curPhase}_from_string functions
        # TODO why? is this better for tracing?
        # this is *not* required for "continue from line"
        # and this changes the build process (too much?)
        #if declare -F ${curPhase}_from_string >/dev/null; then
        #    ${curPhase}_from_string "$@"
        # standard: run custom phase strings with eval
        if [ -n "${!curPhase}" ]; then
            # no. xtrace of eval is too verbose
            #$xtrace_on && set -x
            if $xtrace_on; then
                # quiet xtrace
                echo "# eval \"\$$curPhase\""
                eval "set -x; ${!curPhase}"
                exit $?
            fi
            eval "${!curPhase}"
            exit $?
        else
            $xtrace_on && set -x
            # non-standard: pass arguments to the phase function
            $curPhase "$@"
            exit $?
        fi
    )

    rc=$?

    # import env from subshell
    # dont update some global variables
    # foremost, dont update SHELLOPTS to avoid "set -e"
    # declare -ar BASH_VERSINFO=(...)
    # declare -r BASHOPTS="..."
    # declare -r SHELLOPTS="..."
    # declare -ir EUID="1000"
    # declare -ir PPID="556440"
    # declare -ir UID="1000"

    source <(sed -E '/^declare -[-aAilnrtux]+ (_|SHELLOPTS|BASHOPTS|BASH_VERSINFO|SHLVL|EUID|PPID|UID)=/d; s/^declare -/declare -g -/' $subshell_temp.env.2.sh)

    # change workdir
    cd "$(<$subshell_temp.cwd.2.txt)"

    rm $subshell_temp.*

    # TODO on success, add the phase name to $donePhases (non-standard)

    # TODO also write output logfile

    # TODO print the return code of the phase. success or error?

    # TODO if unpackPhase fails, show hint to remove old $sourceRoot
    # unpacker appears to have produced no directories

    local endTime=$(date +"%s")

    if [[ "$rc" != 0 ]]; then
      # test: buildPhase () { echo test exit 1; exit 1; }
      __showPhaseFooterError "$curPhase" "$startTime" "$endTime" "$rc" "$xtrace_on"
      $xtrace_on && set -x # enable xtrace
      return $rc
    fi

    showPhaseFooter "$curPhase" "$startTime" "$endTime"

    if [ "$curPhase" = unpackPhase ]; then
        $xtrace_on && set -x # enable xtrace
    fi

    if [ "$curPhase" = unpackPhase ]; then
        # make sure we can cd into the directory
        [ -n "${sourceRoot:-}" ] && chmod +x "${sourceRoot}"

        cd "${sourceRoot:-.}"
    fi

    $xtrace_on && set -x # enable xtrace
}
