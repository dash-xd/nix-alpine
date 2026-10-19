#!/usr/bin/env bash
set -euo pipefail
action="${1:-inspect}"
container="${2:-nix-alpine-dev}"
image="${3:-localhost/nix-toolbox:latest}"

echo "Nix-Alpine container: $container"
if podman container exists "$container"; then
  podman inspect "$container" --format 'Status: {{.State.Status}} | running image ID: {{.Image}} | configured tag: {{.Config.Image}}'
  active="$(podman inspect "$container" --format '{{.Image}}')"
else
  active=""
  echo "Container not found"
fi

echo
echo "Current tagged toolbox image:"
if podman image exists "$image"; then
  tagged="$(podman image inspect "$image" --format '{{.Id}}')"
  podman image inspect "$image" --format 'Image ID: {{.Id}} | created: {{.Created}} | virtual size: {{.Size}} bytes'
  if [[ -n "$active" && "$active" == "$tagged" ]]; then
    echo "MATCH: the container uses the currently tagged image"
  elif [[ -n "$active" ]]; then
    echo "MISMATCH: the container is using a different image; consider make refresh"
  fi
else
  echo "Not found: $image"
fi

echo
echo "Normal image inventory (intermediate build images excluded):"
podman images --format '{{.Repository}}:{{.Tag}}  {{.ID}}  {{.CreatedAt}}  {{.Size}}'

if [[ "$action" == "prune" ]]; then
  echo
  echo "Removing dangling images not referenced by containers:"
  podman image prune --force
elif [[ "$action" != "inspect" ]]; then
  echo "Usage: images.sh {inspect|prune} [container] [image]" >&2
  exit 2
fi
