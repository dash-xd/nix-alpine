#!/usr/bin/env bash
set -Eeuo pipefail

accel="${1:-auto}"
[[ "$accel" == auto || "$accel" == kvm || "$accel" == tcg ]] || {
  echo "COREOS_QEMU_ACCEL must be auto, kvm, or tcg" >&2
  exit 2
}

for command in podman systemctl systemd-run; do
  command -v "$command" >/dev/null || {
    echo "Missing host command: $command" >&2
    exit 2
  }
done

systemctl --user show-environment >/dev/null || {
  echo "The systemd user manager is unavailable; start the user session before qualifying QEMU" >&2
  exit 2
}

[[ "$(podman info --format '{{.Host.Security.Rootless}}')" == true ]] || {
  echo "QEMU qualification requires rootless Podman" >&2
  exit 2
}

if [[ "$accel" == kvm && ! ( -r /dev/kvm && -w /dev/kvm ) ]]; then
  echo "KVM requested but /dev/kvm is not accessible" >&2
  exit 2
fi

if [[ "$accel" == auto ]]; then
  if [[ -r /dev/kvm && -w /dev/kvm ]]; then
    accel=kvm
  else
    accel=tcg
  fi
fi

echo "PASS: rootless Podman and systemd user manager are ready (QEMU acceleration=$accel)"
