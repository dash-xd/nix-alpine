# Qualification plan interface

Nix-Alpine owns the generic execution and host-runtime adapter. A caller supplies an exact source revision, a workspace-relative flake, a plan file, and an app target. The app target is the plan implementation; Make does not invoke a caller-selected shell script.

## Make contract

```sh
make qualify-plan \
  PLAN_REPO=owner/repository \
  PLAN_BRANCH=branch \
  PLAN_REV=<full-commit-sha> \
  PLAN_CHECKOUT=workspace/path \
  PLAN_FILE=path/to/plan.json \
  PLAN_FLAKE=path/to/flake \
  PLAN_TARGET=qualify-plan \
  PLAN_GATE=all
```

Nix-Alpine synchronizes the checkout to `PLAN_REV`, synchronizes any declared source manifest, and invokes `nix run PLAN_FLAKE#PLAN_TARGET` inside the toolbox-backed qualification runtime. The app receives the plan path, selected gate, workspace root, toolbox identity, Nix-Alpine local tools path, scope, and plan checkout. Optional artifact manifests are mounted read-only and passed through unchanged.

The host adapter starts and removes the disposable rootless Podman runtime and exposes the host Podman socket and user systemd bus. Qualification apps use those interfaces to test the host runtime. The shared Nix store belongs to the toolbox volume. A plan must not claim a runtime capability that the selected host adapter does not provide.

## Plan module protocol

A plan uses `schemaVersion: 2` and `protocolVersion: 1`. It declares modules by stable ID. Each module contains:

- `kind`: an executor-supported operation
- `phases`: ordered lifecycle phases such as `prepare`, `execute`, `verify`, and `cleanup`
- `inputs`: the module's declared configuration
- `outputs`: named values or evidence the module produces
- `dependsOn`: module IDs that must complete first
- `cleanup`: a policy describing whether resources are preserved or cleaned up

Each gate lists its entry modules. The plan app resolves dependencies in topological order, rejects unknown modules and cycles, and executes shared dependencies once per plan invocation. A module's cleanup handler owns resources created by that module. `always` cleanup must also be safe after a partial setup or failed assertion.

The module kinds and their input/output contracts belong to the plan implementation in its flake. Nix-Alpine only transports the plan and invokes its selected app; it does not know Fatline, Agni, service names, or gate meanings.
