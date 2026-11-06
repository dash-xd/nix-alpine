#!/usr/bin/env bash
set -Eeuo pipefail
trap 'echo "ERROR: line $LINENO: $BASH_COMMAND" >&2' ERR

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd -- "$SCRIPT_DIR/.." && pwd)"
NIX_ALPINE_ROOT="${NIX_ALPINE_ROOT:-$REPO}"
NIX_XD_ROOT="${NIX_XD_ROOT:-$(realpath -m "$NIX_ALPINE_ROOT/../..")}"
NIX_ALPINE_WORKSPACE_ROOT="${NIX_ALPINE_WORKSPACE_ROOT:-$NIX_XD_ROOT/nix-alpine}"
NIX_ALPINE_HOME="${NIX_ALPINE_HOME:-$HOME}"
NIX_ALPINE_STATE_ROOT="${NIX_ALPINE_STATE_ROOT:-${XDG_STATE_HOME:-$HOME/.local/state}/nix.xd}"
WORKSPACES="${WORKSPACES:-$NIX_XD_ROOT}"
SCOPE="${SCOPE:-dev}"
NIX_ALPINE_CHECKOUT_PATH="${NIX_ALPINE_CHECKOUT_PATH:-$(realpath --relative-to="$NIX_XD_ROOT" "$NIX_ALPINE_ROOT")}"
NIX_ALPINE_CHECKOUT="${NIX_ALPINE_CHECKOUT:-$(printf '%s' "$NIX_ALPINE_CHECKOUT_PATH" | tr '/' '-' | tr '[:upper:]' '[:lower:]' | sed -E 's/[^a-z0-9_-]+/-/g')}"
NIX_ALPINE_SOURCE_REV="${NIX_ALPINE_SOURCE_REV:-$(git -C "$NIX_ALPINE_ROOT" rev-parse --short=12 HEAD 2>/dev/null || echo unknown)}"
NIX_ALPINE_SOURCE_DATE="${NIX_ALPINE_SOURCE_DATE:-$(git -C "$NIX_ALPINE_ROOT" log -1 --format=%cs 2>/dev/null | tr '-' '.')}"
NIX_ALPINE_VERSION="${NIX_ALPINE_VERSION:-${NIX_ALPINE_SOURCE_DATE:-unversioned}-${NIX_ALPINE_SOURCE_REV}}"
WORKSPACE_KEY="${WORKSPACE_KEY:-$(basename "$WORKSPACES" | tr '[:upper:]' '[:lower:]' | sed -E 's/[^a-z0-9_-]+/-/g')}"
CONTAINER="${CONTAINER:-nix.xd-$NIX_ALPINE_VERSION-$WORKSPACE_KEY-$NIX_ALPINE_CHECKOUT-$SCOPE}"
SERVICE="${SERVICE:-$CONTAINER.service}"
VOLUME="${VOLUME:-nix.xd-store-$WORKSPACE_KEY-$SCOPE}"
IMAGE="${IMAGE:-localhost/nix.xd:$NIX_ALPINE_VERSION}"
RELEASE_STATE="${RELEASE_STATE:-$NIX_ALPINE_STATE_ROOT/releases}"
STATE_ROOT="${STATE_ROOT:-$NIX_ALPINE_STATE_ROOT/coreos-qemu}"
QUADLET_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/containers/systemd"
die() { echo "ERROR: $*" >&2; exit 1; }
WORKSPACE_ACCESS="${NIX_ALPINE_WORKSPACE_ACCESS:-rw}"
AGE_VOLUME="${NIX_ALPINE_AGE_VOLUME:-}"
AGE_ACCESS="${NIX_ALPINE_AGE_ACCESS:-ro}"
[[ "$WORKSPACE_ACCESS" == rw || "$WORKSPACE_ACCESS" == ro ]] || die "Invalid workspace access"
AGE_VOLUME_LINE=""
AGE_ENV_LINE=""
if [[ -n "$AGE_VOLUME" ]]; then
  [[ "$AGE_VOLUME" =~ ^[a-z][a-z0-9-]{0,62}$ ]] || die "Invalid age volume name"
  [[ "$AGE_ACCESS" == ro || "$AGE_ACCESS" == rw ]] || die "Invalid age volume access"
  AGE_VOLUME_LINE="Volume=$AGE_VOLUME:/run/secrets/age:$AGE_ACCESS"
  AGE_ENV_LINE="Environment=SOPS_AGE_KEY_FILE=/run/secrets/age/keys.txt"
fi

if [[ "$WORKSPACE_ACCESS" == rw ]]; then
  GO_MOD_CACHE=/workspaces/.cache/go/mod
  GO_BUILD_CACHE=/workspaces/.cache/go/build
  XDG_CACHE_DIR=/workspaces/.cache/xdg
else
  GO_MOD_CACHE=/home/nixuser/go/pkg/mod
  GO_BUILD_CACHE=/home/nixuser/.cache/go-build
  XDG_CACHE_DIR=/home/nixuser/.cache
fi


log() { printf '\n==> %s\n' "$*"; }
for cmd in git podman systemctl realpath; do command -v "$cmd" >/dev/null || die "Missing: $cmd"; done
[[ "$SCOPE" =~ ^[a-zA-Z0-9][a-zA-Z0-9_-]*$ ]] || die "Invalid scope"
NIX_ALPINE_ROOT=$(realpath "$NIX_ALPINE_ROOT")
WORKSPACES=$(realpath -m "$WORKSPACES")
NIX_ALPINE_WORKSPACE_ROOT=$(realpath -m "$NIX_ALPINE_WORKSPACE_ROOT")
[[ "$NIX_ALPINE_ROOT" == "$NIX_ALPINE_WORKSPACE_ROOT/"* ]] || die "Nix-Alpine checkout must be under $NIX_ALPINE_WORKSPACE_ROOT"
[[ "$(realpath -m "$NIX_XD_ROOT/$NIX_ALPINE_CHECKOUT_PATH")" == "$NIX_ALPINE_ROOT" ]] || die "Nix-Alpine checkout path must be relative to the common nix.xd root"
[[ "$NIX_ALPINE_CHECKOUT_PATH" =~ ^[A-Za-z0-9_.-]+(/[A-Za-z0-9_.-]+)*$ && "$NIX_ALPINE_CHECKOUT_PATH" != *//* ]] || die "Invalid Nix-Alpine checkout path"
IFS=/ read -r -a checkout_parts <<< "$NIX_ALPINE_CHECKOUT_PATH"
for checkout_part in "${checkout_parts[@]}"; do
  [[ "$checkout_part" != "." && "$checkout_part" != ".." && "$checkout_part" != ".git" ]] || die "Invalid Nix-Alpine checkout path"
done
[[ "$WORKSPACES" == "$(realpath -m "$NIX_XD_ROOT")" ]] || die "WORKSPACES must be the common nix.xd root ($NIX_XD_ROOT)"
[[ "$NIX_ALPINE_VERSION" =~ ^[A-Za-z0-9_][A-Za-z0-9_.-]{0,127}$ ]] || die "Invalid Nix-Alpine source version"
[[ "$CONTAINER" =~ ^[a-zA-Z0-9][a-zA-Z0-9_.-]*$ ]] || die "Invalid container name"
[[ "$VOLUME" =~ ^[a-zA-Z0-9][a-zA-Z0-9_.-]*$ ]] || die "Invalid Nix store volume name"
for f in nix-alpine-store.volume nix-alpine.container; do test -f "$SCRIPT_DIR/quadlet/$f" || die "Missing template $f"; done
test -f "$SCRIPT_DIR/seed-store-volume.sh" || die "Missing shared-store initializer"
test -f "$SCRIPT_DIR/prepare-store-volume.sh" || die "Missing shared-store ownership initializer"

mkdir -p "$WORKSPACES" "$QUADLET_DIR" "$RELEASE_STATE" "$STATE_ROOT"
if [[ "$WORKSPACE_ACCESS" == rw ]]; then
  mkdir -p "$WORKSPACES/.cache/go/mod" "$WORKSPACES/.cache/go/build" "$WORKSPACES/.cache/xdg"
fi
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
  content="${content//@WORKSPACE_ACCESS@/$WORKSPACE_ACCESS}"
  content="${content//@GO_MOD_CACHE@/$GO_MOD_CACHE}"
  content="${content//@GO_BUILD_CACHE@/$GO_BUILD_CACHE}"
  content="${content//@XDG_CACHE_DIR@/$XDG_CACHE_DIR}"
  content="${content//@AGE_VOLUME_LINE@/$AGE_VOLUME_LINE}"
  content="${content//@AGE_ENV_LINE@/$AGE_ENV_LINE}"
  content="${content//@RELEASE_STATE@/$RELEASE_STATE}"
  content="${content//@STATE_ROOT@/$STATE_ROOT}"
  printf '%s\n' "$content" > "$2"
}
if [[ -n "$AGE_VOLUME" ]]; then
  if [[ "$AGE_ACCESS" == rw ]]; then
    podman volume exists "$AGE_VOLUME" || podman volume create "$AGE_VOLUME" >/dev/null
    # The scoped bootstrap runner prepares its own volume once, without
    # touching existing identities or the unrelated Nix store.
    podman run --rm --user 0 -v "$AGE_VOLUME:/run/secrets/age:rw" "$IMAGE" \
      chown 1000:1000 /run/secrets/age
  else
    podman volume exists "$AGE_VOLUME" || die "Reader requested a nonexistent age identity volume"
  fi
fi
log "Installing Quadlets"
render "$SCRIPT_DIR/quadlet/nix-alpine-store.volume" "$QUADLET_DIR/$VOLUME.volume"
render "$SCRIPT_DIR/quadlet/nix-alpine.container" "$QUADLET_DIR/$CONTAINER.container"
systemctl --user daemon-reload
systemctl --user start "$VOLUME-volume.service"
log "Preparing shared store root for the toolbox identity"
bash "$SCRIPT_DIR/prepare-store-volume.sh" "$IMAGE" "$VOLUME"
log "Merging the image Nix profile into shared store $VOLUME"
bash "$SCRIPT_DIR/seed-store-volume.sh" "$IMAGE" "$VOLUME"
systemctl --user restart "$SERVICE"
log "Trusting mounted workspace Git checkouts inside the toolbox"
podman exec "$CONTAINER" bash "/workspaces/$NIX_ALPINE_CHECKOUT_PATH/local/trust-workspace-git.sh" /workspaces
log "Verifying Nix"
podman exec "$CONTAINER" nix --version
if [[ -n "$AGE_VOLUME" ]]; then
  if [[ "$AGE_ACCESS" == rw ]]; then
    log "Ensuring bootstrap-owned age identity (no private-key output)"
    podman exec "$CONTAINER" nix develop \
      /workspaces/$NIX_ALPINE_CHECKOUT_PATH/toolbox#security -c \
      bash "/workspaces/$NIX_ALPINE_CHECKOUT_PATH/local/ensure-age-identity.sh"
  else
    podman exec "$CONTAINER" test -r /run/secrets/age/keys.txt ||
      die "Age identity not available to reader scope"
  fi
fi
cat <<EOF
Source: $NIX_ALPINE_VERSION ($NIX_ALPINE_SOURCE_REV)
Image: $IMAGE
Ready: $CONTAINER
Workspace: $WORKSPACES (container: /workspaces)
Store: $VOLUME
Shell: podman exec -it $CONTAINER bash
EOF
