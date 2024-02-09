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
    subshell_id=$(date +$$.%s.%N)
    # FIXME Ctrl-Z breaks this. Ctrl-Z only suspends the subshell, and the runPhase function continues running
    (
        echo $$ >/run/user/$(id -u)/nix-build-debug.subshell.$subshell_id.pid
        echo "subshell start. env=/run/user/$(id -u)/nix-build-debug.subshell.$subshell_id.env.1.sh"
        { declare -p; declare -p -f; } >/run/user/$(id -u)/nix-build-debug.subshell.$subshell_id.env.1.sh
        echo "$PWD" >/run/user/$(id -u)/nix-build-debug.subshell.$subshell_id.cwd.1.txt
        local rc=
        if declare -F ${curPhase}_from_string >/dev/null; then
            ${curPhase}_from_string "$@"
            rc=$?
        else
            $curPhase "$@"
            rc=$?
        fi
        echo "subshell end. rc=$rc. sourceRoot=${sourceRoot@Q}. cwd=$PWD. env=/run/user/$(id -u)/nix-build-debug.subshell.$subshell_id.env.2.sh"
        # return state-changes to parent shell
        # FIXME trap exit
        { declare -p; declare -p -f; } >/run/user/$(id -u)/nix-build-debug.subshell.$subshell_id.env.2.sh
        echo "$PWD" >/run/user/$(id -u)/nix-build-debug.subshell.$subshell_id.cwd.2.txt
    )
    # WONTFIX? bash job control is too verbose
    # also, this does not allow Ctrl-Z to pause the build phase
    #) & wait $!

    # wait for the subshell to finish
    # this is needed to fix bash job control (Ctrl-Z; jobs; fg)
    subshell_pid=$(</run/user/$(id -u)/nix-build-debug.subshell.$subshell_id.pid)
    echo "runPhase: parent shell $$ is waiting for subshell $subshell_pid" >&2
    # FIXME bash: wait: pid 590811 is not a child of this shell
    # WONTFIX? both shells have the same PID: $$ == $subshell_pid
    #wait $(</run/user/$(id -u)/nix-build-debug.subshell.$subshell_id.pid)

    # import env from subshell
    # declare -g: create global variables when used in a shell function
    #source /run/user/$(id -u)/nix-build-debug.subshell.$subshell_id.env.2.sh
    #source <(sed 's/^declare -/declare -g -/' /run/user/$(id -u)/nix-build-debug.subshell.$subshell_id.env.2.sh)
    # dont update some global variables
    # foremost, dont update SHELLOPTS to avoid "set -e"
    # declare -ar BASH_VERSINFO=(...)
    # declare -r BASHOPTS="..."
    # declare -r SHELLOPTS="..."
    # declare -ir EUID="1000"
    # declare -ir PPID="556440"
    # declare -ir UID="1000"

    source <(sed -E '/^declare -[-aAilnrtux]+ (_|SHELLOPTS|BASHOPTS|BASH_VERSINFO|EUID|PPID|UID)=/d; s/^declare -/declare -g -/' /run/user/$(id -u)/nix-build-debug.subshell.$subshell_id.env.2.sh)

    # change workdir
    cd "$(</run/user/$(id -u)/nix-build-debug.subshell.$subshell_id.cwd.2.txt)"

    rm /run/user/$(id -u)/nix-build-debug.subshell.$subshell_id.*

    # TODO on success, add the phase name to $donePhases (non-standard)

    # TODO also write output logfile

    # TODO print the return code of the phase. success or error?

    # TODO if unpackPhase fails, show hint to remove old $sourceRoot
    # unpacker appears to have produced no directories

    local endTime=$(date +"%s")

    showPhaseFooter "$curPhase" "$startTime" "$endTime"

    if [ "$curPhase" = unpackPhase ]; then
        # make sure we can cd into the directory
        [ -n "${sourceRoot:-}" ] && chmod +x "${sourceRoot}"

        cd "${sourceRoot:-.}"
    fi
}
