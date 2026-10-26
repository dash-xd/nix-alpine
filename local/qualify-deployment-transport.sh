#!/usr/bin/env bash
# Disposable Redis Unix + Nginx TCP-to-Unix transport gate. No systemd changes.
set -Eeuo pipefail
[[ $# == 5 ]] || { echo "usage: $0 BUILDER AGNI_CHECKOUT REDIS_IMAGE NGINX_IMAGE SCOPE" >&2; exit 2; }
builder=$1 checkout=$2 redis_image=$3 nginx_image=$4 scope=$5
for image in "$redis_image" "$nginx_image"; do podman image exists "$image" || { echo "Missing image: $image" >&2; exit 2; }; done
work=$(mktemp -d -t fatline-transport-XXXXXXXX)
prefix="fatline-transport-$$"
net="$prefix-net"
redis="$prefix-redis"
proxy="$prefix-proxy"
cleanup() {
  code=$?
  podman rm -f "$proxy" "$redis" >/dev/null 2>&1 || true
  podman network rm "$net" >/dev/null 2>&1 || true
  podman unshare chmod 700 "$work/socket" 2>/dev/null || true
  podman unshare chown 0:0 "$work/socket" 2>/dev/null || true
  chmod -R u+rwX "$work" 2>/dev/null || true
  rm -rf -- "$work" || code=1
  exit "$code"
}
trap cleanup EXIT
out=$(podman exec "$builder" nix build --no-write-lock-file --no-link --print-out-paths "/workspaces/$checkout/local/fatline#deployment-mixed")
podman cp "$builder:$out/config/redis.conf" - | tar -x --no-same-owner --no-same-permissions -C "$work"
podman cp "$builder:$out/config/redis-proxy.conf" - | tar -x --no-same-owner --no-same-permissions -C "$work"
chmod 644 "$work/redis.conf" "$work/redis-proxy.conf"
pass=$(od -An -N24 -tx1 /dev/urandom | tr -d ' \n')
printf 'user default off\nuser qualify on >%s ~* +ping\n' "$pass" > "$work/users.acl"
chmod 644 "$work/users.acl"
mkdir -m 700 "$work/socket"
podman unshare chown 65534:65534 "$work/socket"
podman unshare chmod 770 "$work/socket"
podman network create --internal "$net" >/dev/null
start_redis() {
  podman run -d --name "$redis" --network none --user 65534:65534 \
    --read-only --cap-drop ALL --security-opt no-new-privileges \
    -v "$work/socket:/run/redis" \
    -v "$work/redis.conf:/etc/redis/redis.conf:ro" \
    -v "$work/users.acl:/etc/redis/users.acl:ro" "$redis_image" >/dev/null
  for i in $(seq 1 60); do
    podman unshare test -S "$work/socket/redis.sock" && return 0
    sleep .25
  done
  podman logs "$redis" >&2 || true
  echo "FAIL: Redis socket unavailable" >&2
  return 1
}
unix_cli() {
  podman run --rm --network none --user 65534:65534 --entrypoint redis-cli \
    -v "$work/socket:/run/redis" "$redis_image" \
    -s /run/redis/redis.sock --user qualify "$@"
}
tcp_cli() {
  podman run --rm --network "$net" --entrypoint redis-cli "$redis_image" \
    -h "$proxy" -p 6379 --user qualify "$@"
}
assert_access() {
  local mode=$1
  local reply
  if [[ "$mode" == unix ]]; then
    reply=$(unix_cli PING)
  else
    reply=$(tcp_cli PING)
  fi
  [[ "$reply" == PONG ]] || { echo "FAIL: $mode PING: $reply" >&2; return 1; }
  if [[ "$mode" == unix ]]; then reply=$(unix_cli SET forbidden value); else reply=$(tcp_cli SET forbidden value); fi
  [[ "$reply" == *NOPERM* ]] || { echo "FAIL: $mode expected NOPERM, got: $reply" >&2; return 1; }
  echo "PASS: $mode authenticated PING and explicit NOPERM denial"
}
start_redis
podman run -d --name "$proxy" --network "$net" --network-alias "$proxy" \
  --user 65534:65534 --read-only --cap-drop ALL --security-opt no-new-privileges \
  --tmpfs /tmp:rw,noexec,nosuid,size=4m \
  -v "$work/socket:/run/redis" \
  -v "$work/redis-proxy.conf:/etc/nginx/nginx.conf:ro" "$nginx_image" >/dev/null
for i in $(seq 1 40); do
  if [[ "$(podman inspect -f '{{.State.Running}}' "$proxy")" != true ]]; then
    podman logs "$proxy" >&2 || true
    echo "FAIL: Nginx stream proxy exited; inspect stream module availability" >&2
    exit 1
  fi
  if tcp_cli PING 2>/dev/null | grep -Fxq PONG; then break; fi
  sleep .25
done
assert_access unix
assert_access tcp
podman rm -f "$redis" >/dev/null
podman unshare rm -f "$work/socket/redis.sock"
start_redis
assert_access unix
assert_access tcp
echo "PASS: both transports reconnect after Redis restart"
echo "UNQUALIFIED: actual Logma/Skymill Redis client configuration, Quadlet installation and rollback"
