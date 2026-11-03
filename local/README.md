# Local Nix-Alpine workspace (Make/Bash only)

Use `~/workspace/nix.xd` as the shared workspace root. Put Nix-Alpine Git checkouts one level below `nix-alpine/`: use `generic/` for a branch-switchable checkout and a dated directory such as `20261103-fatline/` for a retained source version. Put Agni and other composition checkouts under the sibling `compositions/` directory. Every checkout derives the same `nix.xd` root and mounts it at `/workspaces`, so both repository families are visible to Nix flakes and qualification runners.

```text
~/workspace/nix.xd/
├── local/logs/              # shared workspace logs
├── nix-alpine/
│   ├── generic/              # Nix-Alpine Git checkout
│   └── 20261103-fatline/     # optional retained checkout
└── compositions/
    └── agni-fatline/         # composition Git checkout
```

The shared log directory is created when a logged Make target runs. Host-only logs and state remain under `~/.local`; pass `LOG_DIR=...` to override the workspace log path.

```bash
mkdir -p ~/workspace/nix.xd/nix-alpine
git clone -b codex/nixxd-workspace-layout https://github.com/dash-xd/nix-alpine.git ~/workspace/nix.xd/nix-alpine/generic
cd ~/workspace/nix.xd/nix-alpine/generic/local
make bootstrap
make status
make uninstall
```

The toolbox image tag uses the runtime business name and the Nix-Alpine source commit date and short revision, for example `localhost/nix.xd:2026.11.03-<revision>`. This identifies the source used to build it; it does not claim that Nix-Alpine itself passed a qualification pipeline. The systemd unit and container name also include the workspace, checkout, and scope, so different dated workspaces or revisions can run side by side. The Nix store volume remains scope-named to preserve the existing store across source refreshes. Choose a distinct `SCOPE` when you need an isolated store.

`make refresh` fast-forwards the current checkout, then rebuilds and starts the newly versioned instance. Older versioned units remain available for comparison or rollback. `make uninstall` removes only the selected versioned instance's rootless Podman container, Quadlet definitions, and its scope's Nix store volume; inspect other old resources before cleaning them up. It does **not** remove this checkout, sibling workspaces, other flakes, or unrelated Podman resources.

Default scope: `dev`. Other scopes: `make bootstrap SCOPE=other` and `make uninstall SCOPE=other`.

`make qualify-toolbox LOG=1` is a focused rootless smoke check: it verifies the systemd service and versioned image, evaluates `QUALIFY_FLAKE` inside the toolbox (default: the reusable toolbox toolchain flake), creates a small Nix store output, then confirms a second rootless Podman container can read that output through the same named `/nix` volume. It does not require Nix on the host and does not inspect the host's Podman volume storage path.

`make qualify-plan` keeps the host as a small control surface: Make syncs the selected plan, ensures the versioned toolbox image and Nix volume exist, and starts a disposable Nix-Alpine runtime container. The selected plan and its assertions run inside that container using the pinned `toolbox#qualification` shell. The runtime container shares the workspace and `/nix` volume and receives only the host user's rootless Podman socket, user-systemd bus, and the two user unit directories needed by Quadlet. It mounts the workspace at `/workspaces` for flakes and at its host path for bind sources created by the plan. It uses host networking so tests can reach services deliberately published on `127.0.0.1`. It runs as the calling user through `keep-id`; it has no system-level/root Podman or systemd access. While a plan is running, it has the same authority as that user's rootless Podman client and can write that user's systemd/Quadlet definitions. The persistent toolbox does not receive those host-control mounts.

This keeps application-specific plans and gates in Agni while Nix-Alpine supplies the reproducible runtime and generic host adapter. It remains a host Podman/systemd qualification, not a CoreOS boot or a minimal-distro qualification.

## Qualification logs

Set `LOG=1` on a qualification Make target to stream output to the terminal and a
timestamped log file. The wrapper records the command's exit code and returns it
to Make; a failed gate remains a failed Make command.

```bash
make qualify-composition COMPOSITION=fatline GATE=all LOG=1
make qualify-composition-skymill-provider QUADLET=1 LOG=1
```

All workspace logs default to `~/workspace/nix.xd/local/logs`. Qualification log names begin with `qualification-` and include the plan or composition, gate, and scope; the wrapper adds a UTC timestamp and PID. The directory is created on demand. Override `LOG_DIR` for a Make invocation or `LOG_NAME` to set a different filename prefix. The Skymill Quadlet mode runs Skymill's disposable provider against
Logma, Redis, and Nginx started as systemd-user Quadlets.

## CoreOS transient guest tester

CoreOS profile logic is owned by the selected infrastructure checkout. The
Nix-Alpine Makefile provides the host QEMU/systemd adapter and invokes the
profile's pinned preparation app inside the toolbox. For example, the Agni
Astrochicken profile is selected by name:

```bash
make qualify-coreos-profile \
  COREOS_PROFILE=astrochicken \
  COREOS_PROFILE_BRANCH=agni-profile-branch \
  COREOS_PROFILE_REV=<full-agni-commit-sha> \
  LOG=1
```

The profile's Butane, guest units, inputs, expected marker, and preparation
logic live in Agni under `qemu/coreos-live/profiles/astrochicken`. Nix-Alpine
owns generic host resource setup, Nix build execution, rootless Podman, and
transient systemd-user QEMU lifecycle. It does not own the Astrochicken
qualification behavior.

The selected profile owns whether a transient SSH tester is enabled and which
guest identity it uses. The Astrochicken profile currently qualifies its
systemd/Podman/Nix service without SSH; the production boot path has no SSH
dependency. Use `qualify-coreos-guest-transient` only against an already
provisioned guest that supports the generated application account.

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
cd ~/workspace/nix.xd/nix-alpine/generic/local
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
`$NIX_ALPINE_STATE_ROOT/releases` (default `$HOME/.local/state/nix.xd/releases`). A candidate or qualified version is
never overwritten by this command. The integration target is not yet
qualified on the local host; do not use it for production activation.


## Ephemeral and retained plan runs

Plan runs are ephemeral by default: the Agni runner removes the run's user units, Quadlet definitions, containers, network, and scratch directory on normal completion. Set `RETAIN=1` on `make qualify-plan` to keep the final selected gate's runtime active for live inspection. The runner prints its literal run prefix. To remove a retained run or recover resources left by a killed run, first inspect with `make cleanup-run RUN_PREFIX=<printed-prefix> DRY_RUN=1`, then repeat with `DRY_RUN=0` after reviewing the exact matches. This scoped operation preserves toolbox containers, Nix store volumes, reusable images, logs, source checkouts, and unrelated workspace files. Persistent toolbox instances are managed separately with the selected instance's `make uninstall`.
