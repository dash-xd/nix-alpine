#!/usr/bin/env bash
set -Eeuo pipefail
trap 'echo "ERROR: line $LINENO: $BASH_COMMAND" >&2' ERR
SCOPE="${SCOPE:-dev}"
IMAGE="${IMAGE:-localhost/nix.xd:latest}"
[[ "$SCOPE" =~ ^[a-zA-Z0-9][a-zA-Z0-9_-]*$ ]] || { echo "Invalid scope" >&2; exit 2; }
CONTAINER="nix-alpine-$SCOPE"
VOLUME="$CONTAINER-store"
SERVICE="$CONTAINER.service"
QUADLET_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/containers/systemd"

echo "Removing scope: $SCOPE"
systemctl --user stop "$SERVICE" 2>/dev/null || true
rm -f -- "$QUADLET_DIR/$CONTAINER.container" "$QUADLET_DIR/$VOLUME.volume"
systemctl --user daemon-reload
podman rm -f "$CONTAINER" 2>/dev/null || true
podman volume rm "$VOLUME" 2>/dev/null || true
# Avoid removing an image that might be used by another scope.
if ! podman ps -a --format '{{.Image}}' | grep -Fxq "$IMAGE"; then
  podman rmi "$IMAGE" 2>/dev/null || true
else
  echo "Keeping image $IMAGE: still referenced by a container"
fi
systemctl --user reset-failed
echo "Removed Nix-Alpine scope $SCOPE; source files and other workspaces preserved."
