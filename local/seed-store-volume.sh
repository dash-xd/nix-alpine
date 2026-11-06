#!/usr/bin/env bash
set -Eeuo pipefail

PASS_MARKER="PASS: image Nix profile closure seeded into shared store"

if [[ "${1:-}" == --inside ]]; then
  [[ -w /shared/nix ]] || { echo "Shared Nix volume is not writable by the mapped toolbox user" >&2; exit 1; }
  profile="$(readlink -f "$HOME/.nix-profile")"
  [[ "$profile" == /nix/store/* && -d "$profile" ]] || {
    echo "Current image Nix profile is not a valid store path: $profile" >&2
    exit 1
  }

  echo "Merging image profile closure into the existing shared Nix store"
  nix copy --to "local?root=/shared" "$profile"
  test -e "/shared/nix/store/${profile#/nix/store/}"
  nix path-info --store "local?root=/shared" "$profile" >/dev/null
  echo "$PASS_MARKER"
  exit 0
fi

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
IMAGE="${1:?image required}"
VOLUME="${2:?shared volume required}"
command -v podman >/dev/null || { echo "Missing host command: podman" >&2; exit 2; }

output="$(
  podman run --interactive --rm --network=none \
    --userns=keep-id:uid=1000,gid=1000 \
    --volume "$VOLUME:/shared/nix:nocopy" \
    "$IMAGE" /bin/bash -s -- --inside < "$SCRIPT_DIR/$(basename -- "${BASH_SOURCE[0]}")"
)"
printf '%s\n' "$output"
grep -Fxq "$PASS_MARKER" <<<"$output" || {
  echo "Shared Nix store seeding did not emit its success marker" >&2
  exit 1
}
