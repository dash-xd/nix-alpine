# Experimental daemon-backed flake runtime

This directory is a generic Nix owner/client runtime. It does not define application
compositions. The existing single-user toolbox and cache Actions are unchanged.

## Build

Build the existing toolbox image first:

```sh
docker build -t nix-toolbox:latest .
docker build -f Dockerfile.daemon -t nix-alpine:daemon .
```

Podman can be used instead of Docker for these builds. The daemon variant is
experimental and must be runtime-qualified before production use.

## Local Podman

```sh
NIX_ALPINE_IMAGE=localhost/nix-alpine:daemon bash deploy/podman/run.sh
podman run --rm --user 0 \
  -v nix-alpine-store:/nix:ro \
  -v nix-alpine-socket:/run/nix \
  -v "$PWD/examples/smoke-flake:/workspace:ro" \
  localhost/nix-alpine:daemon client nix build /workspace#default --no-link
```

The owner is the only writable /nix mount. Client store mounts are read-only.
The daemon socket is privileged: only give it to trusted build clients. A
reader without the socket can inspect already-built paths with a read-only
store mount.

The example flake has an optional `#image` dockerTools target. Flakes are
external to the runtime and can be mounted from arbitrary directories.

## Quadlet

Copy the three files under deploy/quadlet into
`~/.config/containers/systemd/`, then run `systemctl --user daemon-reload`
and `systemctl --user start nix-alpine-owner.service`. Ensure the daemon
image is available as `localhost/nix-alpine:daemon`.

## Boundaries and outstanding qualification

* The base toolbox is a single-user Nix installation. The daemon image
  copies its initialized store into a seed before /nix is overmounted.
  Validate Nix daemon and build-user behavior on actual Podman hosts.
* The seed is tied to the exact daemon image/Nix version. Do not
  initialize an existing store with a different seed or run two owners.
* Nix build clients require access to the daemon socket; this grants
  build authority, not read-only access.
* Rootless Podman, SELinux labels, socket permissions, and build sandbox
  limitations require explicit tests.
* Existing volume-cache/action.yml still uses single-user execution and
  is not migrated by this change.
* GC roots and upgrade/migration procedures remain to be qualified.
