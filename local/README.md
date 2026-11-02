# Local Nix-Alpine workspace (Make/Bash only)

Place the generic checkout at `~/workspace/nix/nix-alpine`, or place a dated checkout under `~/workspace/nix/workspaces/<date>/<workspace-name>/nix-alpine`. The parent workspace is inferred from the checkout and mounted to `/workspaces` in the container. Override `WORKSPACES` only when the workspace layout differs.

```bash
mkdir -p ~/workspace/nix
git clone -b codex/make-bash-local-orchestration https://github.com/dash-xd/nix-alpine.git ~/workspace/nix/nix-alpine
cd ~/workspace/nix/nix-alpine/local
make bootstrap
make status
make uninstall
```

The toolbox image tag is derived from the Nix-Alpine source commit date and short revision, for example `localhost/nix-alpine:2026.11.01-<revision>`. This identifies the source used to build it; it does not claim that Nix-Alpine itself passed a qualification pipeline. The systemd unit and container name also include the workspace, checkout, and scope, so different dated workspaces or revisions can run side by side. The Nix store volume remains scope-named to preserve the existing store across source refreshes. Choose a distinct `SCOPE` when you need an isolated store.

`make refresh` fast-forwards the current checkout, then rebuilds and starts the newly versioned instance. Older versioned units remain available for comparison or rollback. `make uninstall` removes only the selected versioned instance's rootless Podman container, Quadlet definitions, and its scope's Nix store volume; inspect other old resources before cleaning them up. It does **not** remove this checkout, `~/workspace/nix`, other flakes, or unrelated Podman resources.

Default scope: `dev`. Other scopes: `make bootstrap SCOPE=other` and `make uninstall SCOPE=other`.

No Smoke, Go daemon, host systemd bus mount, KVM passthrough or host deployment activation is implemented. `make qualify-toolbox LOG=1` is a focused rootless smoke check: it verifies the systemd service and versioned image, evaluates the checked-in release flake inside the toolbox, creates a small Nix store output, then confirms a second rootless Podman container can read that output through the same named `/nix` volume. It does not require Nix on the host and does not inspect the host's Podman volume storage path.

## Qualification logs

Set `LOG=1` on a qualification Make target to stream output to the terminal and a
timestamped log file. The wrapper records the command's exit code and returns it
to Make; a failed gate remains a failed Make command.

```bash
make qualify-composition COMPOSITION=fatline GATE=all LOG=1
make qualify-composition-skymill-provider QUADLET=1 LOG=1
```

Logs default to `local/qualification-logs` in this checkout. The directory is
tracked; generated `*.log` files are ignored. Override `LOG_DIR` to choose
another directory or `LOG_NAME` to set the filename prefix. The Skymill Quadlet mode runs Skymill's disposable provider against
Logma, Redis, and Nginx started as systemd-user Quadlets.

## CoreOS transient guest tester

`make qualify-coreos-qemu COREOS_QEMU_TRANSIENT_TESTER=1` creates a throwaway
SSH key, injects only its public half into a qualification-only Ignition
profile, and forwards SSH on loopback. It copies the small tester into FCOS
with SCP, then runs it as the generated composition user using a transient
`systemd --user` unit. The private key and remote staging files are removed
when the gate exits. This is an optional qualification path and is not part of
production boot or recovery.

The same guest runner can target a GCP CoreOS guest through an already-open
IAP tunnel. After starting the tunnel on a local port, run:

```bash
make qualify-coreos-guest-transient \
  COREOS_GUEST_HOST=127.0.0.1 COREOS_GUEST_PORT=2222 \
  COREOS_GUEST_KEY="$HOME/.ssh/coreos-test" \
  COREOS_GUEST_COMPOSITION=fatline LOG=1
```

The guest must have the Agni-generated composition user and user systemd
manager. The GCP tunnel/key setup stays outside the shared guest runner; SSH
and SCP are only test transport.

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
`$NIX_ALPINE_HOME/.state/nix-alpine/releases` (default `$HOME/workspace/nix/.state/nix-alpine/releases`). A candidate or qualified version is
never overwritten by this command. The integration target is not yet
qualified on the local host; do not use it for production activation.
