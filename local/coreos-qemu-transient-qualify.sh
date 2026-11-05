#!/usr/bin/env bash
set -Eeuo pipefail

make_cmd="$1"
container="$2"
workspaces="$3"
input_checkout="$4"
input_rev="$5"
build_flake="$6"
build_target="$7"
runner_flake="$8"
runner_target="$9"
state="${10}"
unit="${11}"
timeout="${12}"
ram_mb="${13}"
cpus="${14}"
accel="${15}"
qemu_image="${16}"
display="${17}"
web_port="${18}"
hold="${19}"
ssh_port="${20}"
composition="${21}"
config_dir="${22}"
resources_dir="${23}"
config_name="${24}"
expected_marker="${25}"

script_dir="$(cd "$(dirname "$0")" && pwd)"
command -v ssh-keygen >/dev/null || { echo "Missing host command: ssh-keygen" >&2; exit 2; }
tmp="$(mktemp -d "${TMPDIR:-/tmp}/nix-alpine-qemu-ssh.XXXXXXXX")"
cleanup() {
  set +e
  systemctl --user stop "$unit.service" >/dev/null 2>&1
  podman rm --force "${unit}-guest" >/dev/null 2>&1
  systemctl --user reset-failed "$unit.service" >/dev/null 2>&1
  rm -rf -- "$tmp"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
ssh-keygen -q -t ed25519 -N '' -C nix-alpine-qemu-transient -f "$tmp/id_ed25519"
public_key="$(awk '{print $1 " " $2}' "$tmp/id_ed25519.pub")"
[[ "$public_key" =~ ^ssh-ed25519\ [A-Za-z0-9+/=]+$ ]] || {
  echo "ssh-keygen returned an invalid public key" >&2
  exit 1
}
export COREOS_TEST_SSH_PUBLIC_KEY="$public_key"

"$make_cmd" coreos-qemu-build \
  CONTAINER="$container" WORKSPACES="$workspaces" \
  COREOS_INPUT_CHECKOUT="$input_checkout" COREOS_INPUT_REV="$input_rev" \
  COREOS_BUILD_FLAKE="$build_flake" COREOS_BUILD_TARGET="$build_target" \
  COREOS_CONFIG_DIR="$config_dir" COREOS_RESOURCES="$resources_dir" \
  COREOS_CONFIG_NAME="$config_name" COREOS_COMPOSITION_NAME="$composition" \
  COREOS_STATE="$state" COREOS_REUSE=0
"$make_cmd" build \
  FLAKE="$input_checkout/$runner_flake" TARGET="$runner_target" \
  CONTAINER="$container" WORKSPACES="$workspaces"
"$make_cmd" image-load \
  FLAKE="$input_checkout/$runner_flake" TARGET="$runner_target" \
  CONTAINER="$container" WORKSPACES="$workspaces"

bash "$script_dir/coreos-qemu-qualify.sh" \
  "$unit" "$state" "$timeout" "$ram_mb" "$cpus" "$accel" \
  "$qemu_image" "$display" "$web_port" "$hold" \
  "$ssh_port" "$tmp/id_ed25519" "$composition" 1 "$expected_marker"
