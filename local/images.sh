#!/usr/bin/env bash
set -euo pipefail
action="${1:-inspect}"
container="${2:-nix-alpine-dev}"
image="${3:-localhost/nix-toolbox:latest}"

echo "Container: $container"
if podman container exists "$container"; then
  podman inspect "$container" --format 'Status: {{.State.Status}} | image ID: {{.Image}} | configured image: {{.Config.Image}}'
  active="$(podman inspect "$container" --format '{{.Image}}')"
else
  active=""
  echo "Container not found"
fi

echo
echo "Nix toolbox images (including untagged images):"
podman images --all --no-trunc --format '{{.ID}} {{.Repository}}:{{.Tag}} {{.CreatedAt}} {{.Size}}' | while IFS= read -r line; do
  case "$line" in
    *nix-toolbox*|*'<none>:<none>'*) printf '%s\n' "$line" ;;
  esac
done
echo
echo "Configured image:"
podman image inspect "$image" --format 'ID: {{.Id}} | created: {{.Created}} | size: {{.Size}} bytes' 2>/dev/null || echo "Not present: $image"

if [[ "$action" == "prune" ]]; then
  echo
  echo "Removing dangling (untagged, unreferenced) images only."
  podman image prune --force
  echo "Active container image was: ${active:-none}"
elif [[ "$action" != "inspect" ]]; then
  echo "Usage: images.sh {inspect|prune} [container] [image]" >&2
  exit 2
fi
