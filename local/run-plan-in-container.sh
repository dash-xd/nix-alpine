#!/usr/bin/env bash
set -Eeuo pipefail

[[ $# == 11 ]] || {
  echo "usage: $0 IMAGE STORE_VOLUME WORKSPACES NIX_ALPINE_ROOT PLAN_CHECKOUT PLAN_FILE PLAN_RUNNER GATE SCOPE ARTIFACT_MANIFEST RETAIN" >&2
  exit 2
}
image=$1 volume=$2 workspaces=$3 nix_alpine_root=$4 checkout=$5 plan_file=$6 runner=$7 gate=$8 scope=$9
artifact_manifest=${10:-}
retain=${11:-0}
[[ "$retain" == 0 || "$retain" == 1 ]] || { echo "RETAIN must be 0 or 1" >&2; exit 2; }
umask 077

die() { echo "ERROR: $*" >&2; exit 1; }
for cmd in podman systemctl realpath; do command -v "$cmd" >/dev/null || die "Missing host command: $cmd"; done
[[ "$scope" =~ ^[A-Za-z0-9][A-Za-z0-9_.-]*$ ]] || die "Invalid runtime scope"
[[ "$checkout" =~ ^[A-Za-z0-9][A-Za-z0-9_.-]*$ ]] || die "PLAN_CHECKOUT must be a simple workspace directory name"
[[ "$plan_file" != /* && "$plan_file" != *..* ]] || die "PLAN_FILE must be relative without traversal"
[[ "$runner" != /* && "$runner" != *..* ]] || die "PLAN_RUNNER must be relative without traversal"

workspaces=$(realpath "$workspaces")
nix_alpine_root=$(realpath "$nix_alpine_root")
nix_alpine_rel=$(realpath --relative-to="$workspaces" "$nix_alpine_root")
[[ "$nix_alpine_rel" != .. && "$nix_alpine_rel" != ../* ]] || die "Nix-Alpine must be inside WORKSPACES"
[[ -f "$workspaces/$checkout/$plan_file" ]] || die "Missing plan: $workspaces/$checkout/$plan_file"
[[ -f "$workspaces/$checkout/$runner" ]] || die "Missing plan runner: $workspaces/$checkout/$runner"
manifest_in_container=
if [[ -n "$artifact_manifest" ]]; then
  artifact_manifest=$(realpath "$artifact_manifest")
  manifest_rel=$(realpath --relative-to="$workspaces" "$artifact_manifest")
  [[ "$manifest_rel" != .. && "$manifest_rel" != ../* ]] || die "Artifact manifest must be inside WORKSPACES"
  [[ -s "$artifact_manifest" ]] || die "Artifact manifest is empty: $artifact_manifest"
  manifest_in_container=/run/plan-artifacts/manifest.tsv
fi

runtime_dir=${XDG_RUNTIME_DIR:-/run/user/$(id -u)}
config_home=${XDG_CONFIG_HOME:-$HOME/.config}
podman_socket="$runtime_dir/podman/podman.sock"
user_bus="$runtime_dir/bus"
systemd_user_dir="$config_home/systemd/user"
quadlet_dir="$config_home/containers/systemd"
mkdir -p "$systemd_user_dir" "$quadlet_dir"
systemctl --user start podman.socket
[[ -S "$podman_socket" ]] || die "Rootless Podman socket is unavailable: $podman_socket"
[[ -S "$user_bus" ]] || die "User D-Bus socket is unavailable: $user_bus"

task="nix-alpine-plan-${scope}-${BASHPID}"
plan_tmp="$workspaces/.state/nix-alpine/plan-tmp/$task"
cleanup() {
  local status=$?
  trap - EXIT INT TERM
  if podman container exists "$task"; then
    podman kill --signal KILL "$task" >/dev/null 2>&1 || true
    podman rm -f "$task" >/dev/null 2>&1 || true
  fi
  if [[ -d "$plan_tmp" ]]; then
    if ! find "$plan_tmp" -mindepth 1 -print -quit | grep -q .; then
      rmdir "$plan_tmp" 2>/dev/null || true
    elif (( status == 0 )); then
      rm -rf -- "$plan_tmp"
    else
      echo "Preserving failed plan scratch at $plan_tmp" >&2
    fi
  fi
  return "$status"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
mkdir -p "$(dirname "$plan_tmp")"
mkdir "$plan_tmp"
chmod 700 "$plan_tmp"

echo "Nix-Alpine runtime: $task"
echo "Host-visible plan scratch: $plan_tmp"
echo "Plan: $workspaces/$checkout/$plan_file (gate: $gate)"
# The host-identical alias lets Podman resolve bind sources created by the plan.
podman_args=(run --rm --name "$task" \
  --userns=keep-id:uid=1000,gid=1000 --network host --cap-drop ALL --security-opt no-new-privileges \
  --volume "$volume:/nix" \
  --volume "$workspaces:/workspaces:rw" \
  --volume "$workspaces:$workspaces:rw" \
  --volume "$podman_socket:/run/host-user/podman/podman.sock:rw" \
  --volume "$user_bus:/run/host-user/bus:rw" \
  --volume "$systemd_user_dir:/home/nixuser/.config/systemd/user:rw" \
  --volume "$quadlet_dir:/home/nixuser/.config/containers/systemd:rw" \
  --env DBUS_SESSION_BUS_ADDRESS=unix:path=/run/host-user/bus \
  --env CONTAINER_HOST=unix:///run/host-user/podman/podman.sock \
  --env WORKSPACES=/workspaces \
  --env NIX_ALPINE_HOST_WORKSPACES="$workspaces" \
  --env NIX_ALPINE_RETAIN="$retain" \
  --env TMPDIR="$plan_tmp" \
  --workdir "/workspaces/$checkout")
if [[ -n "$manifest_in_container" ]]; then
  podman_args+=(--volume "$artifact_manifest:$manifest_in_container:ro")
fi
if [[ -n "${NIX_CONFIG:-}" ]]; then podman_args+=(--env NIX_CONFIG); fi
podman_args+=("$image" bash -euc 'unset XDG_RUNTIME_DIR; chmod 700 "$TMPDIR"; bash "/workspaces/$1/local/trust-workspace-git.sh" /workspaces; shift; exec "$@"' -- "$nix_alpine_rel" \
  nix develop --no-write-lock-file "/workspaces/$nix_alpine_rel/toolbox#qualification" \
  --command bash -euc 'unset XDG_RUNTIME_DIR; systemctl --user show-environment >/dev/null || { echo "ERROR: host user systemd D-Bus is unavailable from Nix-Alpine runtime" >&2; exit 1; }; echo "PASS: host user systemd D-Bus reachable from Nix-Alpine runtime"; exec bash "$@"' -- "/workspaces/$checkout/$runner" \
  --plan "/workspaces/$checkout/$plan_file" --gate "$gate" \
  --workspaces /workspaces --toolbox "$task" \
  --nix-alpine-local "/workspaces/$nix_alpine_rel/local" \
  --scope "$scope" --agni-checkout "$checkout")
if [[ -n "$manifest_in_container" ]]; then
  podman_args+=(--artifact-manifest "$manifest_in_container")
fi
podman "${podman_args[@]}"
