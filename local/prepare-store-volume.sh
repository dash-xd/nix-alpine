#!/usr/bin/env bash
set -Eeuo pipefail

IMAGE="${1:?image required}"
VOLUME="${2:?shared Nix volume required}"
command -v podman >/dev/null || { echo "Missing host command: podman" >&2; exit 2; }

podman run --rm --network=none \
  --userns=keep-id:uid=1000,gid=1000 \
  --user 0:0 \
  --volume "$VOLUME:/shared/nix:nocopy" \
  --entrypoint /bin/sh "$IMAGE" -c '
    uid="$(id -u nixuser)"
    gid="$(id -g nixuser)"
    chown "$uid:$gid" /shared/nix
    test -w /shared/nix
    printf "PASS: shared Nix volume root prepared for toolbox uid:gid %s:%s\\n" "$uid" "$gid"
  '
