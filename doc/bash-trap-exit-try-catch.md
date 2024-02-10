https://www.reddit.com/r/bash/comments/e1mxub/dealing_with_trycatch_situations_and_handling/

https://unix.stackexchange.com/questions/690850/how-do-you-continue-execution-after-using-trap-exit-in-bash



## run code in subshell

see also [bash-trap-exit-try-catch.sh](bash-trap-exit-try-catch.sh)

see also [Is there a TRY CATCH command in Bash](https://stackoverflow.com/questions/22009364/is-there-a-try-catch-command-in-bash)

https://stackoverflow.com/a/43418467/10440128

```sh
subshell_temp=$(mktemp -u -t $([ -d /run/user/$UID ] && echo "-p/run/user/$UID") shell.$$.subshell.XXXXXXXXXX)
(
    set -Ee
    function __exit {
        echo error $?
        exit 0  # optional; use if you don't want to propagate (rethrow) error to outer shell
    }
    trap __exit ERR
    trap __exit EXIT
    exit 1

    __handle_exit() {
        rc=$?
        echo "subshell end. rc=$rc. sourceRoot=${sourceRoot@Q}. cwd=$PWD. env=$subshell_temp.env.2.sh"
        # return state-changes to parent shell
        # FIXME trap exit
        unset __handle_exit
        { declare -p; declare -p -f; } >$subshell_temp.env.2.sh
        echo "$PWD" >$subshell_temp.cwd.2.txt
    }
    trap __handle_exit EXIT
    trap __handle_exit ERR


)
echo continue
```

`trap --help`

```
    If a SIGNAL_SPEC is EXIT (0) ARG is executed on exit from the shell.  If
    a SIGNAL_SPEC is DEBUG, ARG is executed before every simple command.  If
    a SIGNAL_SPEC is RETURN, ARG is executed each time a shell function or a
    script run by the . or source builtins finishes executing.  A SIGNAL_SPEC
    of ERR means to execute ARG each time a command's failure would cause the
    shell to exit when the -e option is enabled.
```



### modify environment of parent shell

problem: subshell cannot modify the environment of the parent shell

solution: `declare` and `source`

- export the subshell environemnt with `declare -p` and `declare -pf` and `echo $PWD`
- import the subshell environemnt with `source`

importing variables like `SHELLOPTS` or `BASHOPTS` is not desired,
because this would also export `set -e` to the parent shell

some variables like `BASH_VERSINFO` or `UID` are read-only



### handle SIGSTOP in interactive shell

problem: sending SIGSTOP (Ctrl-Z) to the subshell will only stop the subshell, and the parent shell continues running

solution: lockfiles

https://stackoverflow.com/questions/37164161/trap-ing-linux-signals-sigstop

> There are two signals which cannot be intercepted and handled: SIGKILL and SIGSTOP

https://stackoverflow.com/questions/20182454/shell-script-get-ctrlz-with-trap

https://stackoverflow.com/questions/52340907/why-does-a-subshell-of-an-interactive-shell-run-as-an-interactive-shell

https://stackoverflow.com/questions/60907427/ctrlz-sigtstp-has-strange-behavior-in-bash-shell-in-docker-container

https://stackoverflow.com/questions/46752794/why-does-wait-generate-pid-is-not-a-child-of-this-shell-error-if-a-pipe-is-u

https://unix.stackexchange.com/questions/421020/what-is-the-exact-difference-between-a-subshell-and-a-child-process

https://stackoverflow.com/questions/77973144/sigtstp-ctrl-z-stops-only-the-subshell-but-the-parent-shell-keeps-running-i



#### disable job control

since Ctrl-Z does not work, lets disable it

https://unix.stackexchange.com/questions/137915/disabling-job-control-in-bash-ctrl-z

```
set +m
```



## try/catch in bash

note: this is not-yet implemented in bash

expected

```sh
#!/usr/bin/env bash

try
  echo trying...
  exit 1 # fail
  echo ok
catch
  rc=$? # get the return code 1 from "exit 1"
  echo got return code $rc
done

echo continuing the main script
```



## try/catch in powershell

https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.core/about/about_try_catch_finally

https://stackoverflow.com/questions/13211557/how-do-i-exit-from-a-try-catch-block-in-powershell



## other shells

https://github.com/alebcay/awesome-shell

> [crash](https://github.com/molovo/crash) - Proper error handling, exceptions and try/catch for ZSH

too high-level, using `throw` instead of `exit`
