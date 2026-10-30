#!/usr/bin/env bash
set -Eeuo pipefail

container="${1:?Podman toolbox container is required}"
workspaces="${2:?WORKSPACES is required}"
agni_checkout="${3:?Agni checkout name is required}"
agni_rev="${4:?Agni revision is required}"
config_input="${5:?Butane config directory is required}"
resources_input="${6:?Butane resources directory is required}"
state="${7:?CoreOS state directory is required}"
reuse="${8:-1}"

workspace_root="$(realpath "$workspaces")"
agni_dir="$(realpath "$workspaces/$agni_checkout")"
config_dir="$(realpath "$config_input")"
resources_dir="$(realpath "$resources_input")"
state="$(realpath -m "$state")"

for pair in "Agni checkout:$agni_dir" "Butane config:$config_dir" "Butane resources:$resources_dir"; do
  path="${pair#*:}"
  [[ "$path/" == "$workspace_root/"* ]] || {
    echo "${pair%%:*} must remain under WORKSPACES ($workspace_root): $path" >&2
    exit 2
  }
done
test -f "$config_dir/fatline-bootstrap.bu" || {
  echo "Missing Butane config: $config_dir/fatline-bootstrap.bu" >&2
  exit 2
}
test -d "$resources_dir" || {
  echo "Missing Butane resources: $resources_dir" >&2
  exit 2
}
[[ "$agni_rev" =~ ^[0-9a-f]{40}$ ]] || {
  echo "Invalid pinned Agni revision: $agni_rev" >&2
  exit 2
}
[[ "$reuse" == 0 || "$reuse" == 1 ]] || {
  echo "COREOS_REUSE must be 0 or 1" >&2
  exit 2
}

config_rel="$(realpath --relative-to "$workspace_root" "$config_dir")"
resources_rel="$(realpath --relative-to "$workspace_root" "$resources_dir")"
mkdir -p "$state"

podman exec "$container" test -f "/workspaces/$config_rel/fatline-bootstrap.bu" || {
  echo "Butane config is not visible inside toolbox at /workspaces/$config_rel" >&2
  exit 2
}
podman exec "$container" test -d "/workspaces/$resources_rel" || {
  echo "Butane resources are not visible inside toolbox at /workspaces/$resources_rel" >&2
  exit 2
}

build_key="$(bash "$(dirname "$0")/coreos-qemu-input-key.sh" "$agni_dir" "$config_dir" "$resources_dir" "$agni_rev")"
if [[ "$reuse" == 1 && -f "$state/build-key" && -f "$state/artifacts.sha256" ]] &&
  [[ "$(cat "$state/build-key")" == "$build_key" ]] &&
  (cd "$state" && sha256sum --check artifacts.sha256); then
  echo "PASS: reused checksum-verified CoreOS QEMU artifact bundle"
  exit 0
fi

podman exec "$container" git config --global --replace-all safe.directory "/workspaces/$agni_checkout"
build_log="$state/nix-build.log"
: > "$build_log"
podman_exec=(podman exec)
if [[ -n "${NIX_CONFIG:-}" ]]; then
  podman_exec+=(-e NIX_CONFIG)
fi

if ! output="$("${podman_exec[@]}" \
  -e "COREOS_CONFIG_DIR=/workspaces/$config_rel" \
  -e "COREOS_RESOURCES_DIR=/workspaces/$resources_rel" \
  "$container" nix build -L --impure --no-write-lock-file --no-link --print-out-paths \
  "/workspaces/$agni_checkout/qemu/coreos-live/local#bootstrap" 2>"$build_log")"; then
  cat "$build_log" >&2
  printf '%s\n' "$output" >&2
  exit 1
fi
cat "$build_log"

if [[ ! "$output" =~ ^/nix/store/[a-z0-9]{32}-fatline-coreos-qemu-bootstrap-[^[:space:]]+$ ]]; then
  echo "Unexpected Nix artifact path output: $output" >&2
  exit 1
fi

podman cp "$container:$output/." "$state/"
test -s "$state/base.qcow2" && test -s "$state/config.ign" || {
  echo "Nix-Alpine QEMU artifact copy was incomplete" >&2
  exit 1
}
(cd "$state" && sha256sum base.qcow2 config.ign > artifacts.sha256)
printf '%s\n' "$build_key" > "$state/build-key"
echo "PASS: pinned FCOS disk and workspace-composed Ignition artifact staged at $state"
