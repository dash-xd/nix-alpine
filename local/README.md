# Nix-Alpine local runtime

Nix-Alpine is the generic Nix and flake execution runtime used by Make. It provides a rootless Podman toolbox, a shared Nix store, and generic systemd-user/Podman/QEMU adapters. Application and composition plans, pins, resources, expected behavior, and qualification gates belong to the caller repository (for example, Agni).

## Workspace layout

Use `~/workspace/nix.xd` as the common mounted workspace. Keep switchable Nix-Alpine checkouts under `nix-alpine/`, and caller repositories such as infrastructure plans under `compositions/`.

```text
~/workspace/nix.xd/
├── local/logs/             # shared Make logs; ignored by source repositories
├── nix-alpine/
│   ├── generic/             # branch-switchable Nix-Alpine checkout
│   └── YYYYMMDD-name/       # optional retained source snapshot
└── compositions/
    └── <caller-checkout>/
```

Each checkout derives the common root and mounts it at `/workspaces`, so flakes can reference sibling checkouts. Qualification logs default to `~/workspace/nix.xd/local/logs`; host-only state remains under `~/.local/state/nix.xd`. Override `LOG_DIR` for a Make invocation.

## Bootstrap and toolbox identity

```bash
cd ~/workspace/nix.xd/nix-alpine/generic/local
make bootstrap SCOPE=dev WORKSPACES="$HOME/workspace/nix.xd"
make status SCOPE=dev WORKSPACES="$HOME/workspace/nix.xd"
make qualify-toolbox LOG=1 SCOPE=dev WORKSPACES="$HOME/workspace/nix.xd"
```

The toolbox image tag identifies the Nix-Alpine source date and commit, for example `localhost/nix.xd:2026.11.03-<revision>`. It is a source identity, not a qualification claim. Unit and container names also include workspace, checkout, and scope, allowing distinct workspaces to run side by side. A scope owns its named Nix store volume.

`make refresh` fast-forwards the current checkout, then rebuilds and starts the versioned instance. `make uninstall` removes only the selected instance and its scoped Nix store. Review the selected `SCOPE`, `CONTAINER`, and `VOLUME` before uninstalling.

`make qualify-toolbox` verifies the systemd-user service, evaluates the selected toolbox flake, creates a small Nix store output, then confirms a second rootless Podman container can read that output through the same named `/nix` volume. It does not require host Nix and does not expose the host's Podman volume storage path.

## Caller-owned plan qualification

`make qualify-plan` is the generic plan entry point. Make synchronizes a caller-selected checkout to an exact commit, synchronizes its declared source inputs, ensures the versioned toolbox and store exist, and starts a disposable Nix-Alpine runtime. Inside that runtime it invokes the caller's selected flake app. Make never accepts or executes a caller-selected script path. The host adapter exposes the calling user's rootless Podman socket, systemd-user bus, and Quadlet directories needed to exercise the host topology; it has no system-level Podman or systemd access.

The selected flake app accepts the shared plan arguments and interprets the caller-owned module graph. For example:

```bash
make qualify-plan \
  PLAN_REPO=owner/repo PLAN_BRANCH=branch PLAN_REV=<full-commit-sha> \
  PLAN_CHECKOUT=compositions/name \
  PLAN_FILE=path/to/plan.json \
  PLAN_FLAKE=path/to/flake PLAN_TARGET=qualify-plan \
  PLAN_GATE=all GATE=all LOG=1
```

Plans use the versioned module protocol documented in [PLAN_INTERFACE.md](PLAN_INTERFACE.md). The caller owns module behavior, pins, artifacts, assertions, and cleanup. Nix-Alpine owns the generic execution toolchain and host runtime adapter. This target qualifies the selected host Podman/systemd topology; it does not claim to qualify another operating system or a virtual machine.

Plan runs are ephemeral by default. The caller's runner owns its scoped setup and cleanup. Set `RETAIN=1` only when the plan supports retaining its final runtime for inspection. Use generic Make inventory and cleanup targets to inspect or remove host resources:

```bash
make inventory RESOURCE=units|containers|networks|images|volumes|paths
make cleanup RESOURCE=containers PREFIX=<literal-prefix> DRY_RUN=1
make cleanup-run RUN_PREFIX=<printed-run-prefix> DRY_RUN=1
```

Cleanup is preview-first and scoped by explicit resource arguments. Shared Nix stores and reusable images are preserved by run cleanup.

## Qualification logs

Set `LOG=1` on a Make target to stream output and write a timestamped log. Make returns the wrapped command's exit status. Names identify the purpose and scope; `LOG_DIR` and `LOG_NAME` can override the defaults.

## CoreOS/QEMU host adapter

The QEMU adapter is generic infrastructure. The caller supplies the pinned input repository and revision, build flake and target, Butane config and resource directory, composition/account name, and runner image. Nix-Alpine builds the guest artifacts inside its toolbox; Make manages host Podman/systemd/QEMU lifecycle and scoped state. Caller-specific Butane resources, guest services, and expected markers stay in the caller checkout.

```bash
make qualify-coreos-qemu \
  COREOS_INPUT_REPO=owner/repo COREOS_INPUT_BRANCH=branch \
  COREOS_INPUT_REV=<commit> COREOS_INPUT_CHECKOUT=compositions/name \
  COREOS_BUILD_FLAKE=path/to/flake COREOS_BUILD_TARGET='#bootstrap' \
  COREOS_CONFIG_DIR=path/to/config COREOS_RESOURCES=path/to/resources \
  COREOS_CONFIG_NAME=guest.bu COREOS_COMPOSITION_NAME=name \
  COREOS_QEMU_IMAGE=localhost/runner:tag LOG=1
```

SSH/SCP are optional test transports for an already booted guest. They are not production activation dependencies. The same generic guest runner can target a QEMU forwarded port or another SSH endpoint such as a locally opened tunnel.

## Source reset

`make reset-source` operates only on this checkout and defaults to preview. It separates tracked, untracked, and ignored paths. Review the preview before selecting discard flags; it does not clean Podman resources or host state.

## Release and toolchain helpers

Generic component, release-ledger, Go-through-Nix, image-inspection, and workspace synchronization helpers are available through `make help`. They do not assign application-specific pins or claim a component is qualified unless the selected caller flake supplies and passes its own gates.
