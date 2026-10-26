#!/usr/bin/env bash
# Scoped cleanup of disposable Fatline composition resources only.
set -Eeuo pipefail
mode=${1:-inspect}
dry_run=${2:-1}
[[ "$dry_run" == 0 || "$dry_run" == 1 ]] || { echo "DRY_RUN must be 0 or 1" >&2; exit 2; }
case "$mode" in inspect|networks|containers|all) ;; *) echo "MODE must be inspect, networks, containers or all" >&2; exit 2;; esac
prefix='fatline-composition-'
containers=()
networks=()
while IFS= read -r name; do
  [[ "$name" == "$prefix"* ]] && containers+=("$name")
done < <(podman ps -a --format '{{.Names}}')
while IFS= read -r name; do
  [[ "$name" == "$prefix"* ]] && networks+=("$name")
done < <(podman network ls --format '{{.Name}}')
printf 'Disposable containers (%d):\n' "${#containers[@]}"
printf '  %s\n' "${containers[@]}"
printf 'Disposable networks (%d):\n' "${#networks[@]}"
printf '  %s\n' "${networks[@]}"
[[ "$mode" != inspect ]] || exit 0
if [[ "$dry_run" == 1 ]]; then
  echo 'DRY_RUN=1: no changes; use DRY_RUN=0 to remove selected resources.'
  exit 0
fi
# Refuse to disrupt active qualification runs. Stopped containers may be
# removed explicitly; networks are only removed when Podman considers them unused.
if [[ "$mode" == containers || "$mode" == all ]]; then
  for name in "${containers[@]}"; do
    state=$(podman inspect --format '{{.State.Running}}' "$name")
    if [[ "$state" == true ]]; then
      echo "SKIP: running container $name" >&2
      continue
    fi
    podman rm -f --depend "$name"
  done
fi
if [[ "$mode" == networks || "$mode" == all ]]; then
  for name in "${networks[@]}"; do
    # Never force-remove a network with attached containers.
    if ! podman network rm "$name"; then
      echo "SKIP: network $name could not be removed (possibly in use)" >&2
    fi
  done
fi
