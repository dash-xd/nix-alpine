#!/usr/bin/env bash
set -Eeuo pipefail

unit="${1:?transient unit is required}"
state="${2:?state directory is required}"
timeout_seconds="${3:-600}"
ram_mb="${4:-3072}"
cpus="${5:-2}"
accel="${6:-auto}"
qemu_image="${7:?QEMU runtime image is required}"
state="$(realpath -m "$state")"

base="$state/base.qcow2"
ignition="$state/config.ign"
overlay="$state/overlay.qcow2"
serial="$state/serial.log"
container_name="${unit}-guest"

for command in podman systemctl systemd-run; do
  command -v "$command" >/dev/null || { echo "Missing host command: $command" >&2; exit 2; }
done
test -s "$base" || { echo "Missing CoreOS disk: $base" >&2; exit 2; }
test -s "$ignition" || { echo "Missing Ignition config: $ignition" >&2; exit 2; }
[[ "$timeout_seconds" =~ ^[0-9]+$ ]] && (( timeout_seconds >= 60 )) || { echo "Invalid QEMU timeout" >&2; exit 2; }
[[ "$ram_mb" =~ ^[0-9]+$ ]] && (( ram_mb >= 2048 )) || { echo "RAM must be at least 2048 MiB" >&2; exit 2; }
[[ "$cpus" =~ ^[1-9][0-9]*$ ]] || { echo "Invalid CPU count" >&2; exit 2; }
[[ "$unit" =~ ^[A-Za-z0-9_.@-]+$ ]] || { echo "Invalid transient unit name" >&2; exit 2; }
[[ "$accel" == auto || "$accel" == kvm || "$accel" == tcg ]] || { echo "COREOS_QEMU_ACCEL must be auto, kvm, or tcg" >&2; exit 2; }

if [[ "$accel" == auto ]]; then
  if [[ -r /dev/kvm && -w /dev/kvm ]]; then accel=kvm; else accel=tcg; fi
fi
if [[ "$accel" == kvm && ! ( -r /dev/kvm && -w /dev/kvm ) ]]; then
  echo "KVM requested but /dev/kvm is not accessible" >&2
  exit 2
fi
qemu_accel="$accel"
if [[ "$accel" == tcg ]]; then qemu_accel="tcg,thread=multi"; fi

image_id="$(podman image inspect "$qemu_image" --format '{{.Id}}')" || {
  echo "QEMU runtime image is not loaded: $qemu_image" >&2
  exit 2
}
[[ "$image_id" =~ ^sha256:[a-f0-9]{64}$ ]] || {
  echo "Unexpected Podman image ID: $image_id" >&2
  exit 2
}

mkdir -p "$state"
systemctl --user stop "$unit.service" >/dev/null 2>&1 || true
systemctl --user reset-failed "$unit.service" >/dev/null 2>&1 || true
podman rm --force "$container_name" >/dev/null 2>&1 || true
rm -f "$overlay" "$serial"

podman run --rm --pull=never --volume "$state:/state:rw,z" "$image_id" \
  img create -q -f qcow2 -F qcow2 -b /state/base.qcow2 /state/overlay.qcow2

podman_args=(run --rm --pull=never --name "$container_name" --volume "$state:/state:rw,z")
if [[ "$accel" == kvm ]]; then
  podman_args+=(--device /dev/kvm:/dev/kvm:rw)
fi

systemd-run --user --quiet --unit="$unit" --collect \
  --property="Description=Fatline CoreOS QEMU Podman bootstrap qualification" \
  --property=Restart=no \
  --property=KillMode=mixed \
  --property=RuntimeMaxSec=15m \
  --property=TimeoutStopSec=20s \
  -- "${podman_args[@]}" "$image_id" run \
    -machine q35 -accel "$qemu_accel" \
    -m "$ram_mb" -smp "$cpus" \
    -drive if=virtio,format=qcow2,file=/state/overlay.qcow2 \
    -fw_cfg name=opt/com.coreos/config,file=/state/config.ign \
    -netdev user,id=net0 \
    -device virtio-net-pci,netdev=net0 \
    -display none -serial file:/state/serial.log -monitor none \
    -no-reboot
test "$(systemctl --user show --property=Transient --value "$unit.service")" = yes

cleanup() {
  systemctl --user stop "$unit.service" >/dev/null 2>&1 || true
  podman rm --force "$container_name" >/dev/null 2>&1 || true
  systemctl --user reset-failed "$unit.service" >/dev/null 2>&1 || true
}
trap cleanup EXIT

for ((i=0; i<timeout_seconds; i+=2)); do
  if grep -Fq 'PASS: transient systemd unit ran Podman inside Fedora CoreOS' "$serial" 2>/dev/null; then
    echo "PASS: Fedora CoreOS booted and a transient systemd unit ran Podman"
    echo "Host systemd unit: $unit.service"
    echo "QEMU Podman image: $image_id"
    echo "Acceleration: $accel"
    echo "Serial log: $serial"
    exit 0
  fi
  if systemctl --user is-failed "$unit.service" >/dev/null 2>&1; then
    break
  fi
  if ! systemctl --user is-active --quiet "$unit.service"; then
    break
  fi
  sleep 2
done

echo "FAIL: CoreOS did not report the transient Podman bootstrap PASS marker" >&2
systemctl --user --no-pager -l status "$unit.service" >&2 || true
journalctl --user -u "$unit.service" --no-pager -n 120 >&2 || true
podman logs "$container_name" >&2 2>/dev/null || true
if [[ -f "$serial" ]]; then tail -n 160 "$serial" >&2; fi
exit 1
