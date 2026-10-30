#!/usr/bin/env bash
# Non-mutating preflight for the qualified Fatline Redis/Nginx/Logma topology.
set -Eeuo pipefail
[[ $# == 4 ]] || { echo "usage: $0 BUILDER REDIS_IMAGE NGINX_IMAGE LOGMA_IMAGE" >&2; exit 2; }
builder=$1 redis_image=$2 nginx_image=$3 logma_image=$4
root="${WORKSPACES:-$HOME/workspace/nix}"
agni="$root/${COMPOSITION_AGNI_CHECKOUT:-agni-qualification}/local/fatline"
[[ -f "$agni/composition.nix" && -f "$agni/flake.nix" ]] || { echo "Agni local/fatline checkout required" >&2; exit 2; }
[[ "$(podman info --format '{{.Host.Security.Rootless}}')" == true ]] || { echo "Rootless Podman required" >&2; exit 1; }
podman container exists "$builder" || { echo "Nix-Alpine builder not running" >&2; exit 1; }
for image in "$redis_image" "$nginx_image" "$logma_image"; do
  id=$(podman image inspect "$image" --format '{{.Id}}')
  [[ "$id" =~ ^[a-f0-9]{64}$|^sha256:[a-f0-9]{64}$ ]] || { echo "Invalid image ID: $image" >&2; exit 1; }
  echo "$image -> $id"
done
# Build the Nix-owned Nginx qualification artifact in the isolated builder.
# This is a source/build gate, not the final runtime integration gate.
podman exec "$builder" nix build --no-write-lock-file --no-link /workspaces/${COMPOSITION_AGNI_CHECKOUT:-agni-qualification}/local/fatline#nginx-qualification
# Confirm the final production composition (not the HTTP-only Nginx probe)
# retains its TCP-to-Unix stream topology and network alias.
grep -Fq 'upstream redis_socket { server unix:/run/redis/redis.sock; }' "$agni/composition.nix"
grep -Fq 'listen 6379;' "$agni/composition.nix"
grep -Fq 'proxy_pass redis_socket;' "$agni/composition.nix"
grep -Fq 'NetworkAlias=redis-proxy' "$agni/composition.nix"
grep -Fq 'Network=fatline.network' "$agni/composition.nix"
grep -Fq 'Internal=true' "$agni/composition.nix"
grep -Fq 'maxmemory 40mb' "$agni/composition.nix" || grep -Fq 'maxmemory ${toString redis.memoryMiB}mb' "$agni/composition.nix"
grep -Fq 'maxmemory-policy noeviction' "$agni/composition.nix"
ports=$(podman image inspect "$logma_image" --format '{{json .Config.ExposedPorts}}')
[[ "$ports" == *'8080/tcp'* ]] || { echo "Logma provider image does not expose its configured HTTP port" >&2; exit 1; }
grep -Fq 'Environment=LOGMA_BIND_ADDR=0.0.0.0' "$agni/composition.nix" || { echo "Agni composition must bind Logma on the container interface" >&2; exit 1; }
grep -Fq 'Environment=REDIS_NETWORK=tcp' "$agni/composition.nix" || { echo "Agni composition must select Logma TCP Redis transport" >&2; exit 1; }
grep -Fq 'Environment=REDIS_URI=redis-proxy:6379' "$agni/composition.nix" || { echo "Agni composition must route Logma to the Redis proxy" >&2; exit 1; }
echo "PASS: Fatline composition preflight passed; runtime checks follow in the selected gate."
