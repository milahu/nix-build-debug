# TODO? move this to the runPhase function

set -e
__goto_script_line() {
    # goto line number
    if [ -z "$2" ]; then return; fi
    local F="$1"
    local L="$2"
    local curPhase="${F##*/}"; curPhase="${curPhase%.sh}"
    local S="################ $curPhase ################"
    local n

    #local body_start=$(grep -m1 -n "^$S" "$F"); body_start=${body_start%%:*}
    local body_start=$(n=0; while read -r L; do n=$((n+1)); [ "$L" = "$S" ] || continue; echo $n; break; done <"$F")

    (( L <= body_start )) && return

    if [ -z "$body_start" ]; then
        echo "# __goto_script_line: internal error: not found the ${S@Q} line in ${F@Q}" >&2
        exit 1
    fi

    echo "# __goto_script_line: found body start at line ${body_start@Q}" >&2 # debug

    echo "# __goto_script_line: $F: continuing script execution from line $L" >&2

    # TODO? rename function to ${curPhase}_line_${L}
    # first line is always "$curPhase() {"

    {
        #echo "# lines 1 to $((body_start - 1))" # debug
        #head -n$body_start "$F"
        for (( n = 1; n < body_start; n++ )); do read -r l; echo "$l"; done

        #echo "# lines $body_start to $((L - 1))" # debug
        #seq $((body_start + 1)) $((L - 1)) | sed 's/^.*$//'
        #for (( n = body_start; n < L; n++ )); do read -r l; echo "# $n: $l"; done # debug
        for (( n = body_start; n < L; n++ )); do read -r l; echo; done

        #echo "# lines $L to end" # debug
        #tail -n+$L "$F"
        cat

    } <"$F" >"$F.line${L}.sh"

    chmod +x "$F.line${L}.sh"

    echo "# __goto_script_line: running $F.line${L}.sh" >&2

    #exec "$F.line${L}.sh"
    source "$F.line${L}.sh"

    # call the modified phase function
    echo "# __goto_script_line: calling the modified phase function $curPhase" >&2 # debug
    $curPhase

    # exit the subshell to stop running the original phase function
    echo "# __goto_script_line: exiting the subshell" >&2
    exit 1
}
shopt -s extglob
#source "${BASH_SOURCE%/*}"/.all_functions.sh
export GZIP_NO_TIMESTAMPS=1
#export PS4='\n# $(realpath --relative-to=$PWD ${BASH_SOURCE} | sed -E 's/\.line[0-9]+\.sh$//') ${LINENO}\n# '
export PS4='\n# $(realpath --relative-to="$NIX_BUILD_TOP" --relative-base="$NIX_BUILD_TOP" "$NIX_BUILD_TOP/${BASH_SOURCE}" | sed -E "s/\.line[0-9]+\.sh$//") ${LINENO} # ${FUNCNAME[0]}\n# cwd: $(realpath --relative-to=$NIX_BUILD_TOP --relative-base=$NIX_BUILD_TOP "$PWD")\n# '

# FIXME do not know how to unpack source archive
