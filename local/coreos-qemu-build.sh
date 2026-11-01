#!/usr/bin/env bash
set -Eeuo pipefail

container="${1:?Nix-Alpine toolbox container required}"
workspaces="$(realpath "${2:?WORKSPACES required}")"
agni_checkout="${3:?Agni checkout required}"
agni_rev="${4:?Agni revision required}"
config_dir="$(realpath "${5:?Butane config directory required}")"
resources_dir="$(realpath "${6:?Butane resources directory required}")"
state="$(realpath -m "${7:?CoreOS state directory required}")"
reuse="${8:-1}"
config_name="${9:-fatline-bootstrap.bu}"
composition_name="${10:-fatline}"
toolbox_flake="${11:?Toolbox flake path required}"
state_root="$(realpath -m "${12:?CoreOS state root required}")"

to_workspace_path() {
  local path="$(realpath "$1")"
  [[ "$path/" == "$workspaces/"* ]] || { echo "Path escapes WORKSPACES: $path" >&2; exit 2; }
  printf '/workspaces/%s' "${path#"$workspaces"/}"
}
[[ "$state/" == "$state_root/"* ]] || { echo "CoreOS state must be beneath $state_root" >&2; exit 2; }
config_container="$(to_workspace_path "$config_dir")"
resources_container="$(to_workspace_path "$resources_dir")"
state_container="/run/nix-alpine/coreos-qemu/${state#"$state_root"/}"
test -d "$workspaces/$agni_checkout" || { echo "Missing Agni checkout: $workspaces/$agni_checkout" >&2; exit 2; }
mkdir -p "$state"
probe="$(mktemp "$state/.toolbox-mount-check.XXXXXXXX")"
trap 'rm -f -- "$probe"' EXIT
if ! podman exec "$container" test -f "$state_container/${probe##*/}"; then
  echo "CoreOS state is not visible through the toolbox mount; run make bootstrap to install the state mount" >&2
  exit 2
fi
rm -f -- "$probe"
trap - EXIT

podman_args=(podman exec)
[[ -z "${COREOS_TEST_SSH_PUBLIC_KEY:-}" ]] || podman_args+=(-e "COREOS_TEST_SSH_PUBLIC_KEY=$COREOS_TEST_SSH_PUBLIC_KEY")
exec "${podman_args[@]}" "$container" nix run --no-write-lock-file "$toolbox_flake#coreos-qemu-build" -- \
  /workspaces "$agni_checkout" "$agni_rev" "$config_container" "$resources_container" \
  "$state_container" "$reuse" "$config_name" "$composition_name"
