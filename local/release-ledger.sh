#!/usr/bin/env bash
set -Eeuo pipefail
action="${1:?action required}"; component="${2:?component required}"
state="${RELEASE_STATE:?RELEASE_STATE required}"
[[ "$component" =~ ^[a-z][a-z0-9-]*$ ]] || exit 2
root="$state/$component"; mkdir -p "$root"
exec 9>"$root/.lock"; flock -x 9

write_json() {
  local dest="$1" tmp
  tmp="$(mktemp "$root/.record.XXXXXXXX")"
  cat > "$tmp"
  # Same-filesystem atomic replacement; caller holds exclusive component lock.
  mv -f "$tmp" "$dest"
}

check_image() {
  local id="$1" tag="$2" got
  got="$(podman image inspect "$tag" --format '{{.Id}}')"
  [[ "$got" =~ ^[a-f0-9]{64}$ ]] && got="sha256:$got"
  [[ "$got" == "$id" ]] || { echo "image identity mismatch: $tag" >&2; return 1; }
}
case "$action" in
  version)
    today="$(date -u +%Y.%m.%d)"; version="$today"; micro=0
    while [[ -e "$root/$version.json" ]]; do micro=$((micro+1)); version="$today.$micro"; done
    printf '%s\n' "$version"
    ;;
  candidate)
    [[ $# == 5 ]] || exit 2
    version="$3"; metadata="$4"; imported="$5"; record="$root/$version.json"
    [[ ! -e "$record" ]] || { echo "version already recorded" >&2; exit 1; }
    jq -e --arg c "$component" --arg v "$version" \
      '.schema == 1 and .component == $c and .version == $v and (.nix_output | type == "string") and (.source_sha | test("^[a-f0-9]{40}$")) and (.flake_lock_sha256 | test("^[a-f0-9]{64}$"))' "$metadata" >/dev/null
    jq -e --arg out "$(jq -r .nix_output "$metadata")" \
      '.nix_output == $out and (.archive_sha256 | test("^[a-f0-9]{64}$")) and (.image_id | test("^sha256:[a-f0-9]{64}$"))' "$imported" >/dev/null
    id="$(jq -r .image_id "$imported")"
    tag="localhost/nix-alpine/$component:candidate-$version"
    if podman image inspect "$tag" >/dev/null 2>&1; then
      echo "orphaned or pre-existing candidate tag; refusing unrecorded version" >&2; exit 1
    fi
    check_image "$id" "$id"
    podman tag "$id" "$tag"
    check_image "$id" "$tag"
    tmp="$(mktemp "$root/.candidate.XXXXXXXX")"
    trap 'rm -f "$tmp"' EXIT
    jq -s --arg tag "$tag" '.[0] + .[1] + {status:"candidate",candidate_tag:$tag}' "$metadata" "$imported" > "$tmp"
    ln "$tmp" "$record"
    cat "$record"
    ;;
  qualify)
    [[ $# == 4 ]] || { echo "qualify COMPONENT VERSION EVIDENCE_JSON" >&2; exit 2; }
    version="$3"; evidence="$4"; record="$root/$version.json"
    [[ -f "$record" ]] || { echo "candidate record missing" >&2; exit 1; }
    jq -e '.status == "candidate" or .status == "failed"' "$record" >/dev/null
    image_id="$(jq -er .image_id "$record")"
    candidate="$(jq -er .candidate_tag "$record")"
    check_image "$image_id" "$candidate"
    # Required gate set is determined by component, never by supplied evidence.
    case "$component" in
      redis) first="qualify-process"; second="qualify-service" ;;
      *) first="qualify"; second="qualify-integration" ;;
    esac
    # The gate runner must produce a complete, successful fixed gate set.
    jq -e --arg first "$first" --arg second "$second" --arg expected_id "$image_id" --arg expected_source "$(jq -r .source_sha "$record")" --arg expected_output "$(jq -r .nix_output "$record")" \
      '.schema == 1 and .image_id == $expected_id and .source_sha == $expected_source and .nix_output == $expected_output and (.gates | length == 2) and
      .gates[0].name == $first and .gates[1].name == $second and
      all(.gates[]; .exit_code == 0 and (.sha256 | test("^[a-f0-9]{64}$")))' "$evidence" >/dev/null
    tag="localhost/nix-alpine/$component:qualified-$version"
    if podman image inspect "$tag" >/dev/null 2>&1; then
      echo "qualified tag already exists without qualified record" >&2; exit 1
    fi
    podman tag "$image_id" "$tag"
    check_image "$image_id" "$candidate"
    check_image "$image_id" "$tag"
    jq -s --arg tag "$tag" '.[0] + .[1] + {status:"qualified",qualified_tag:$tag}' "$record" "$evidence" | write_json "$record"
    cat "$record"
    ;;
  inspect)
    [[ $# == 3 ]] || exit 2
    version="$3"; record="$root/$version.json"
    [[ -f "$record" ]] || { echo "release record missing" >&2; exit 1; }
    jq . "$record"
    ;;
  fail)
    [[ $# == 4 ]] || exit 2
    version="$3"; evidence="$4"; record="$root/$version.json"
    [[ -f "$record" ]] || exit 1
    jq -e '.status == "candidate" or .status == "failed"' "$record" >/dev/null
    jq -s '.[0] + {status:"failed",last_failure:.[1]}' "$record" "$evidence" | write_json "$record"
    ;;
  *) echo "unsupported action: $action" >&2; exit 2 ;;
esac
