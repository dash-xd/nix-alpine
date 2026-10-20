#!/usr/bin/env bash
set -Eeuo pipefail
trap 'echo "ERROR: line $LINENO: $BASH_COMMAND" >&2' ERR

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
WORKSPACES="${WORKSPACES:-$HOME/workspace/nix}"
SCOPE="${SCOPE:-dev}"
IMAGE="${IMAGE:-localhost/nix.xd:latest}"
REPO="$(cd -- "$SCRIPT_DIR/.." && pwd)"
QUADLET_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/containers/systemd"
CONTAINER="nix-alpine-$SCOPE"
VOLUME="$CONTAINER-store"
SERVICE="$CONTAINER.service"

die() { echo "ERROR: $*" >&2; exit 1; }
log() { printf '\n==> %s\n' "$*"; }
for cmd in git podman systemctl realpath; do command -v "$cmd" >/dev/null || die "Missing: $cmd"; done
[[ "$SCOPE" =~ ^[a-zA-Z0-9][a-zA-Z0-9_-]*$ ]] || die "Invalid scope"
for f in nix-alpine-store.volume nix-alpine.container; do test -f "$SCRIPT_DIR/quadlet/$f" || die "Missing template $f"; done

mkdir -p "$WORKSPACES" "$QUADLET_DIR"
WORKSPACES="$(realpath "$WORKSPACES")"
[[ "$WORKSPACES" != *[[:space:]]* ]] || die "Workspace path cannot contain whitespace"
[[ -f "$REPO/Dockerfile" ]] || die "Missing Dockerfile in $REPO"
log "Building toolbox image"
podman build -t "$IMAGE" "$REPO"

render() {
  local content
  content="$(<"$1")"
  content="${content//@SCOPE@/$SCOPE}"
  content="${content//@IMAGE@/$IMAGE}"
  content="${content//@CONTAINER@/$CONTAINER}"
  content="${content//@VOLUME@/$VOLUME}"
  content="${content//@WORKSPACES@/$WORKSPACES}"
  printf '%s\n' "$content" > "$2"
}
log "Installing Quadlets"
render "$SCRIPT_DIR/quadlet/nix-alpine-store.volume" "$QUADLET_DIR/$VOLUME.volume"
render "$SCRIPT_DIR/quadlet/nix-alpine.container" "$QUADLET_DIR/$CONTAINER.container"
systemctl --user daemon-reload
systemctl --user restart "$SERVICE"
log "Verifying Nix"
podman exec "$CONTAINER" nix --version
cat <<EOF
Ready: $CONTAINER
Workspace: $WORKSPACES (container: /workspaces)
Store: $VOLUME
Shell: podman exec -it $CONTAINER bash
EOF
