#!/usr/bin/env bash
set -Eeuo pipefail
[[ $# == 2 ]] || { echo "usage: $0 BUILDER AGNI_CHECKOUT" >&2; exit 2; }
builder=$1 checkout=$2
out=$(podman exec "$builder" nix build --no-write-lock-file --no-link --print-out-paths "/workspaces/$checkout/local/fatline#deployment")
work=$(mktemp -d)
trap 'chmod -R u+rwX "$work" 2>/dev/null || true; rm -rf -- "$work"' EXIT
podman cp "$builder:$out/." - | tar -x --no-same-owner --no-same-permissions -C "$work/"
chmod -R u+rwX "$work"
for component in redis logma skymill; do
  test -s "$work/quadlets/fatline-$component.container"
  test -s "$work/readiness/$component"
  bash -n "$work/readiness/$component"
done
test -s "$work/quadlets/fatline-reconcile.service"
test -s "$work/config/redis.conf"
# Validate each provider's declared transport without assuming all providers use Unix.
for component in logma skymill; do
  file="$work/quadlets/fatline-$component.container"
  if grep -Fqx 'Environment=FATLINE_REDIS_TRANSPORT=unix' "$file"; then
    grep -Fq 'Volume=%t/fatline/redis:/run/redis' "$file"
  elif grep -Fqx 'Environment=FATLINE_REDIS_TRANSPORT=tcp-proxy' "$file"; then
    ! grep -Fq 'Volume=%t/fatline/redis:/run/redis' "$file"
    test -s "$work/quadlets/fatline-redis-proxy.container"
    test -s "$work/config/redis-proxy.conf"
    grep -Fqx 'NetworkAlias=fatline-redis-proxy' "$work/quadlets/fatline-redis-proxy.container"
    grep -Fqx 'Environment=FATLINE_REDIS_ENDPOINT=fatline-redis-proxy:6379' "$file"
    grep -Fq 'proxy_pass unix:/run/redis/redis.sock;' "$work/config/redis-proxy.conf"
    grep -Fq 'After=fatline-redis-proxy.service' "$file"
  else
    echo "FAIL: $component transport is not declared" >&2
    exit 1
  fi
done
grep -Fq 'maxmemory-policy noeviction' "$work/config/redis.conf"
grep -Fq 'REDISCLI_AUTH=' "$work/readiness/redis"
grep -Fq 'PING | grep -Fx PONG' "$work/readiness/redis"
grep -Fq 'FATLINE_LOGMA_READINESS_URL' "$work/readiness/logma"
grep -Fq 'FATLINE_SKYMILL_READINESS_URL' "$work/readiness/skymill"
! grep -Fq '0777' "$work/quadlets/fatline-redis.container"
grep -Fq 'podman unshare install -d -o 65534 -g 65534 -m 0770' "$work/quadlets/fatline-redis.container"
grep -Fq 'ExecStart=%h/.config/fatline/reconcile' "$work/quadlets/fatline-reconcile.service"
echo "PASS: generated deployment structure, per-provider transport contracts, fail-closed readiness and probe syntax"
echo "UNQUALIFIED: provider-specific client endpoint semantics, TCP proxy runtime, reconciler implementation, image promotion, live deployment"
