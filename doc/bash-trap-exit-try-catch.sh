#!/usr/bin/env bash

# similar code is used in lib/stdenv-generic-runPhase.sh

function demo_try_catch {
    subshell_temp=$(mktemp -u -t $([ -d /run/user/$UID ] && echo "-p/run/user/$UID") shell.$$.subshell.XXXXXXXXXX)
    (
        # init ...
        { declare -p; declare -p -f; } >$subshell_temp.env.1.sh
        echo "$PWD" >$subshell_temp.cwd.1.txt
        echo "subshell: start. cwd=$PWD. env=$subshell_temp.env.1.sh"
        echo "subshell: PID=$$ PPID=$PPID"
        set -Ee
        function __exit {
            local __rc=$?
            echo "subshell: end. rc=$__rc. cwd=$PWD. env=$subshell_temp.env.2.sh"
            unset __exit
            { declare -p; declare -p -f; } >$subshell_temp.env.2.sh
            echo "$PWD" >$subshell_temp.cwd.2.txt
            exit $__rc
            #exit 0  # optional; use if you don't want to propagate (rethrow) error to outer shell
        }
        trap __exit EXIT
        function __err { echo "subshell: err"; exit 1; }; trap __err ERR # TODO when is this called
        function __interrupt { echo "subshell: interrupt"; exit 1; }; trap __interrupt SIGINT # Ctrl-C
        #function __cont { echo "subshell: cont"; }; trap __cont SIGCONT # no
        #function __stop { echo "subshell: stop"; exit 1; }; trap __stop SIGSTOP # no
        # TSTP = stop typed at tty = signal 20
        # return code 148 = 128 + 20
        #function __t_stop { echo "subshell: t_stop"; exit 1; }; trap __t_stop SIGTSTP # no! this hangs
        #trap "" SIGTSTP # ignore Ctrl-Z # no! this hangs
        #function __kill { echo kill; exit 1; }; trap __kill SIGKILL # no
        #function __abort { echo abort; exit 1; }; trap __abort SIGABRT
        #function __quit { echo quit; exit 1; }; trap __quit SIGQUIT
        # init done

        #exit 1 # test error

        # test "Ctrl-Z" (suspend, bash job control)
        # this breaks when sourcing this script
        # and running the demo_try_catch function in an interactive shell
        echo "subshell: sleeping"; sleep 99999

        echo "subshell: cd /"
        cd /

        echo "subshell: someVar=x"
        someVar=x
    )
    rc_pid="$? $!"
    read rc pid <<<"$rc_pid"
    echo "parent shell: rc=$rc pid=$pid PID=$$ PPID=$PPID"
    if [ $rc = 148 ]; then
        echo "parent shell: subshell was stopped by Ctrl-Z"

        echo "parent shell: stopping self"
        #kill -SIGSTOP $$ # no. this hangs
        #kill -SIGTSTP $$ # no. no effect

        #echo "parent shell: jobs:"; jobs # ok
        subshell_job=$(jobs -s | grep -o -E '^\[[0-9]+\]\+  Stopped')
        subshell_job=${subshell_job:1: -11}
        echo "parent shell: subshell job: $subshell_job"
        # wait -f: wait for job to terminate
        wait -f %$subshell_job
    fi
    # parent shell: rc=148 pid=611633 # Ctrl-Z
    echo "parent shell: importing subshell env"
    source <(sed -E '/^declare -[-aAilnrtux]+ (_|SHELLOPTS|BASHOPTS|BASH_VERSINFO|EUID|PPID|UID)=/d; s/^declare -/declare -g -/' $subshell_temp.env.2.sh)
    cd "$(<$subshell_temp.cwd.2.txt)"
    rm $subshell_temp.*
    echo "parent shell: cwd=$PWD. someVar=$someVar"
}

if [ "$0" = "$BASH_SOURCE" ]; then
    # running in a non-interactive shell
    echo "note: running the demo_try_catch in a non-interactive shell is simple... try sourcing"
    echo "  source $0"
    demo_try_catch
else
    # running in an interactive shell
    echo "mmkay, you have sourced the script into your interactive shell. now run"
    echo "  demo_try_catch"
fi
