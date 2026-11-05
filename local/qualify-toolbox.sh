#!/usr/bin/env bash
set -Eeuo pipefail
trap 'echo "ERROR: line $LINENO: $BASH_COMMAND" >&2' ERR

CONTAINER="${1:?container required}"
SERVICE="${2:?service required}"
IMAGE="${3:?image required}"
VOLUME="${4:?Nix store volume required}"
WORKSPACES="${5:?workspace path required}"
FLAKE="${6:?flake path required}"
VERSION="${7:?source version required}"
SOURCE_REV="${8:?source revision required}"
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

fail() { echo "FAIL: $*" >&2; exit 1; }
for cmd in podman systemctl realpath id; do
  command -v "$cmd" >/dev/null || fail "missing host command: $cmd"
done

WORKSPACES="$(realpath "$WORKSPACES")"
systemctl --user start "$SERVICE"
systemctl --user is-active --quiet "$SERVICE" || fail "systemd service is not active: $SERVICE"

running="$(podman inspect "$CONTAINER" --format '{{.State.Running}}' 2>/dev/null || true)"
[[ "$running" == true ]] || fail "toolbox container is not running: $CONTAINER"
container_image="$(podman inspect "$CONTAINER" --format '{{.Config.Image}}')"
[[ "$container_image" == "$IMAGE" ]] || fail "container image mismatch: expected $IMAGE, got $container_image"
container_image_id="$(podman inspect "$CONTAINER" --format '{{.Image}}')"
image_id="$(podman image inspect "$IMAGE" --format '{{.Id}}')"
[[ "$container_image_id" == "$image_id" ]] || fail "container is not using the selected image ID"

nix_volume="$(podman inspect "$CONTAINER" --format '{{range .Mounts}}{{if eq .Destination "/nix"}}{{.Name}}{{end}}{{end}}')"
[[ "$nix_volume" == "$VOLUME" ]] || fail "expected Nix volume $VOLUME, found $nix_volume"
workspace_mount="$(podman inspect "$CONTAINER" --format '{{range .Mounts}}{{if eq .Destination "/workspaces"}}{{.Source}}{{end}}{{end}}')"
[[ "$(realpath "$workspace_mount")" == "$WORKSPACES" ]] || fail "workspace bind mount does not match $WORKSPACES"

nix_env=()
if [[ -n "${NIX_CONFIG:-}" ]]; then
  nix_env+=(--env NIX_CONFIG)
fi
nix_version="$(podman exec "${nix_env[@]}" "$CONTAINER" nix --version)"

printf 'PASS: systemd toolbox active: %s\n' "$SERVICE"
printf 'PASS: toolbox source %s (%s), image %s\n' "$VERSION" "$SOURCE_REV" "$image_id"
printf 'PASS: Nix executable: %s\n' "$nix_version"
podman exec "${nix_env[@]}" "$CONTAINER" nix flake show --no-write-lock-file "$FLAKE" >/dev/null
printf 'PASS: Nix flake evaluated: %s\n' "$FLAKE"

store_path="$(podman exec "${nix_env[@]}" "$CONTAINER" nix eval --raw --impure --expr 'builtins.toFile "nix-alpine-shared-store-smoke" "shared-store"')"
[[ "$store_path" == /nix/store/* ]] || fail "Nix returned an invalid shared-store path: $store_path"
podman exec "$CONTAINER" test -e "$store_path" || fail "primary toolbox cannot see its Nix store output"

peer="nix-store-peer-$RANDOM-$BASHPID"
podman run --rm --name "$peer" --userns=keep-id:uid=1000,gid=1000 --network=none \
  --volume "$VOLUME:/nix" --env "EXPECTED_STORE_PATH=$store_path" "${nix_env[@]}" \
  --entrypoint /bin/bash "$IMAGE" -c \
  'test -e "$EXPECTED_STORE_PATH" && command -v nix >/dev/null && nix path-info "$EXPECTED_STORE_PATH" >/dev/null'
printf 'PASS: a second rootless Podman container used the same Nix store volume (%s)\n' "$VOLUME"

probe="nix.xd-qualify-$RANDOM-$BASHPID"
podman volume create --opt "o=uid=$(id -u),gid=$(id -g)" "$probe" >/dev/null
cleanup_probe() { podman volume rm "$probe" >/dev/null 2>&1 || true; }
trap cleanup_probe EXIT
bash "$SCRIPT_DIR/seed-store-volume.sh" "$IMAGE" "$probe"

probe_version="$(podman run --rm --network=none --userns=keep-id:uid=1000,gid=1000 \
  --volume "$probe:/nix" "${nix_env[@]}" "$IMAGE" nix --version)"
[[ "$probe_version" == "$nix_version" ]] || fail "fresh-volume Nix version mismatch: expected $nix_version, got $probe_version"
fresh_path="$(podman run --rm --network=none --userns=keep-id:uid=1000,gid=1000 \
  --volume "$probe:/nix" "${nix_env[@]}" "$IMAGE" nix eval --raw --impure \
  --expr 'builtins.toFile "nix-alpine-fresh-store-smoke" "fresh-store-shared"')"
[[ "$fresh_path" == /nix/store/* ]] || fail "fresh volume returned an invalid store path: $fresh_path"
podman run --rm --network=none --userns=keep-id:uid=1000,gid=1000 \
  --volume "$probe:/nix" --env "EXPECTED_STORE_PATH=$fresh_path" "${nix_env[@]}" \
  --entrypoint /bin/bash "$IMAGE" -c \
  'test -e "$EXPECTED_STORE_PATH" && command -v nix >/dev/null && nix path-info "$EXPECTED_STORE_PATH" >/dev/null'
printf 'PASS: empty Nix store volume initialized and shared by a second rootless container\n'
podman volume rm "$probe" >/dev/null
trap - EXIT
printf 'PASS: toolbox qualification completed\n'
