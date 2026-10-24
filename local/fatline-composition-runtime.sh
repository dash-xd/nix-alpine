#!/usr/bin/env bash
# Disposable runtime composition. Never installs units or promotes release tags.
set -Eeuo pipefail
[[ $# == 4 ]] || { echo "usage: $0 BUILDER REDIS_IMAGE NGINX_IMAGE LOGMA_IMAGE" >&2; exit 2; }
builder=$1 redis_image=$2 nginx_image=$3 logma_image=$4
scope="fatline-composition-$$"
work=$(mktemp -d)
net="$scope"
socket="$work/socket"
redis="$scope-redis"
nginx="$scope-nginx"
logma="$scope-logma"
cleanup() {
  podman rm -f "$logma" "$nginx" "$redis" >/dev/null 2>&1 || true
  podman network rm "$net" >/dev/null 2>&1 || true
  rm -rf "$work"
}
trap cleanup EXIT
mkdir -m 777 "$socket"
# Nix owns the exact Agni Redis/Nginx configuration; no hand-copied proxy config.
out=$(podman exec "$builder" nix build --no-write-lock-file --no-link --print-out-paths /workspaces/agni/local/fatline#composition-qualification)
podman cp "$builder:$out/config/redis.conf" "$work/redis.conf"
podman cp "$builder:$out/config/nginx.conf" "$work/nginx.conf"
chmod 644 "$work/redis.conf" "$work/nginx.conf"
redis_pass=$(od -An -N24 -tx1 /dev/urandom | tr -d ' \n')
api_pass=$(od -An -N24 -tx1 /dev/urandom | tr -d ' \n')
# Restrict keyspace; lifecycle runtime's complete command-level ACL remains
# a separate qualification gate. Do not equate this with production ACL approval.
printf 'user default off\nuser logma on >%s ~logma:* ~active_subscriptions:* ~subscription_groups:* +@read +@write +@pubsub +ping -@admin -@dangerous\n' "$redis_pass" > "$work/users.acl"
chmod 644 "$work/users.acl"
podman network create --internal "$net" >/dev/null
# Same unprivileged UID owns the socket and connects through Nginx.
podman run -d --name "$redis" --network none --user 65534:65534 \
  --read-only --cap-drop ALL --security-opt no-new-privileges \
  -v "$socket:/run/redis" \
  -v "$work/redis.conf:/etc/redis/redis.conf:ro" \
  -v "$work/users.acl:/etc/redis/users.acl:ro" \
  "$redis_image" >/dev/null
for i in $(seq 1 60); do [[ -S "$socket/redis.sock" ]] && break; sleep .25; done
[[ -S "$socket/redis.sock" ]] || { podman logs "$redis"; exit 1; }
podman run -d --name "$nginx" --network "$net" --network-alias redis-proxy \
  --user 65534:65534 --read-only --cap-drop ALL --security-opt no-new-privileges \
  --tmpfs /tmp:rw,noexec,nosuid,size=4m,mode=1777 \
  -v "$socket:/run/redis" -v "$work/nginx.conf:/etc/nginx/nginx.conf:ro" \
  "$nginx_image" >/dev/null
cli_entry=$(podman image inspect "$redis_image" --format '{{index .Config.Entrypoint 0}}')
cli="${cli_entry%redis-server}redis-cli"
redis_cli() {
  podman run --rm --network "container:$nginx" --entrypoint "$cli" \
    "$redis_image" -h 127.0.0.1 -p 6379 --user logma -a "$redis_pass" --no-auth-warning "$@"
}
for i in $(seq 1 60); do
  if [[ "$(redis_cli PING 2>/dev/null)" == PONG ]]; then break; fi
  sleep .25
done
[[ "$(redis_cli PING)" == PONG ]] || { podman logs "$nginx"; exit 1; }
[[ "$(redis_cli SET logma:qualification ok)" == OK ]]
[[ "$(redis_cli GET logma:qualification)" == ok ]]
[[ "$(redis_cli SET foreign:denied value)" == *NOPERM* ]]
[[ "$(redis_cli ACL LIST)" == *NOPERM* ]]
echo "PASS: authenticated TCP -> Nginx -> Unix Redis, key isolation, admin denial"
podman run -d --name "$logma" --network "$net" \
  --user 65534:65534 --read-only --cap-drop ALL --security-opt no-new-privileges \
  --mount type=tmpfs,destination=/var/lib/logma/lifecycle,tmpfs-size=4194304,tmpfs-mode=1777 \
  -e LOGMA_LIFECYCLE_STATE_DIR=/var/lib/logma/lifecycle \
  -e REDIS_USERNAME=logma -e REDISCLI_AUTH="$redis_pass" -e API_KEY="$api_pass" \
  -p 127.0.0.1::8080 "$logma_image" >/dev/null
port=$(podman port "$logma" 8080/tcp | sed -n '1s/.*://p')
[[ "$port" =~ ^[0-9]+$ ]] || { echo "Cannot resolve published Logma port" >&2; exit 1; }
url="http://127.0.0.1:$port/lifecycle/policies"
for i in $(seq 1 60); do
  status=$(curl -sS --max-time 2 -o /dev/null -w '%{http_code}' -H "X-API-Key: $api_pass" "$url" 2>/dev/null || true)
  [[ "$status" == 200 ]] && break
  sleep .25
done
[[ "$status" == 200 ]] || { podman logs "$logma"; echo "Authenticated lifecycle policies HTTP $status" >&2; exit 1; }
[[ "$(curl -sS -o /dev/null -w '%{http_code}' "$url")" == 401 ]]
[[ "$(curl -sS -o /dev/null -w '%{http_code}' -H 'X-API-Key: incorrect' "$url")" == 401 ]]
logma_id=$(podman image inspect "$logma_image" --format '{{.Id}}')
[[ "$(podman inspect "$logma" --format '{{.Image}}')" == "$logma_id" ]]
podman restart "$logma" >/dev/null
for i in $(seq 1 60); do
  status=$(curl -sS --max-time 2 -o /dev/null -w '%{http_code}' -H "X-API-Key: $api_pass" "$url" 2>/dev/null || true)
  [[ "$status" == 200 ]] && break
  sleep .25
done
[[ "$status" == 200 ]]
[[ "$(podman inspect "$logma" --format '{{.Image}}')" == "$logma_id" ]]
echo "PASS: Logma unprivileged read-only HTTP auth and restart with immutable image identity"
echo "Fatline runtime connectivity gate passed; lifecycle Redis command coverage and systemd-user Quadlet restart remain unqualified."
