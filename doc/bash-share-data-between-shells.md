https://stackoverflow.com/questions/5564418/exporting-an-array-in-bash-script

> When you invoke another bash shell you're starting a new process, you loose some bash state. However, if you dot-source a script, the script is run in the same environment; or if you run a subshell via `( )` the environment is also preserved (because bash forks, preserving its complete state, rather than reinitialising using the process environment).



https://stackoverflow.com/questions/16618071/can-i-export-a-variable-to-the-environment-from-a-bash-script-without-sourcing-i

https://stackoverflow.com/questions/496702/can-a-shell-script-set-environment-variables-of-the-calling-shell

https://stackoverflow.com/questions/15541321/set-a-parent-shells-variable-from-a-subshell



## export full shell environment

https://askubuntu.com/questions/275965/how-to-list-all-variables-names-and-their-current-values

to dump the full environment of a subshell, use `declare -p` for variables and `declare -pf` for functions

### set

everything?

envs, vars, arrays, functions

### declare

#### declare -p

envs, vars, arrays

#### declare -f

functions

### env

only envs

### printenv

only envs
