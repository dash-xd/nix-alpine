#!/usr/bin/env bash
set -Eeuo pipefail
[[ $# == 3 ]] || { echo "usage: $0 NIX_XD_ROOT WORKSPACES NIX_ALPINE_ROOT" >&2; exit 2; }
root=$1 workspaces=$2 nix_alpine=$3
for path in "$root" "$workspaces" "$nix_alpine"; do [[ -d "$path" ]] || { echo "Expected an existing directory: $path" >&2; exit 2; }; done
root=$(realpath "$root")
workspaces=$(realpath "$workspaces")
nix_alpine=$(realpath "$nix_alpine")
[[ "$workspaces" == "$root" ]] || { echo "WORKSPACES must resolve to canonical nix.xd root $root (got $workspaces)" >&2; exit 2; }
case "$nix_alpine" in "$root"/*) ;; *) echo "Nix-Alpine checkout is outside nix.xd root: $nix_alpine" >&2; exit 2;; esac
git_root=$(git -C "$nix_alpine" rev-parse --show-toplevel 2>/dev/null) || { echo "Nix-Alpine path is not a Git checkout: $nix_alpine" >&2; exit 2; }
[[ "$(realpath "$git_root")" == "$nix_alpine" ]] || { echo "NIX_ALPINE_ROOT must be the Git checkout root: $nix_alpine" >&2; exit 2; }
printf 'PASS: canonical workspace root %s; Nix-Alpine checkout %s\n' "$root" "$nix_alpine"
