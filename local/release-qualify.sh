#!/usr/bin/env bash
set -Eeuo pipefail
[[ $# == 4 ]] || { echo "usage: release-qualify.sh COMPONENT VERSION CONTAINER STATE" >&2; exit 2; }
component="$1"; version="$2"; container="$3"; state="$4"
root="$state/$component"; record="$root/$version.json"
[[ -f "$record" ]] || { echo "candidate record missing" >&2; exit 1; }
flake="$(jq -er .flake_ref "$record")"
image="$(jq -er .image_id "$record")"
candidate="$(jq -er .candidate_tag "$record")"
[[ "$flake" == /workspaces/* && "$flake" == *#* ]] || exit 2
[[ "$(podman image inspect "$candidate" --format '{{.Id}}')" == "$image" ]] || {
  echo "candidate identity changed" >&2; exit 1;
}
source="${flake%%#*}"
# Validate that the source and lock did not move between build and qualification.
[[ "$(podman exec "$container" git -C "$source" rev-parse HEAD)" == "$(jq -r .source_sha "$record")" ]] || exit 1
[[ "$(podman exec "$container" sha256sum "$source/flake.lock" | cut -d' ' -f1)" == "$(jq -r .flake_lock_sha256 "$record")" ]] || exit 1
[[ "$(podman exec "$container" nix path-info "$flake")" == "$(jq -r .nix_output "$record")" ]] || exit 1

evidence_dir="$root/evidence/$version"; mkdir -p "$evidence_dir"
tmp="$(mktemp "$root/.evidence.XXXXXXXX")"; trap 'rm -f "$tmp"' EXIT
printf '{"schema":1,"gates":[' > "$tmp"
failed=0
for gate in qualify qualify-integration; do
  log="$evidence_dir/$gate.log"
  if podman exec -w "$source" "$container" nix run "${source}#$gate" > "$log" 2>&1; then code=0; else code=$?; failed=1; fi
  hash="$(sha256sum "$log" | cut -d' ' -f1)"
  [[ "$gate" == qualify ]] || printf ',' >> "$tmp"
  jq -cn --arg name "$gate" --arg sha "$hash" --argjson exit_code "$code" \
    '{name:$name,sha256:$sha,exit_code:$exit_code}' >> "$tmp"
done
printf ']}' >> "$tmp"
if [[ "$failed" != 0 ]]; then
  RELEASE_STATE="$state" bash "$(dirname "$0")/release-ledger.sh" fail "$component" "$version" "$tmp"
  echo "qualification failed; qualified tag was not created" >&2; exit 1
fi
# Check source, lock, store output, and image again after gates.
if [[ "$(podman exec "$container" git -C "$source" rev-parse HEAD)" != "$(jq -r .source_sha "$record")" ||
      "$(podman exec "$container" sha256sum "$source/flake.lock" | cut -d' ' -f1)" != "$(jq -r .flake_lock_sha256 "$record")" ||
      "$(podman exec "$container" nix path-info "$flake")" != "$(jq -r .nix_output "$record")" ||
      "$(podman image inspect "$candidate" --format '{{.Id}}')" != "$image" ]]; then
  RELEASE_STATE="$state" bash "$(dirname "$0")/release-ledger.sh" fail "$component" "$version" "$tmp"
  echo "release identity changed during qualification" >&2; exit 1
fi
RELEASE_STATE="$state" bash "$(dirname "$0")/release-ledger.sh" qualify "$component" "$version" "$tmp"
