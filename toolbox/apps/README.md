Toolbox flake applications package build and qualification tools used by the
host Makefile. Make still owns the entry points and host Git/Podman/systemd
operations. It invokes these apps with `podman exec`; workspace sources and
the scoped CoreOS state directory are shared mounts, so generated Butane
inputs and QEMU artifacts are written directly where the host runtime needs
them.

Applications currently include Astrochicken Butane/resource assembly, the
CoreOS QEMU artifact build and checksum/reuse logic, and Fatline ACL pin
validation. Keep host-side scripts limited to mount/path translation and
Podman/systemd lifecycle operations.
