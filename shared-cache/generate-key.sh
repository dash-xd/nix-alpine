#!/usr/bin/env sh
set -eu

name="${1:-xd-dash-shared-1}"
out="${2:-.}"

mkdir -p "$out"
nix-store --generate-binary-cache-key   "$name"   "$out/nix-cache-private.key"   "$out/nix-cache-public.key"

chmod 600 "$out/nix-cache-private.key"
printf 'public key: '
cat "$out/nix-cache-public.key"
printf '\nprivate key written to %s\n' "$out/nix-cache-private.key"
