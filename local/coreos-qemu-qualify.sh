#!/usr/bin/env bash
set -Eeuo pipefail

unit="${1:?transient unit is required}"
state="${2:?state directory is required}"
timeout_seconds="${3:-600}"
ram_mb="${4:-3072}"
cpus="${5:-2}"
accel="${6:-auto}"
qemu_image="${7:?QEMU runtime image is required}"
display="${8:-headless}"
web_port="${9:-8006}"
hold="${10:-0}"
ssh_port="${11:-2222}"
ssh_key="${12:-}"
composition="${13:-guest}"
transient_test="${14:-0}"
expected_marker="${15:-}"
state="$(realpath -m "$state")"

base="$state/base.qcow2"
ignition="$state/config.ign"
overlay="$state/overlay.qcow2"
serial="$state/serial.log"
container_name="${unit}-guest"

for command in podman systemctl systemd-run; do
  command -v "$command" >/dev/null || { echo "Missing host command: $command" >&2; exit 2; }
done
[[ "$timeout_seconds" =~ ^[0-9]+$ ]] && (( timeout_seconds >= 60 )) || { echo "Invalid QEMU timeout" >&2; exit 2; }
[[ "$ram_mb" =~ ^[0-9]+$ ]] && (( ram_mb >= 2048 )) || { echo "RAM must be at least 2048 MiB" >&2; exit 2; }
[[ "$cpus" =~ ^[1-9][0-9]*$ ]] || { echo "Invalid CPU count" >&2; exit 2; }
[[ "$unit" =~ ^[A-Za-z0-9_.@-]+$ ]] || { echo "Invalid transient unit name" >&2; exit 2; }
[[ "$accel" == auto || "$accel" == kvm || "$accel" == tcg ]] || { echo "COREOS_QEMU_ACCEL must be auto, kvm, or tcg" >&2; exit 2; }
[[ "$display" == headless || "$display" == web ]] || { echo "COREOS_QEMU_DISPLAY must be headless or web" >&2; exit 2; }
[[ "$hold" == 0 || "$hold" == 1 ]] || { echo "COREOS_QEMU_HOLD must be 0 or 1" >&2; exit 2; }
[[ "$hold" != 1 || "$display" == web ]] || { echo "COREOS_QEMU_HOLD=1 requires web display" >&2; exit 2; }
[[ "$transient_test" == 0 || "$transient_test" == 1 ]] || { echo "transient test must be 0 or 1" >&2; exit 2; }
if [[ "$transient_test" == 1 ]]; then
  [[ "$ssh_port" =~ ^[0-9]+$ ]] && (( ssh_port >= 1024 && ssh_port <= 65535 )) || { echo "Invalid SSH forwarding port" >&2; exit 2; }
  [[ -r "$ssh_key" && -x "$(dirname "$0")/coreos-guest-transient-qualify.sh" ]] || { echo "Transient tester SSH key/helper is missing" >&2; exit 2; }
  [[ "$composition" =~ ^[a-z_][a-z0-9_-]{0,18}$ ]] || { echo "Invalid composition account prefix" >&2; exit 2; }
fi
if [[ "$display" == web ]]; then
  [[ "$web_port" =~ ^[1-9][0-9]{0,4}$ ]] && (( 10#$web_port >= 1024 && 10#$web_port <= 65535 )) || {
    echo "COREOS_QEMU_WEB_PORT must be between 1024 and 65535" >&2
    exit 2
  }
fi
test -s "$base" || { echo "Missing CoreOS disk: $base" >&2; exit 2; }
test -s "$ignition" || { echo "Missing Ignition config: $ignition" >&2; exit 2; }

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
if [[ "$image_id" =~ ^[a-f0-9]{64}$ ]]; then
  image_id="sha256:$image_id"
fi
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
qemu_command=run
netdev=user,id=net0
if [[ "$display" == web ]]; then
  qemu_command=run-web
  # The browser console is reachable only from the host itself. Raw VNC stays
  # on the container's loopback interface and is never published.
  podman_args+=(--publish "127.0.0.1:${web_port}:6080")
fi
if [[ "$transient_test" == 1 ]]; then
  podman_args+=(--publish "127.0.0.1:${ssh_port}:2222")
  netdev+=",hostfwd=tcp::2222-:22"
fi
if [[ "$accel" == kvm ]]; then
  podman_args+=(--device /dev/kvm:/dev/kvm:rw)
fi

systemd-run --user --quiet --unit="$unit" --collect \
  --property="Description=CoreOS QEMU Podman profile qualification" \
  --property=Restart=no \
  --property=KillMode=mixed \
  --property="RuntimeMaxSec=$((timeout_seconds + 60))s" \
  --property=TimeoutStopSec=20s \
  -- podman "${podman_args[@]}" "$image_id" "$qemu_command" \
    -machine q35 -accel "$qemu_accel" \
    -m "$ram_mb" -smp "$cpus" \
    -drive if=virtio,format=qcow2,file=/state/overlay.qcow2 \
    -fw_cfg name=opt/com.coreos/config,file=/state/config.ign \
    -netdev "$netdev" \
    -device virtio-net-pci,netdev=net0 \
    -display none -serial file:/state/serial.log -monitor none \
    -no-reboot
test "$(systemctl --user show --property=Transient --value "$unit.service")" = yes
if [[ "$display" == web ]]; then
  echo "QEMU browser console: http://127.0.0.1:${web_port}/vnc.html?autoconnect=true&resize=scale"
fi

cleanup() {
  systemctl --user stop "$unit.service" >/dev/null 2>&1 || true
  podman rm --force "$container_name" >/dev/null 2>&1 || true
  systemctl --user reset-failed "$unit.service" >/dev/null 2>&1 || true
  rm -f "$overlay"
}
trap cleanup EXIT

for ((i=0; i<timeout_seconds; i+=2)); do
  if grep -Fq 'COREOS_QEMU_STATUS=FAIL' "$serial" 2>/dev/null; then
    echo "FAIL: Fedora CoreOS guest reported a bootstrap failure" >&2
    tail -n 240 "$serial" >&2
    exit 1
  fi
  if grep -Eq 'Ignition has failed|Entering emergency mode|failed to acquire config|config is not valid' "$serial" 2>/dev/null; then
    echo "FAIL: Fedora CoreOS entered Ignition emergency mode" >&2
    tail -n 160 "$serial" >&2
    exit 1
  fi
  if (( i > 0 && i % 30 == 0 )); then
    echo "CHECK: waiting for Fedora CoreOS qualification marker (${i}s elapsed)"
    tail -n 3 "$serial" 2>/dev/null || true
  fi
  if grep -Fq 'COREOS_QEMU_STATUS=PASS' "$serial" 2>/dev/null; then
    if [[ -n "$expected_marker" ]] && ! grep -Fq -- "$expected_marker" "$serial" 2>/dev/null; then
      echo "FAIL: CoreOS reported success without the requested guest qualification marker: $expected_marker" >&2
      tail -n 240 "$serial" >&2
      exit 1
    fi
    if [[ -n "$expected_marker" ]]; then
      echo "PASS: Fedora CoreOS bootstrap and requested guest qualification marker"
    else
      echo "PASS: Fedora CoreOS guest qualification result"
    fi
    echo "Host transient systemd unit: $unit.service"
    echo "QEMU Podman image: $image_id"
    echo "Acceleration: $accel"
    echo "Serial log: $serial"
    if [[ "$display" == web ]]; then
      echo "QEMU browser console: http://127.0.0.1:${web_port}/vnc.html?autoconnect=true&resize=scale"
    fi
    if [[ "$transient_test" == 1 ]]; then
      bash "$(dirname "$0")/coreos-guest-transient-qualify.sh" \
        127.0.0.1 "$ssh_port" "$ssh_key" "$composition" 10m
    fi
    if [[ "$hold" == 1 ]]; then
      echo "Interactive console is holding the guest. Stop it from another terminal with:"
      echo "systemctl --user stop $unit.service"
      for ((hold_i=0; hold_i<timeout_seconds; hold_i+=2)); do
        if ! systemctl --user is-active --quiet "$unit.service"; then
          echo "PASS: interactive guest stopped after the qualification smoke"
          exit 0
        fi
        sleep 2
      done
      echo "FAIL: interactive guest exceeded COREOS_QEMU_TIMEOUT" >&2
      exit 1
    fi
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

if [[ -n "$expected_marker" ]]; then
  echo "FAIL: CoreOS did not report the requested guest qualification marker: $expected_marker" >&2
else
  echo "FAIL: CoreOS did not report the Podman qualification bootstrap PASS marker" >&2
fi
systemctl --user --no-pager -l status "$unit.service" >&2 || true
journalctl --user -u "$unit.service" --no-pager -n 120 >&2 || true
podman logs "$container_name" >&2 2>/dev/null || true
if [[ -f "$serial" ]]; then tail -n 160 "$serial" >&2; fi
exit 1
