#!/usr/bin/env bash
set -Eeuo pipefail
# Host-only import of the exact Nix output. No Nix installation on the host.
[[ $# == 4 ]] || { echo "usage: release-import.sh CONTAINER VOLUME NIX_OUTPUT RESULT_FILE" >&2; exit 2; }
container="$1"; volume="$2"; output="$3"; result="$4"
[[ "$output" == /nix/store/* && "$output" == *.tar.gz && "$output" != *$'\n'* ]] || {
  echo "expected one Nix image archive output" >&2; exit 2;
}
actual="$(podman exec "$container" nix path-info "$output")"
[[ "$actual" == "$output" ]] || { echo "Nix output not present in builder" >&2; exit 1; }
mountpoint="$(podman volume inspect "$volume" --format '{{.Mountpoint}}')"
[[ -n "$mountpoint" ]] || exit 1
archive="$mountpoint${output#/nix}"
podman unshare test -r "$archive"
digest="$(podman unshare sha256sum "$archive" | cut -d' ' -f1)"
# Capture the image ID from Podman's actual load response, never a supplied tag.
load_result="$(podman load -i "$archive")"
printf '%s\n' "$load_result" >&2
image_id="$(printf '%s\n' "$load_result" | sed -n 's/^Loaded image ID: \(sha256:[a-f0-9]*\)$/\1/p')"
if [[ -z "$image_id" ]]; then
  # Podman may report only a named image; inspect exactly one reported name.
  mapfile -t names < <(printf '%s\n' "$load_result" | sed -n 's/^Loaded image(s): //p')
  [[ "${#names[@]}" -eq 1 && -n "${names[0]}" ]] || {
    echo "cannot unambiguously resolve imported image identity" >&2; exit 1;
  }
  image_id="$(podman image inspect "${names[0]}" --format '{{.Id}}')"
fi
[[ "$image_id" =~ ^sha256:[a-f0-9]{64}$ ]] || {
  echo "invalid imported image ID: $image_id" >&2; exit 1;
}
mkdir -p "$(dirname "$result")"
tmp="$(mktemp "$(dirname "$result")/.import.XXXXXXXX")"
trap 'rm -f "$tmp"' EXIT
jq -n --arg nix_output "$output" --arg archive_sha256 "$digest" --arg image_id "$image_id" \
  '{nix_output:$nix_output,archive_sha256:$archive_sha256,image_id:$image_id}' > "$tmp"
mv -f "$tmp" "$result"
cat "$result"
