#!/usr/bin/env bash
# Disposable systemd-user Quadlet lifecycle gate for a loaded Nginx image.
# Intended for an isolated CI runner user manager; never invoke against production.
set -Eeuo pipefail
[[ $# == 1 ]] || { echo "usage: $0 NGINX_IMAGE" >&2; exit 2; }
image=$1
[[ "${FATLINE_CI_DISPOSABLE_RUNNER:-}" == 1 ]] || { echo "Refusing to modify a user manager outside an explicitly disposable CI runner" >&2; exit 2; }
command -v systemctl >/dev/null
command -v podman >/dev/null
podman image exists "$image"
[[ -n "${XDG_RUNTIME_DIR:-}" && -S "$XDG_RUNTIME_DIR/bus" ]] || { echo "Missing systemd user bus" >&2; exit 1; }
systemctl --user show-environment >/dev/null
unit_dir="$HOME/.config/containers/systemd"
name="fatline-ci-quadlet-$$"
unit="$unit_dir/$name.container"
service="$name.service"
container="$name"
work=$(mktemp -d -t fatline-quadlet-XXXXXXXX)
cleanup() {
  code=$?
  systemctl --user stop "$service" >/dev/null 2>&1 || true
  rm -f "$unit"
  systemctl --user daemon-reload >/dev/null 2>&1 || true
  podman rm -f "$container" >/dev/null 2>&1 || true
  rm -rf "$work"
  if systemctl --user list-unit-files --no-legend "$service" 2>/dev/null | grep -Fq "$service"; then
    echo "FAIL: Quadlet unit remained installed" >&2
    code=1
  fi
  exit "$code"
}
trap cleanup EXIT
mkdir -p "$unit_dir"
cat > "$work/nginx.conf" <<'CONF'
worker_processes 1;
pid /tmp/nginx.pid;
error_log /dev/stderr warn;
events { worker_connections 64; }
http {
  access_log off;
  server {
    listen 127.0.0.1:8080;
    location /health { return 200 "ok"; }
  }
}
CONF
cat > "$unit" <<EOF
[Unit]
Description=Disposable Fatline CI Quadlet lifecycle fixture
[Container]
Image=$image
Pull=never
ContainerName=$container
Network=none
User=65534:65534
ReadOnly=true
Volume=$work/nginx.conf:/etc/nginx/nginx.conf:ro
Tmpfs=/tmp:rw,noexec,nosuid,size=4m
NoNewPrivileges=true
DropCapability=all
[Service]
Restart=no
EOF
chmod 644 "$unit" "$work/nginx.conf"
systemctl --user daemon-reload
systemctl --user cat "$service" >/dev/null
systemctl --user start "$service"
systemctl --user is-active --quiet "$service"
podman inspect "$container" --format '{{.State.Running}}' | grep -Fx true
first=$(podman inspect "$container" --format '{{.Id}}')
systemctl --user restart "$service"
systemctl --user is-active --quiet "$service"
podman inspect "$container" --format '{{.State.Running}}' | grep -Fx true
second=$(podman inspect "$container" --format '{{.Id}}')
[[ "$first" != "$second" ]] || { echo "FAIL: restart did not replace container" >&2; exit 1; }
echo "PASS: systemd-user Quadlet generated, started, restarted with replacement container"
echo "PASS: rollback cleanup will stop service, remove unit and reload generator"
