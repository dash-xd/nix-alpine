# Local Nix-Alpine workspace (Make/Bash only)

Place this repository at `~/workspace/nix/nix-alpine`. The parent directory is mounted to `/workspaces` in the container.

```bash
mkdir -p ~/workspace/nix
git clone -b codex/make-bash-local-orchestration https://github.com/dash-xd/nix-alpine.git ~/workspace/nix/nix-alpine
cd ~/workspace/nix/nix-alpine/local
make bootstrap
make status
make uninstall
```

`make uninstall` removes the selected scope's rootless Podman container, Quadlet definitions and Nix store volume, and removes the toolbox image if no other container references it. It does **not** remove this checkout, `~/workspace/nix`, other flakes, or unrelated Podman resources.

Default scope: `dev`. Other scopes: `make bootstrap SCOPE=other` and `make uninstall SCOPE=other`.

No Smoke, Go daemon, host systemd bus mount, KVM passthrough or host deployment activation is implemented. The actual ThinkPad bootstrap and uninstall lifecycle still needs qualification.

## Qualification logs

Set `LOG=1` on a qualification Make target to stream output to the terminal and a
timestamped log file. The wrapper records the command's exit code and returns it
to Make; a failed gate remains a failed Make command.

```bash
make qualify-composition COMPOSITION=fatline GATE=all LOG=1
make qualify-composition-skymill-provider QUADLET=1 LOG=1
```

Logs default to `~/.local/state/nix-alpine/qualification-logs`. Override
`LOG_DIR` to choose another directory or `LOG_NAME` to set the filename
prefix. The Skymill Quadlet mode runs Skymill's disposable provider against
Logma, Redis, and Nginx started as systemd-user Quadlets.

## Local release workflow

The host only needs Make, Bash, jq, and rootless Podman. Nix executes in the
already bootstrapped `nix-alpine-<scope>` container. No host Nix, registry,
GitHub Actions image cache, or artifact upload is involved.

```bash
cd ~/workspace/nix/nix-alpine/local
make bootstrap
make test-release                   # lightweight ledger contracts; no Nix
make release-lock                   # writes ../release/flake.lock via workspace mount
git -C .. add release/flake.lock    # commit the generated lock with your change
make release-check                  # Nix flake check, inside container

# Example only: the target repo must expose #provider-image,
# #qualify and #qualify-integration, and have a clean locked checkout.
make test-release-integration \
  REPO=xd-dash/skymill COMPONENT=skymill \
  RELEASE_FLAKE=/workspaces/skymill \
  RELEASE_TARGET='#provider-image' \
  RELEASE_VERSION=2026.10.21.1
```

`make version COMPONENT=skymill` reports the next locally unused CalVer.
A real integration release uses `make release-candidate` and
`make release-qualify` under the hood, and writes evidence to
`~/.local/state/nix-alpine/releases`. A candidate or qualified version is
never overwritten by this command. The integration target is not yet
qualified on the local host; do not use it for production activation.
