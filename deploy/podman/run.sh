#!/usr/bin/env bash
set -euo pipefail
image="${NIX_ALPINE_IMAGE:-localhost/nix-alpine:daemon}"
podman volume create nix-alpine-store >/dev/null
podman volume create nix-alpine-socket >/dev/null
exec podman run -d --name nix-alpine-owner \
  -v nix-alpine-store:/nix \
  -v nix-alpine-socket:/run/nix \
  "$image" owner
