__showPhaseFooterError() {
    # based on showPhaseFooter
    local phase="$1";
    local startTime="$2";
    local endTime="$3";
    local rc="$4";
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
}

runPhase() {
    #local curPhase="$*"
    local curPhase="$1"; shift
    # non-standard: validate phase name
    if [[ "$curPhase" != *"Phase" ]] || [[ "$curPhase" == "Phase" ]]; then
        echo "runPhase: error: not a phase name: ${curPhase}. phase names must end with 'Phase'" >&2
        return 1
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

    # Evaluate the variable named $curPhase if it exists, otherwise the
    # function named $curPhase.
    #eval "${!curPhase:-$curPhase}"

    #if declare -F ${curPhase}_from_string >/dev/null; then ${curPhase}_from_string; else $curPhase; fi

    subshell_temp=$(mktemp -u -t "$([ -d /run/user/$UID ] && echo "-p/run/user/$UID" || echo "-p$__NIX_BUILD_DEBUG_DIR")" shell.$$.subshell.XXXXXXXXXX)
    #subshell_id=${subshell_temp##*.}

    # run the phase function in a subshell to catch exit
    # aka: try/catch in bash

    # Ctrl-Z breaks this. Ctrl-Z only suspends the subshell, and the runPhase function continues running
    # fixed by using bash with disable-job-control

    #echo "# runPhase: starting subshell"

    (
        #echo "# runPhase subshell: running $curPhase"
        __handle_exit() {
            # this is always reached, success or error
            rc=$?
            set +x # disable xtrace
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

        local rc=
        if declare -F ${curPhase}_from_string >/dev/null; then
            ${curPhase}_from_string "$@"
            exit $?
        else
            $curPhase "$@"
            exit $?
        fi
    )

    rc=$?

    set +x # disable xtrace

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

    xtrace_was_on=false
    if cat $subshell_temp.env.1.sh | grep -m1 '^declare -r SHELLOPTS=' | grep -q -w xtrace; then
        xtrace_was_on=true
    fi

    rm $subshell_temp.*

    # TODO on success, add the phase name to $donePhases (non-standard)

    # TODO also write output logfile

    # TODO print the return code of the phase. success or error?

    # TODO if unpackPhase fails, show hint to remove old $sourceRoot
    # unpacker appears to have produced no directories

    local endTime=$(date +"%s")

    if [[ "$rc" != 0 ]]; then
      # test: buildPhase () { echo test exit 1; exit 1; }
      __showPhaseFooterError "$curPhase" "$startTime" "$endTime" "$rc"
      $xtrace_was_on && set -x # enable xtrace
      return $rc
    fi

    showPhaseFooter "$curPhase" "$startTime" "$endTime"

    if [ "$curPhase" = unpackPhase ]; then
        # make sure we can cd into the directory
        [ -n "${sourceRoot:-}" ] && chmod +x "${sourceRoot}"

        cd "${sourceRoot:-.}"
    fi

    $xtrace_was_on && set -x # enable xtrace
}
