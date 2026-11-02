#!/usr/bin/env bash
set -Eeuo pipefail
container="${1:?container required}"
volume="${2:?volume required}"
flake_ref="${3:?flake reference required}"

archive="$(podman exec "$container" nix path-info --no-write-lock-file "$flake_ref")"
[[ "$archive" == /nix/store/* && "$archive" != *$'\n'* && "$archive" == *.tar.gz ]] || {
  echo "Expected one built Nix image archive (.tar.gz), got: $archive" >&2
  exit 1
}

# A remote Podman client can stream the archive directly from its mounted Nix
# store to the host API. Host-side callers still need the rootless volume path
# and podman-unshare because the store's files are owned by the subordinate UID.
if [[ -n "${CONTAINER_HOST:-}" ]]; then
  podman load --input "$archive"
  exit 0
fi

mountpoint="$(podman volume inspect "$volume" --format '{{.Mountpoint}}')"
[[ -n "$mountpoint" ]] && podman unshare test -d "$mountpoint/store" || {
  echo "Missing scoped Nix store volume: $volume" >&2
  exit 1
}
host_archive="$mountpoint${archive#/nix}"
podman unshare test -r "$host_archive" || {
  echo "Image archive not readable in scoped store: $archive" >&2
  exit 1
}
podman unshare podman load -i "$host_archive"
