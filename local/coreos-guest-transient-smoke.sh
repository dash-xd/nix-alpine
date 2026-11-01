#!/usr/bin/bash
set -Eeuo pipefail

expected_prefix="${COREOS_COMPOSITION_NAME:?composition prefix is required}"
actual="$(/usr/bin/id -un)"
[[ -n "${INVOCATION_ID:-}" ]] || { echo "tester is not running as a systemd service" >&2; exit 1; }
[[ "$actual" =~ ^${expected_prefix}-[a-f0-9]{12}$ ]] || {
  echo "unexpected transient service identity: $actual" >&2
  exit 1
}
[[ "$(/usr/bin/podman info --format '{{.Host.Security.Rootless}}')" == true ]] || {
  echo "Podman is not running rootless for $actual" >&2
  exit 1
}
echo "PASS: transient systemd service runs rootless Podman as $actual"
