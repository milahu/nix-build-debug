#!/bin/sh

cd "$(dirname "$0")"

nix-build -E 'with import <nixpkgs> {}; stdenv.mkDerivation { name = "x"; buildCommand = "env; exit 1"; }' 2>&1 | tee nix-build-env.txt
