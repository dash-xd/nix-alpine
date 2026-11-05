#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

if [[ "${1:-}" == --inside ]]; then
  profile="$(readlink -f "$HOME/.nix-profile")"
  [[ "$profile" == /nix/store/* && -d "$profile" ]] || {
    echo "Current image Nix profile is not a valid store path: $profile" >&2
    exit 1
  }

  echo "Merging the image Nix profile closure into the shared store"
  nix copy --to "local?root=/shared" "$profile"

  profile_dir="/shared/nix/var/nix/profiles/per-user/$USER"
  mkdir -p "$profile_dir"
  ln -sfn "$profile" "$profile_dir/profile"
  test -e "/shared/nix/store/${profile#/nix/store/}"
  echo "PASS: current Nix profile closure is registered in the shared store"
  exit 0
fi

IMAGE="${1:?image required}"
VOLUME="${2:?shared volume required}"
command -v podman >/dev/null || { echo "Missing host command: podman" >&2; exit 2; }

podman run --rm --network=none \
  --userns=keep-id:uid=1000,gid=1000 \
  --volume "$VOLUME:/shared/nix" \
  "$IMAGE" /bin/bash -s -- --inside < "$SCRIPT_DIR/$(basename -- "${BASH_SOURCE[0]}")"
