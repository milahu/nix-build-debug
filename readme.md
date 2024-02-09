# nix-build-debug

debug nix-build in a nix-shell

- run the build phases explicitly
- modify the build phases (they are stored in *.sh files)
- continue running build phases from specified line number



## status

early draft. not functional. not usable



## why

using `nix-shell` to debug a failing nix build is not ideal



### stop on error

`nix-build` runs the build as a bash script with `set -e`
so the build stops on the first error

`nix-shell` starts an interactive bash shell with `set +e`
so that errors dont exit the shell.
but with `set +e`, the build does not stop on the first error,
and continues to execute commands after the error

example

```console
$ nix_expr='
  with import <nixpkgs> {};
  stdenv.mkDerivation {
    name = "x";
    buildCommand = "echo buildCommand; false; echo still running";
  }
'

$ nix-build -E "$nix_expr"
buildCommand
error: builder for '/nix/store/29zpgfmmsvf81m49piy26daxljpnli0s-x.drv' failed with exit code 1;

$ nix-shell -E "$nix_expr"
$ runPhase buildCommand
Running phase: buildCommand
buildCommand
still running
```

`nix-build-debug` solves this problem
by running the phase functions in subshells

```sh
runPhase() {
  curPhase=$1
  ( set -e; $curPhase ) # run $curPhase in subshell (...)
}
```

in these subshells,
there is `set -e` to stop the script on the first error.
now, when a build phase fails, the subshell is terminated,
but the `runPhase` function keeps running, and the debug shell keeps running



### continue running

`nix-build-debug` also allows to
continue running a build phase from a certain line in the build phase

example:
the `buildPhase` fails on a command on line 10.
now we can modify the `buildPhase.sh` script
and continue running the `buildPhase` from line 10



## usage



### start a nix-shell

```
nix-shell '<nixpkgs>' -A some-package
```

or

```
nix-shell -E 'with import <nixpkgs> {}; callPackage ./default.nix {}'
```



### source this script

```
source /path/to/nix-build-debug.sh
```

running the script fails  
because bash functions like makeWrapper are missing



### run phases

```
ls nix*
./nix.00*
./nix.01*
./nix.02*
```



### continue running a phase

when a phase fails, fix the phase script in nix.*.sh  
then continue running the phase, for example from line 123

```
./nix.02* 123
```

the build result will be installed to result-out/ etc



## example

```
$ mkdir test && cd test

$ nix-shell '<nixpkgs>' -A hello

$ source ../nix-build-debug.sh
writing nix.00.unpackPhase.sh
writing nix.01.patchPhase.sh
writing nix.02.updateAutotoolsGnuConfigScriptsPhase.sh
writing nix.03.configurePhase.sh
writing nix.04.buildPhase.sh
writing nix.05.checkPhase.sh
writing nix.06.installPhase.sh
writing nix.07.fixupPhase.sh
writing nix.08.installCheckPhase.sh
writing nix.09.distPhase.sh

$ ./nix.00*

$ ./nix.01*

$ ./nix.02*

$ ./nix.03*
```



## see also

- https://unix.stackexchange.com/questions/498435/how-do-i-diagnose-a-failing-nix-build
- https://github.com/NixOS/nixpkgs/blob/master/doc/stdenv/stdenv.chapter.md#building-a-stdenv-package-in-nix-shell-sec-building-stdenv-package-in-nix-shell
- https://discourse.nixos.org/t/nix-build-phases-run-nix-build-phases-interactively/36090
- https://nixos.wiki/wiki/Development_environment_with_nix-shell#stdenv.mkDerivation
- https://github.com/NixOS/nixpkgs/blob/master/pkgs/stdenv/generic/setup.sh



## keywords

- nix-shell
  - nix-shell with build dependencies of derivation
  - nix develop
  - rewrite nix-shell in bash
    - generate rcfile for bash
    - get-env.sh
    - dump nix-shell environment to json file
    - declare bash variables
    - declare bash functions
    - bashFunctions
- nix-build
  - what would nix-build do
  - debug build phases of nix-build
  - debug a failing nix-build
  - debug a failing nix build
- nix
  - nixos
  - nixpkgs
