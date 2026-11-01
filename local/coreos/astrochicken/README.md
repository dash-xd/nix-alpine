# Astrochicken CoreOS base case

Astrochicken is the Nix-Alpine controlled Fedora CoreOS/QEMU base case. The
guest's root systemd bootstrap creates one generated `astrochicken-<random>`
service account and starts a persistent rootless Podman container through that
account's systemd user manager and Quadlet. Root is used only to create the
account, enable lingering, and start its user manager. The Nix-Alpine process
and its Podman container run without host root.

The service name is persisted on the CoreOS guest disk, so a guest reboot
reuses the same app account, home, user manager, and Nix store. The optional
console profile creates a separate persisted `local-<random>` shell account;
it can read the service workspace but its interactive sandbox blocks writes
outside its own home workspace.

Set `COREOS_QEMU_CONSOLE_LOGIN=1 COREOS_QEMU_DISPLAY=web` to add a separate
generated `local-<random>` login account for the browser console. The account
has a Bash shell, and its interactive session is started by its user systemd
manager with writes limited to that account's home workspace. The generated
service identity remains nologin. Add `COREOS_QEMU_HOLD=1` to keep the VM and
browser console open after the smoke passes; stop it with
`make clean-coreos-astrochicken` from another terminal.

Run it from `local/` with `make qualify-coreos-astrochicken`. Make uses the
pinned Agni CoreOS image and QEMU runner, but owns the Astrochicken Butane
configuration and guest resources. The default smoke checks that the user
service survives a container restart, the mounted workspace is writable, a
flake in that workspace evaluates, and the named Nix store persists across a
service restart. It does not start a transient guest test service or claim
Fatline application qualification.

The pinned Nix-Alpine source is archived from its clean Git revision and
included in Ignition so the guest can build its toolbox. Additional local
workspace files can be embedded with `COREOS_ASTROCHICKEN_WORKSPACE_FILES`, a
space-separated list of paths relative to `WORKSPACES`. The files are copied
into the guest workspace at the same relative paths and become visible in the
container under `/workspaces`. For example:

```sh
make qualify-coreos-astrochicken \
  COREOS_ASTROCHICKEN_WORKSPACE_FILES="smoke/go.mod smoke/flake.nix" \
  COREOS_QEMU_ACCEL=kvm LOG=1
```

Inputs must be regular files beneath `WORKSPACES`; symlinks and path traversal
are rejected. The resulting Butane and resource bundle is content-hashed by
the existing QEMU artifact builder.

Smoke's `astrochicken-xd-run` remains a distinct named Smoke composition. It
pins and seeds Agni Probe and its other profile tools into a Smoke environment;
this QEMU profile supplies the persistent CoreOS host and workspace where
those tools can be mounted and run later. It does not conflate Probe's
installation profile or Terraform lifecycle with Nix-Alpine's host service.
