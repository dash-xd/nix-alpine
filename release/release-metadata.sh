#!/usr/bin/env bash
set -Eeuo pipefail

# Pure metadata capture in the builder container; never accesses host Podman.
[[ "${1:-}" == "capture" && $# == 5 ]] || {
  echo "usage: release-metadata capture COMPONENT VERSION SOURCE_DIR FLAKE_REF" >&2
  exit 2
}
component="$2"; version="$3"; source="$4"; flake="$5"
[[ "$component" =~ ^[a-z][a-z0-9-]*$ ]] || { echo "invalid component" >&2; exit 2; }
[[ "$version" =~ ^([0-9]{4})\.(0[1-9]|1[0-2])\.(0[1-9]|[12][0-9]|3[01])(\.(0|[1-9][0-9]*))?$ ]] || {
  echo "invalid CalVer" >&2; exit 2;
}
year="${BASH_REMATCH[1]}"; month="${BASH_REMATCH[2]}"; day="${BASH_REMATCH[3]}"; micro="${BASH_REMATCH[5]:-}"
# GNU date normalizes invalid dates, so require an exact round trip.
[[ "$(date -u -d "$year-$month-$day" +%Y.%m.%d 2>/dev/null)" == "$year.$month.$day" ]] || {
  echo "invalid calendar date" >&2; exit 2;
}
if [[ -n "$micro" ]]; then
  # shellcheck disable=SC2071
  [[ "${#micro}" -lt 20 || ( "${#micro}" -eq 20 && "$micro" < "18446744073709551616" ) ]] || {
    echo "micro version exceeds uint64" >&2; exit 2;
  }
fi
[[ "$source" == /workspaces/* && "$flake" == /workspaces/* ]] || {
  echo "source and flake must be workspace paths" >&2; exit 2;
}
sha="$(git -C "$source" rev-parse HEAD)"
[[ -z "$(git -C "$source" status --porcelain --untracked-files=all)" ]] || {
  echo "source checkout is dirty" >&2; exit 2;
}
lock="${flake%%#*}/flake.lock"
[[ -f "$lock" ]] || { echo "flake.lock is required for release" >&2; exit 2; }
lock_sha="$(sha256sum "$lock" | cut -d' ' -f1)"
output="$(nix path-info "$flake")"
[[ "$output" == /nix/store/* && "$output" != *$'\n'* ]] || {
  echo "expected one Nix store output" >&2; exit 2;
}
jq -n --arg component "$component" --arg version "$version" \
  --arg source_sha "$sha" --arg lock_sha256 "$lock_sha" \
  --arg flake_ref "$flake" --arg nix_output "$output" \
  '{schema:1,component:$component,version:$version,source_sha:$source_sha,flake_lock_sha256:$lock_sha256,flake_ref:$flake_ref,nix_output:$nix_output}'
