Toolbox flake applications package build and qualification tools used by the
host Makefile. Make still owns the entry points and host Git/Podman/systemd
operations. It invokes these apps with `podman exec`; workspace sources and
the scoped CoreOS state directory are shared mounts, so generated Butane
inputs and QEMU artifacts are written directly where the host runtime needs
them.

The CoreOS QEMU artifact builder is a generic Nix/flake tool. Caller-owned
qualification profiles and policies belong in their owning infrastructure
repository; Agni currently supplies the Astrochicken profile and Fatline ACL
policy check. Keep application-specific profiles and gate logic out of this
toolbox flake.
