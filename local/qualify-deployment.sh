#!/usr/bin/env bash
set -Eeuo pipefail
[[ $# == 2 ]] || { echo "usage: $0 BUILDER AGNI_CHECKOUT" >&2; exit 2; }
builder=$1 checkout=$2
out=$(podman exec "$builder" nix build --no-write-lock-file --no-link --print-out-paths "/workspaces/$checkout/local/fatline#deployment")
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
podman cp "$builder:$out/." - | tar -x --no-same-owner --no-same-permissions -C "$work/"
for component in redis logma skymill; do
  test -s "$work/quadlets/fatline-$component.container"
  test -s "$work/readiness/$component"
  bash -n "$work/readiness/$component"
done
test -s "$work/quadlets/fatline-reconcile.service"
test -s "$work/config/redis.conf"
grep -Fq 'Volume=%t/fatline/redis:/run/redis' "$work/quadlets/fatline-logma.container"
grep -Fq 'Volume=%t/fatline/redis:/run/redis' "$work/quadlets/fatline-skymill.container"
grep -Fq 'maxmemory-policy noeviction' "$work/config/redis.conf"
grep -Fq 'ExecStart=%h/.config/fatline/reconcile' "$work/quadlets/fatline-reconcile.service"
echo "PASS: generated deployment artifact structure, socket mounts and probe syntax"
echo "UNQUALIFIED: socket permissions, authenticated provider readiness, reconciler implementation, image promotion, live deployment"
