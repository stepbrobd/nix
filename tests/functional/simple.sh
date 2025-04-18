#!/usr/bin/env bash

source common.sh

drvPath=$(nix-instantiate simple.nix)

test "$(nix-store -q --binding system "$drvPath")" = "$system"

echo "derivation is $drvPath"

outPath=$(nix-store -rvv "$drvPath")

echo "output path is $outPath"

[[ ! -w $outPath ]]

text=$(cat "$outPath/hello")
[[ "$text" = "Hello World!" ]]

TODO_NixOS

# Directed delete: $outPath is not reachable from a root, so it should
# be deleteable.
nix-store --delete "$outPath"
[[ ! -e $outPath/hello ]]

outPath="$(NIX_REMOTE='local?store=/foo&real='"$TEST_ROOT"'/real-store' nix-instantiate --readonly-mode hash-check.nix)"
if test "$outPath" != "/foo/lfy1s6ca46rm5r6w4gg9hc0axiakjcnm-dependencies.drv"; then
    echo "hashDerivationModulo appears broken, got $outPath"
    exit 1
fi

outPath="$(NIX_REMOTE='local?store=/foo&real='"$TEST_ROOT"'/real-store' nix-instantiate --readonly-mode big-derivation-attr.nix)"
if test "$outPath" != "/foo/xxiwa5zlaajv6xdjynf9yym9g319d6mn-big-derivation-attr.drv"; then
    echo "big-derivation-attr.nix hash appears broken, got $outPath. Memory corruption in large drv attr?"
    exit 1
fi
