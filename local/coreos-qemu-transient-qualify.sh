#!/usr/bin/env bash
set -Eeuo pipefail

make_cmd="${1:-make}"
container="${2:?Nix-Alpine toolbox container is required}"
workspaces="${3:?WORKSPACES is required}"
agni_checkout="${4:?Agni checkout is required}"
agni_rev="${5:?Agni revision is required}"
state="${6:?CoreOS state directory is required}"
unit="${7:?QEMU unit name is required}"
timeout="${8:-600}"
ram_mb="${9:-3072}"
cpus="${10:-2}"
accel="${11:-auto}"
qemu_image="${12:?QEMU image is required}"
display="${13:-headless}"
web_port="${14:-8006}"
hold="${15:-0}"
ssh_port="${16:-2222}"
composition="${17:-fatline}"

script_dir="$(cd "$(dirname "$0")" && pwd)"
command -v ssh-keygen >/dev/null || { echo "Missing host command: ssh-keygen" >&2; exit 2; }
tmp="$(mktemp -d "${TMPDIR:-/tmp}/fatline-qemu-ssh.XXXXXXXX")"
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
ssh-keygen -q -t ed25519 -N '' -C fatline-qemu-transient -f "$tmp/id_ed25519"
public_key="$(awk '{print $1 " " $2}' "$tmp/id_ed25519.pub")"
[[ "$public_key" =~ ^ssh-ed25519\ [A-Za-z0-9+/=]+$ ]] || {
  echo "ssh-keygen returned an invalid public key" >&2
  exit 1
}
export COREOS_TEST_SSH_PUBLIC_KEY="$public_key"

"$make_cmd" coreos-qemu-build \
  CONTAINER="$container" WORKSPACES="$workspaces" \
  COMPOSITION_AGNI_CHECKOUT="$agni_checkout" \
  COMPOSITION_AGNI_REV="$agni_rev" \
  COREOS_CONFIG_NAME=fatline-bootstrap-transient.bu \
  COREOS_COMPOSITION_NAME="$composition" COREOS_STATE="$state" COREOS_REUSE=0
"$make_cmd" build \
  FLAKE="$agni_checkout/qemu/coreos-live/local" TARGET='#qemuRunner' \
  CONTAINER="$container" WORKSPACES="$workspaces"
"$make_cmd" image-load \
  FLAKE="$agni_checkout/qemu/coreos-live/local" TARGET='#qemuRunner' \
  CONTAINER="$container" WORKSPACES="$workspaces"

bash "$script_dir/coreos-qemu-qualify.sh" \
  "$unit" "$state" "$timeout" "$ram_mb" "$cpus" "$accel" \
  "$qemu_image" "$display" "$web_port" "$hold" \
  "$ssh_port" "$tmp/id_ed25519" "$composition" 1
