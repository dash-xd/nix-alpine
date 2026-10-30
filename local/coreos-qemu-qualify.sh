#!/usr/bin/env bash
set -Eeuo pipefail

unit="${1:?transient unit is required}"
state="${2:?state directory is required}"
timeout_seconds="${3:-600}"
ram_mb="${4:-3072}"
cpus="${5:-2}"
accel="${6:-auto}"

base="$state/base.qcow2"
ignition="$state/config.ign"
overlay="$state/overlay.qcow2"
serial="$state/serial.log"

for command in qemu-system-x86_64 qemu-img systemctl systemd-run; do
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

mkdir -p "$state"
systemctl --user stop "$unit.service" >/dev/null 2>&1 || true
systemctl --user reset-failed "$unit.service" >/dev/null 2>&1 || true
rm -f "$overlay" "$serial"
qemu-img create -q -f qcow2 -F qcow2 -b "$base" "$overlay"

systemd-run --user --quiet --unit="$unit" --collect \
  --property="Description=Fatline CoreOS QEMU bootstrap qualification" \
  --property=Restart=no \
  --property=KillMode=mixed \
  --property=RuntimeMaxSec=15m \
  -- qemu-system-x86_64 \
    -machine "q35,accel=$accel" \
    -m "$ram_mb" -smp "$cpus" \
    -drive "if=virtio,format=qcow2,file=$overlay" \
    -fw_cfg "name=opt/com.coreos/config,file=$ignition" \
    -netdev user,id=net0 \
    -device virtio-net-pci,netdev=net0 \
    -display none -serial "file:$serial" -monitor none \
    -no-reboot
test "$(systemctl --user show --property=Transient --value "$unit.service")" = yes

for ((i=0; i<timeout_seconds; i+=2)); do
  if grep -Fq 'PASS: transient systemd unit ran Podman inside Fedora CoreOS' "$serial" 2>/dev/null; then
    echo "PASS: Fedora CoreOS booted and a transient systemd unit ran Podman"
    echo "CoreOS transient unit: $unit.service"
    echo "Acceleration: $accel"
    echo "Serial log: $serial"
    systemctl --user stop "$unit.service" >/dev/null 2>&1 || true
    systemctl --user reset-failed "$unit.service" >/dev/null 2>&1 || true
    exit 0
  fi
  if systemctl --user is-failed "$unit.service" >/dev/null 2>&1; then
    break
  fi
  sleep 2
done

echo "FAIL: CoreOS did not report the transient Podman bootstrap PASS marker" >&2
systemctl --user --no-pager -l status "$unit.service" >&2 || true
journalctl --user -u "$unit.service" --no-pager -n 120 >&2 || true
if [[ -f "$serial" ]]; then tail -n 160 "$serial" >&2; fi
systemctl --user stop "$unit.service" >/dev/null 2>&1 || true
systemctl --user reset-failed "$unit.service" >/dev/null 2>&1 || true
exit 1
