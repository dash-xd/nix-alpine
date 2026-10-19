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
