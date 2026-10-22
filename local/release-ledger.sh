#!/usr/bin/env bash
set -Eeuo pipefail
# Host-side release ledger. Nix execution is confined to the builder container.
action="${1:?action required}"; component="${2:?component required}"
state="${RELEASE_STATE:?RELEASE_STATE required}"
[[ "$component" =~ ^[a-z][a-z0-9-]*$ ]] || exit 2
root="$state/$component"
mkdir -p "$root"
exec 9>"$root/.lock"
flock -x 9
case "$action" in
  version)
    today="$(date -u +%Y.%m.%d)"
    version="$today"; micro=0
    while [[ -e "$root/$version.json" ]]; do
      micro=$((micro+1)); version="$today.$micro"
    done
    printf '%s\n' "$version"
    ;;
  candidate)
    [[ $# == 5 ]] || { echo "candidate COMPONENT VERSION METADATA IMPORT" >&2; exit 2; }
    version="$3"; metadata="$4"; imported="$5"
    record="$root/$version.json"
    [[ ! -e "$record" ]] || { echo "version already reserved" >&2; exit 1; }
    jq -e --arg c "$component" --arg v "$version" \
      '.schema == 1 and .component == $c and .version == $v and (.nix_output | type == "string") and (.source_sha | test("^[0-9a-f]{40}$")) and (.flake_lock_sha256 | test("^[0-9a-f]{64}$"))' "$metadata" >/dev/null
    jq -e --arg output "$(jq -r .nix_output "$metadata")" \
      '.nix_output == $output and (.archive_sha256 | test("^[0-9a-f]{64}$")) and (.image_id | test("^sha256:[0-9a-f]{64}$"))' "$imported" >/dev/null
    id="$(jq -r .image_id "$imported")"
    tag="localhost/nix-alpine/$component:candidate-$version"
    if existing="$(podman image inspect "$tag" --format '{{.Id}}' 2>/dev/null)"; then
      [[ "$existing" == "$id" ]] || { echo "immutable candidate tag conflict" >&2; exit 1; }
    else
      podman image inspect "$id" >/dev/null
      podman tag "$id" "$tag"
    fi
    tmp="$(mktemp "$root/.candidate.XXXXXXXX")"
    trap 'rm -f "$tmp"' EXIT
    jq -s --arg tag "$tag" '.[0] + .[1] + {status:"candidate",candidate_tag:$tag}' "$metadata" "$imported" >"$tmp"
    # No overwrite: preserve the version reservation across crashes/retries.
    ln "$tmp" "$record"
    cat "$record"
    ;;
  *)
    echo "unsupported release action: $action" >&2; exit 2 ;;
esac
