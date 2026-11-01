#!/usr/bin/env bash
set -Eeuo pipefail

action=${1:-inspect}
resource=${2:-}
prefix=${3:-}
dry_run=${4:-1}

case "$action" in
  inspect|cleanup) ;;
  *) echo "ACTION must be inspect or cleanup" >&2; exit 2 ;;
esac
case "$resource" in
  units|containers|networks|images|volumes) ;;
  *) echo "RESOURCE must be units, containers, networks, images or volumes" >&2; exit 2 ;;
esac
[[ "$dry_run" == 0 || "$dry_run" == 1 ]] || { echo "DRY_RUN must be 0 or 1" >&2; exit 2; }
if [[ "$action" == cleanup && -z "$prefix" ]]; then
  echo "cleanup requires a literal PREFIX; inspect may omit it to list all resources" >&2
  exit 2
fi

names=()
declare -A details=()

matches_prefix() {
  [[ -z "$prefix" || "$1" == "$prefix"* ]]
}

collect_resources() {
  local name state load active sub description ref image_id
  case "$resource" in
    units)
      while read -r name load active sub description; do
        [[ -n "$name" ]] || continue
        matches_prefix "$name" || continue
        names+=("$name")
        details["$name"]="$active/$sub"
      done < <(systemctl --user list-units --all --type=service --no-legend --no-pager)
      ;;
    containers)
      while IFS=$'\t' read -r name state; do
        [[ -n "$name" ]] || continue
        matches_prefix "$name" || continue
        names+=("$name")
        details["$name"]="$state"
      done < <(podman ps -a --format '{{.Names}}\t{{.State}}')
      ;;
    networks)
      while IFS= read -r name; do
        [[ -n "$name" ]] || continue
        matches_prefix "$name" || continue
        names+=("$name")
        details["$name"]="network"
      done < <(podman network ls --format '{{.Name}}')
      ;;
    images)
      while IFS=$'\t' read -r ref image_id; do
        [[ -n "$ref" ]] || continue
        matches_prefix "$ref" || continue
        names+=("$ref")
        details["$ref"]="$image_id"
      done < <(podman images --no-trunc --format '{{.Repository}}:{{.Tag}}\t{{.ID}}')
      ;;
    volumes)
      while IFS= read -r name; do
        [[ -n "$name" ]] || continue
        matches_prefix "$name" || continue
        names+=("$name")
        details["$name"]="volume"
      done < <(podman volume ls --format '{{.Name}}')
      ;;
  esac
}

collect_resources
if [[ "${#names[@]}" == 0 ]]; then
  printf 'No %s matched prefix %q.\n' "$resource" "$prefix"
  exit 0
fi

printf '%s matching %q (%d):\n' "$resource" "$prefix" "${#names[@]}"
for name in "${names[@]}"; do
  printf '  %-64s %s\n' "$name" "${details[$name]}"
done

[[ "$action" != cleanup ]] || [[ "$dry_run" == 0 ]] || {
  echo "DRY_RUN=1: no changes; rerun with DRY_RUN=0 to apply this scoped cleanup."
  exit 0
}

[[ "$action" == cleanup ]] || exit 0
for name in "${names[@]}"; do
  case "$resource" in
    units)
      if ! systemctl --user stop "$name"; then
        echo "SKIP: could not stop unit $name" >&2
        continue
      fi
      systemctl --user reset-failed "$name" >/dev/null 2>&1 || true
      ;;
    containers)
      if [[ "${details[$name]}" == running || "${details[$name]}" == paused ]]; then
        echo "SKIP: active container $name" >&2
        continue
      fi
      podman rm "$name"
      ;;
    networks)
      if ! podman network rm "$name"; then
        echo "SKIP: network $name could not be removed (possibly in use)" >&2
      fi
      ;;
    images)
      if ! podman image rm "$name"; then
        echo "SKIP: image $name could not be removed (possibly in use)" >&2
      fi
      ;;
    volumes)
      if ! podman volume rm "$name"; then
        echo "SKIP: volume $name could not be removed (possibly in use)" >&2
      fi
      ;;
  esac
done
