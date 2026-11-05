#!/usr/bin/env bash
set -Eeuo pipefail

container="$1"
workspaces="$(realpath "$2")"
input_checkout="$3"
input_rev="$4"
build_flake="$5"
config_dir="$(realpath "$6")"
resources_dir="$(realpath "$7")"
state="$(realpath -m "$8")"
reuse="$9"
config_name="${10}"
composition_name="${11}"
toolbox_flake="${12}"
state_root="$(realpath -m "${13}")"

valid_relative() {
  local value="$1"
  [[ "$value" =~ ^[A-Za-z0-9_.-]+(/[A-Za-z0-9_.-]+)*$ ]] &&
    [[ "/$value/" != *"/../"* && "/$value/" != *"/.git/"* ]]
}
valid_relative "$input_checkout" || { echo "Invalid input checkout path" >&2; exit 2; }
valid_relative "$build_flake" || { echo "Invalid build flake path" >&2; exit 2; }
input_root="$(realpath "$workspaces/$input_checkout")"
[[ "$(realpath --relative-to="$workspaces" "$input_root")" == "$input_checkout" ]] || { echo "Input checkout escapes WORKSPACES" >&2; exit 2; }
[[ -f "$input_root/$build_flake/flake.nix" ]] || { echo "Build flake not found: $input_checkout/$build_flake" >&2; exit 2; }
[[ "$(git -C "$input_root" rev-parse HEAD)" == "$input_rev" ]] || { echo "Input checkout does not match pinned revision $input_rev" >&2; exit 1; }
for path in "$config_dir" "$resources_dir"; do
  [[ "$path/" == "$workspaces/"* ]] || { echo "Build input escapes WORKSPACES: $path" >&2; exit 2; }
done
[[ "$state/" == "$state_root/"* ]] || { echo "CoreOS state must be beneath $state_root" >&2; exit 2; }
[[ "$input_rev" =~ ^[0-9a-f]{40}$ ]] || { echo "Invalid pinned input revision" >&2; exit 2; }
[[ "$config_name" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*\.bu$ ]] || { echo "Invalid Butane config name" >&2; exit 2; }
[[ "$composition_name" =~ ^[a-z_][a-z0-9_-]{0,18}$ ]] || { echo "Invalid composition account prefix" >&2; exit 2; }
[[ "$reuse" == 0 || "$reuse" == 1 ]] || { echo "COREOS_REUSE must be 0 or 1" >&2; exit 2; }

config_container="/workspaces/$(realpath --relative-to="$workspaces" "$config_dir")"
resources_container="/workspaces/$(realpath --relative-to="$workspaces" "$resources_dir")"
state_relative="$(realpath --relative-to="$state_root" "$state")"
state_container="/run/nix-alpine/coreos-qemu/$state_relative"
flake_container="/workspaces/$input_checkout/$build_flake"

mkdir -p "$state"
probe="$(mktemp "$state/.toolbox-mount-check.XXXXXXXX")"
trap 'rm -f -- "$probe"' EXIT
if ! podman exec "$container" test -f "$state_container/$(basename "$probe")"; then
  echo "CoreOS state is not visible through the toolbox mount; run make bootstrap to install the state mount" >&2
  exit 2
fi
rm -f -- "$probe"
trap - EXIT

podman_args=(podman exec)
if [[ -n "$COREOS_TEST_SSH_PUBLIC_KEY" ]]; then podman_args+=(-e "COREOS_TEST_SSH_PUBLIC_KEY=$COREOS_TEST_SSH_PUBLIC_KEY"); fi
exec "${podman_args[@]}" "$container" nix run --no-write-lock-file "$toolbox_flake#coreos-qemu-build" -- \
  /workspaces "$input_checkout" "$input_rev" "$build_flake" \
  "$config_container" "$resources_container" "$state_container" "$reuse" \
  "$config_name" "$composition_name"
