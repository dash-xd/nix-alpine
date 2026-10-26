#!/usr/bin/env bash
# Disposable rootless Redis Unix-socket access gate. No systemd installation.
set -Eeuo pipefail
[[ $# == 3 ]] || { echo "usage: $0 BUILDER AGNI_CHECKOUT REDIS_IMAGE" >&2; exit 2; }
builder=$1 checkout=$2 image=$3
podman image exists "$image" || { echo "missing Redis image: $image" >&2; exit 2; }
command -v podman >/dev/null
command -v tar >/dev/null
work=$(mktemp -d -t fatline-socket-XXXXXXXX)
name="fatline-socket-$$"
cleanup() {
  code=$?
  podman rm -f "$name" >/dev/null 2>&1 || true
  podman unshare chmod 700 "$work/socket" 2>/dev/null || true
  podman unshare chown 0:0 "$work/socket" 2>/dev/null || true
  chmod -R u+rwX "$work" 2>/dev/null || true
  rm -rf -- "$work" || code=1
  exit "$code"
}
trap cleanup EXIT
out=$(podman exec "$builder" nix build --no-write-lock-file --no-link --print-out-paths "/workspaces/$checkout/local/fatline#deployment")
podman cp "$builder:$out/config/redis.conf" - | tar -x --no-same-owner --no-same-permissions -C "$work"
# The image's Redis server must read both bind-mounted configuration files.
chmod 644 "$work/redis.conf"
pass=$(od -An -N24 -tx1 /dev/urandom | tr -d ' \n')
printf 'user default off\nuser qualify on >%s ~* +ping\n' "$pass" > "$work/users.acl"
chmod 644 "$work/users.acl"
mkdir -m 700 "$work/socket"
# Rootless user namespace: map container UID/GID 65534 to the backing host IDs.
podman unshare chown 65534:65534 "$work/socket"
podman unshare chmod 770 "$work/socket"
start() {
  podman run -d --name "$name" --network none --user 65534:65534 \
    --read-only --cap-drop ALL --security-opt no-new-privileges \
    -v "$work/socket:/run/redis" \
    -v "$work/redis.conf:/etc/redis/redis.conf:ro" \
    -v "$work/users.acl:/etc/redis/users.acl:ro" "$image" >/dev/null
  for i in $(seq 1 60); do
    podman unshare test -S "$work/socket/redis.sock" && return 0
    sleep .25
  done
  echo "DIAGNOSTIC: Redis socket absent from expected namespace-visible bind mount" >&2
  podman inspect "$name" --format '{{json .Mounts}}' >&2 || true
  podman unshare sh -c 'id; ls -ldn "$1"; ls -lan "$1"' sh "$work/socket" >&2 || true
  podman logs "$name" >&2 || true
  echo "FAIL: Redis socket not visible through podman unshare; inspect mount and UID diagnostics above" >&2
  return 1
}
probe() {
  # A separate container models provider access to the shared Unix socket.
  podman run --rm --network none --user 65534:65534 \
    --entrypoint redis-cli -v "$work/socket:/run/redis" "$image" \
    -s /run/redis/redis.sock --user qualify -a "$pass" PING 2>/dev/null | grep -Fx PONG
}
start
probe
# Verify ACL denial, not just socket reachability.
if podman run --rm --network none --user 65534:65534 \
  --entrypoint redis-cli -v "$work/socket:/run/redis" "$image" \
  -s /run/redis/redis.sock --user qualify -a "$pass" SET forbidden value 2>/dev/null | grep -q '^OK$'; then
  echo "FAIL: restricted Redis principal can write" >&2; exit 1
fi
echo "PASS: mapped UID socket, provider-container authenticated PING and write denial"
podman rm -f "$name" >/dev/null
# Redis is RAM-only. Socket should be recreated on restart, not reused.
podman unshare rm -f "$work/socket/redis.sock"
start
probe
echo "PASS: authenticated provider socket access after Redis restart"
echo "UNQUALIFIED: distinct Logma/Skymill image UID mapping, lifecycle restoration, systemd installation and rollback"
