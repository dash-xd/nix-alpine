#!/usr/bin/env bash
set -Eeuo pipefail
trap 'echo "ERROR: line $LINENO: $BASH_COMMAND" >&2' ERR

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd -- "$SCRIPT_DIR/.." && pwd)"
NIX_ALPINE_ROOT="${NIX_ALPINE_ROOT:-$REPO}"
NIX_ALPINE_HOME="${NIX_ALPINE_HOME:-$HOME/workspace/nix}"
NIX_ALPINE_STATE_ROOT="${NIX_ALPINE_STATE_ROOT:-$NIX_ALPINE_HOME/.state/nix-alpine}"
WORKSPACES="${WORKSPACES:-$NIX_ALPINE_HOME}"
SCOPE="${SCOPE:-dev}"
NIX_ALPINE_CHECKOUT="${NIX_ALPINE_CHECKOUT:-$(basename "$NIX_ALPINE_ROOT" | tr '[:upper:]' '[:lower:]' | sed -E 's/[^a-z0-9_-]+/-/g')}"
NIX_ALPINE_SOURCE_REV="${NIX_ALPINE_SOURCE_REV:-$(git -C "$NIX_ALPINE_ROOT" rev-parse --short=12 HEAD 2>/dev/null || echo unknown)}"
NIX_ALPINE_SOURCE_DATE="${NIX_ALPINE_SOURCE_DATE:-$(git -C "$NIX_ALPINE_ROOT" log -1 --format=%cs 2>/dev/null | tr '-' '.')}"
NIX_ALPINE_VERSION="${NIX_ALPINE_VERSION:-${NIX_ALPINE_SOURCE_DATE:-unversioned}-${NIX_ALPINE_SOURCE_REV}}"
WORKSPACE_KEY="${WORKSPACE_KEY:-$(basename "$WORKSPACES" | tr '[:upper:]' '[:lower:]' | sed -E 's/[^a-z0-9_-]+/-/g')}"
CONTAINER="${CONTAINER:-nix-alpine-$NIX_ALPINE_VERSION-$WORKSPACE_KEY-$NIX_ALPINE_CHECKOUT-$SCOPE}"
SERVICE="${SERVICE:-$CONTAINER.service}"
VOLUME="${VOLUME:-nix-alpine-$SCOPE-store}"
IMAGE="${IMAGE:-localhost/nix-alpine:$NIX_ALPINE_VERSION}"
RELEASE_STATE="${RELEASE_STATE:-$NIX_ALPINE_STATE_ROOT/releases}"
STATE_ROOT="${STATE_ROOT:-$NIX_ALPINE_STATE_ROOT/coreos-qemu}"
QUADLET_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/containers/systemd"

die() { echo "ERROR: $*" >&2; exit 1; }
log() { printf '\n==> %s\n' "$*"; }
for cmd in git podman systemctl realpath; do command -v "$cmd" >/dev/null || die "Missing: $cmd"; done
[[ "$SCOPE" =~ ^[a-zA-Z0-9][a-zA-Z0-9_-]*$ ]] || die "Invalid scope"
[[ "$NIX_ALPINE_VERSION" =~ ^[A-Za-z0-9_][A-Za-z0-9_.-]{0,127}$ ]] || die "Invalid Nix-Alpine source version"
[[ "$CONTAINER" =~ ^[a-zA-Z0-9][a-zA-Z0-9_.-]*$ ]] || die "Invalid container name"
[[ "$VOLUME" =~ ^[a-zA-Z0-9][a-zA-Z0-9_.-]*$ ]] || die "Invalid Nix store volume name"
for f in nix-alpine-store.volume nix-alpine.container; do test -f "$SCRIPT_DIR/quadlet/$f" || die "Missing template $f"; done

mkdir -p "$WORKSPACES" "$QUADLET_DIR" "$RELEASE_STATE" "$STATE_ROOT"
RELEASE_STATE="$(realpath "$RELEASE_STATE")"
STATE_ROOT="$(realpath "$STATE_ROOT")"
WORKSPACES="$(realpath "$WORKSPACES")"
[[ "$WORKSPACES" != *[[:space:]]* ]] || die "Workspace path cannot contain whitespace"
[[ -f "$REPO/Dockerfile" ]] || die "Missing Dockerfile in $REPO"
log "Building toolbox image"
podman build \
  --label "org.opencontainers.image.version=$NIX_ALPINE_VERSION" \
  --label "org.opencontainers.image.revision=$NIX_ALPINE_SOURCE_REV" \
  --label "io.nix-alpine.workspace=$WORKSPACE_KEY" \
  -t "$IMAGE" "$REPO"

render() {
  local content
  content="$(<"$1")"
  content="${content//@SCOPE@/$SCOPE}"
  content="${content//@VERSION@/$NIX_ALPINE_VERSION}"
  content="${content//@SOURCE_REV@/$NIX_ALPINE_SOURCE_REV}"
  content="${content//@WORKSPACE_KEY@/$WORKSPACE_KEY}"
  content="${content//@IMAGE@/$IMAGE}"
  content="${content//@CONTAINER@/$CONTAINER}"
  content="${content//@VOLUME@/$VOLUME}"
  content="${content//@WORKSPACES@/$WORKSPACES}"
  content="${content//@RELEASE_STATE@/$RELEASE_STATE}"
  content="${content//@STATE_ROOT@/$STATE_ROOT}"
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
Source: $NIX_ALPINE_VERSION ($NIX_ALPINE_SOURCE_REV)
Image: $IMAGE
Ready: $CONTAINER
Workspace: $WORKSPACES (container: /workspaces)
Store: $VOLUME
Shell: podman exec -it $CONTAINER bash
EOF
