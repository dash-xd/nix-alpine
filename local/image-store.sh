#!/usr/bin/env bash
set -Eeuo pipefail
container="${1:?container required}"
volume="${2:?volume required}"
flake_ref="${3:?flake reference required}"

archive="$(podman exec "$container" nix path-info "$flake_ref")"
[[ "$archive" == /nix/store/* && "$archive" != *$'\n'* && "$archive" == *.tar.gz ]] || {
  echo "Expected one built Nix image archive (.tar.gz), got: $archive" >&2
  exit 1
}
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
