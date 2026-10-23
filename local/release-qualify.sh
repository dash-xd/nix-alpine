#!/usr/bin/env bash
set -Eeuo pipefail
[[ $# == 4 ]] || { echo "usage: release-qualify.sh COMPONENT VERSION CONTAINER STATE" >&2; exit 2; }
component="$1"; version="$2"; container="$3"; state="$4"
case "$component" in
  redis) gates=(qualify-process qualify-service) ;;
  *) gates=(qualify qualify-integration) ;;
esac
root="$state/$component"; record="$root/$version.json"
[[ -f "$record" ]] || { echo "candidate record missing" >&2; exit 1; }
flake="$(jq -er .flake_ref "$record")"
image="$(jq -er .image_id "$record")"
candidate="$(jq -er .candidate_tag "$record")"
[[ "$flake" == /workspaces/* && "$flake" == *#* ]] || exit 2
candidate_id="$(podman image inspect "$candidate" --format '{{.Id}}')"
[[ "$candidate_id" =~ ^[a-f0-9]{64}$ ]] && candidate_id="sha256:$candidate_id"
[[ "$candidate_id" == "$image" ]] || {
  echo "candidate identity changed" >&2; exit 1;
}
source="${flake%%#*}"
[[ -z "$(podman exec "$container" git -C "$source" status --porcelain --untracked-files=all)" ]] || { echo "source dirty" >&2; exit 1; }
# Validate that the source and lock did not move between build and qualification.
[[ "$(podman exec "$container" git -C "$source" rev-parse HEAD)" == "$(jq -r .source_sha "$record")" ]] || exit 1
[[ "$(podman exec "$container" sha256sum "$source/flake.lock" | cut -d' ' -f1)" == "$(jq -r .flake_lock_sha256 "$record")" ]] || exit 1
[[ "$(podman exec "$container" nix path-info "$flake")" == "$(jq -r .nix_output "$record")" ]] || exit 1

evidence_dir="$root/evidence/$version"; mkdir -p "$evidence_dir"
tmp="$(mktemp "$root/.evidence.XXXXXXXX")"; trap 'rm -f "$tmp"' EXIT
jq -cn --arg image_id "$image" --arg source_sha "$(jq -r .source_sha "$record")" --arg nix_output "$(jq -r .nix_output "$record")" \
  '{schema:1,image_id:$image_id,source_sha:$source_sha,nix_output:$nix_output,gates:[]}' > "$tmp"
gates_file="$(mktemp "$root/.gates.XXXXXXXX")"; trap 'rm -f "$tmp" "$gates_file"' EXIT
printf '[' > "$gates_file"
failed=0
for gate in "${gates[@]}"; do
  log="$evidence_dir/$gate.log"
  if [[ "$component" == redis && "$gate" == qualify-service ]]; then
    # Smoke owns the runtime lifecycle and writes evidence for the ledger.
    service_evidence="$evidence_dir/service.json"
    smoke="${QUALIFY_SMOKE:-$HOME/workspace/nix/smoke}"
    agni="${QUALIFY_AGNI:-$HOME/workspace/nix/agni}"
    if [[ -f "$smoke/qualification/components/run.sh" ]]; then
      if bash "$smoke/qualification/components/run.sh" --component redis --agni "$agni" --builder "$container" --evidence "$service_evidence" > "$log" 2>&1; then code=0; else code=$?; failed=1; fi
    else
      echo "Smoke component runtime qualification entry point missing" > "$log"
      code=1; failed=1
    fi
  else
    if podman exec -w "$source" "$container" nix run "${source}#$gate" > "$log" 2>&1; then code=0; else code=$?; failed=1; fi
  fi
  hash="$(sha256sum "$log" | cut -d' ' -f1)"
  [[ "$gate" == "${gates[0]}" ]] || printf ',' >> "$gates_file"
  jq -cn --arg name "$gate" --arg sha "$hash" --argjson exit_code "$code" \
    '{name:$name,sha256:$sha,exit_code:$exit_code}' >> "$gates_file"
done
printf ']' >> "$gates_file"
jq --slurpfile gates "$gates_file" '.gates = $gates[0]' "$tmp" > "$tmp.final"
mv "$tmp.final" "$tmp"
if [[ "$component" == redis && -s "$evidence_dir/service.json" ]]; then
  jq --slurpfile service "$evidence_dir/service.json" '.service = $service[0]' "$tmp" > "$tmp.final"
  mv "$tmp.final" "$tmp"
fi
if [[ "$failed" != 0 ]]; then
  RELEASE_STATE="$state" bash "$(dirname "$0")/release-ledger.sh" fail "$component" "$version" "$tmp"
  echo "qualification failed; qualified tag was not created" >&2; exit 1
fi
# Check source, lock, store output, and image again after gates.
if [[ -n "$(podman exec "$container" git -C "$source" status --porcelain --untracked-files=all)" ||
      "$(podman exec "$container" git -C "$source" rev-parse HEAD)" != "$(jq -r .source_sha "$record")" ||
      "$(podman exec "$container" sha256sum "$source/flake.lock" | cut -d' ' -f1)" != "$(jq -r .flake_lock_sha256 "$record")" ||
      "$(podman exec "$container" nix path-info "$flake")" != "$(jq -r .nix_output "$record")" ||
      "$(podman image inspect "$candidate" --format '{{.Id}}' | sed -E 's/^(sha256:)?([a-f0-9]{64})$/sha256:\2/')" != "$image" ]]; then
  RELEASE_STATE="$state" bash "$(dirname "$0")/release-ledger.sh" fail "$component" "$version" "$tmp"
  echo "release identity changed during qualification" >&2; exit 1
fi
RELEASE_STATE="$state" bash "$(dirname "$0")/release-ledger.sh" qualify "$component" "$version" "$tmp"
