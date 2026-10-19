# Local Make/Bash Nix-Alpine workspace

Smoke and Go orchestration are explicitly out of scope. This is a staging path for a rootless Podman Quadlet and one writable /nix volume per scope.

Default host workspace: `~/workspace/nix` — mounted to `/workspaces` inside Nix-Alpine. Other source repositories may be cloned as child directories.

```sh
git clone https://github.com/dash-xd/nix-alpine.git ~/src/nix-alpine
cd ~/src/nix-alpine/local
make bootstrap
make run FLAKE=agni TARGET='#default'
```

On the staging branch, check out that branch before running the local Makefile. A new `nix run` app may build artifacts within the container, but **must not attempt to operate host systemd directly**. Host activation will be handled by a separate, narrowly scoped Bash deploy target after generation exports, validation, and rollback semantics are implemented.

The host source checkout (`~/src/nix-alpine`) is separate from the flake workspace (`~/workspace/nix`). The bootstrap fetches updates to nix-alpine main through `git pull --ff-only`, which does not change branches itself. Pin a reviewed git revision before relying on the image as a trusted build input.

This variant intentionally does not request a Podman API socket, systemd DBus, KVM, host root, or privileges. Qualification for mounted workspaces, UID mappings, Nix store persistence and service restart is still outstanding.
