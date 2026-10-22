SHELL := /bin/bash
.DEFAULT_GOAL := help
SCOPE ?= dev
CONTAINER := nix-alpine-$(SCOPE)
SERVICE := $(CONTAINER).service
VOLUME := $(CONTAINER)-store
IMAGE ?= localhost/nix.xd:latest
WORKSPACES ?= $(HOME)/workspace/nix
FLAKE ?= .
TARGET ?=
# Image archive is resolved from the selected flake output, never a hard-coded store path.
ARGS ?=
CMD ?= bash
PROJECTS ?=
COMPONENT ?= logma
HASH := \#
RELEASE_VERSION ?=
RELEASE_IMAGE ?=
RELEASE_SOURCE ?= $(WORKSPACES)/$(notdir $(REPO))
RELEASE_FLAKE ?= $(FLAKE_PATH)
RELEASE_TARGET ?= $(HASH)provider-image
RELEASE_GATES ?= $(HASH)qualify $(HASH)qualify-integration
RELEASE_STATE ?= $(HOME)/.local/state/nix-alpine/releases
RELEASE_SOURCE_CONTAINER ?= /workspaces/$(notdir $(REPO))
RELEASE_METADATA_FLAKE ?= /workspaces/nix-alpine/release
RELEASE_IMPORT_RECORD ?= $(RELEASE_STATE)/$(COMPONENT)/$(RELEASE_VERSION).import.json
PACKAGE ?= ./...
TOOLCHAIN_FLAKE ?= nix-alpine/toolbox
TOOLCHAIN_SHELL ?= go
REPO ?=
BRANCH ?= main
FATLINE_REPO ?= dash-xd/agni
FATLINE_BRANCH ?= codex/local-fatline-nix-alpine-bootstrap
FATLINE_FLAKE ?= agni/local/fatline
# Set FORCE=1 to discard tracked local changes before refreshing.
FORCE ?= 0
FLAKE_PATH := $(if $(filter .,$(FLAKE)),/workspaces,$(if $(filter /workspaces%,$(FLAKE)),$(FLAKE),/workspaces/$(FLAKE)))
FLAKE_REF := $(FLAKE_PATH)$(TARGET)

.PHONY: release-lock release-check test-release-integration release-inspect test-release release-import release-metadata version release-candidate release-qualify fatline-compose fatline-images test-workspace-race test-workspace-race-latest self-update test-workspace-latest diagnose-toolbox test-workspace qualify-workspace uninstall help bootstrap refresh update sync show-images show-image-layers images image-prune start stop restart status logs shell exec run build path-info image-load image-inspect develop show check ps inspect store store-info parallel-build
help:
	@echo "make release-lock | release-check (Nix inside local builder only)"
	@echo "make test-release (lightweight host contract; no Nix)"
	@echo "make test-release-integration REPO=owner/repo RELEASE_FLAKE=/workspaces/repo RELEASE_VERSION=... (real local build/import/gates)"
	@echo "make version COMPONENT=logma (next available UTC CalVer in local ledger)"
	@echo "make release-candidate COMPONENT=logma RELEASE_VERSION=... REPO=owner/repo RELEASE_IMAGE=local/image:tag RELEASE_FLAKE=/workspaces/project RELEASE_TARGET='#provider-image'"
	@echo "make release-qualify COMPONENT=logma RELEASE_VERSION=... (runs configured Nix gates; refuses failed qualification)"
	@echo "make show-image-layers (compare build layers, image IDs, and container references)"
	@echo "make show-images (show active image, tagged image, and normal image inventory)"
	@echo "make image-prune  (remove only dangling unused images)"
	@echo "make sync REPO=dash-xd/agni BRANCH=branch (clone or fast-forward a workspace repository)"
	@echo "make fatline-images (sync Agni, build/import Redis and Nginx Nix images; no service activation)"
	@echo "make fatline-compose (sync Agni and build Quadlet composition; no service activation)"
	@echo "make qualify-workspace REPO=dash-xd/agni BRANCH=branch FLAKE=agni/local/fatline COMPONENT=logma"
	@echo "make test-workspace REPO=xd-dash/skymill BRANCH=branch PACKAGE=./httpapi (via pinned TOOLCHAIN_FLAKE#go devShell)"
	@echo "make diagnose-toolbox (inspect Nix shell PATH and Go executable)"
	@echo "make self-update (fast-forward this checkout; no image rebuild)"
	@echo "make test-workspace-race-latest REPO=... BRANCH=... (race detector via Nix)"
	@echo "make REPO=xd-dash/skymill BRANCH=... (isolated Redis integration)"
	@echo "make test-workspace-latest REPO=... BRANCH=... PACKAGE=... (self-update, then test)"
	@echo "make refresh   (fetch origin, fast-forward branch, rebuild and restart; FORCE=1 discards tracked edits)"
	@echo "make update    (alias for refresh)"
	@echo "make uninstall (remove scope resources)"
	@echo "make bootstrap; make run FLAKE=agni TARGET='#app'; make build FLAKE=agni TARGET='#package'"
	@echo "make path-info FLAKE=logma TARGET='#provider-image' (show built Nix store path)"
	@echo "make image-load FLAKE=logma TARGET='#provider-image' (load archive into rootless Podman)"
	@echo "make image-inspect (list rootless Podman image IDs)"
	@echo "make start|stop|restart|status|logs|shell|show|check|develop|store-info"
# Fast-forward source without rebuilding or restarting the container.
self-update:
	@bash ./refresh.sh "$(FORCE)"

# Re-enter Make after updating, so the updated Makefile is loaded.
test-workspace-latest:
	@$(MAKE) self-update FORCE="$(FORCE)"
	@$(MAKE) test-workspace REPO="$(REPO)" BRANCH="$(BRANCH)" PACKAGE="$(PACKAGE)" SCOPE="$(SCOPE)" WORKSPACES="$(WORKSPACES)"

refresh update:
	@bash ./refresh.sh "$(FORCE)"
	$(MAKE) bootstrap SCOPE="$(SCOPE)" WORKSPACES="$(WORKSPACES)"
show-images images:
	@bash ./images.sh inspect "$(CONTAINER)" "$(IMAGE)"
show-image-layers:
	@python3 ./show-image-layers.py "$(CONTAINER)" "$(IMAGE)"
image-prune:
	@bash ./images.sh prune "$(CONTAINER)" "$(IMAGE)"
sync:
	@test -n "$(REPO)" || { echo "Usage: make sync REPO=owner/repo BRANCH=branch"; exit 2; }
	@bash ./sync.sh "$(REPO)" "$(BRANCH)" "$(WORKSPACES)"
# Reuse source synchronization and Nix artifact loading for Fatline's
# infrastructure images. No registry, service installation, or activation.
fatline-images:
	@$(MAKE) sync REPO="$(FATLINE_REPO)" BRANCH="$(FATLINE_BRANCH)" WORKSPACES="$(WORKSPACES)"
	@$(MAKE) build FLAKE="$(FATLINE_FLAKE)" TARGET='#redis-image' SCOPE="$(SCOPE)"
	@$(MAKE) image-load FLAKE="$(FATLINE_FLAKE)" TARGET='#redis-image' SCOPE="$(SCOPE)"
	@$(MAKE) build FLAKE="$(FATLINE_FLAKE)" TARGET='#nginx-image' SCOPE="$(SCOPE)"
	@$(MAKE) image-load FLAKE="$(FATLINE_FLAKE)" TARGET='#nginx-image' SCOPE="$(SCOPE)"
	@$(MAKE) image-inspect SCOPE="$(SCOPE)"

# Build-only composition gate; does not install or activate user services.
fatline-compose:
	@$(MAKE) sync REPO="$(FATLINE_REPO)" BRANCH="$(FATLINE_BRANCH)" WORKSPACES="$(WORKSPACES)"
	@$(MAKE) build FLAKE="$(FATLINE_FLAKE)" TARGET='#fatline' SCOPE="$(SCOPE)"
	@$(MAKE) path-info FLAKE="$(FATLINE_FLAKE)" TARGET='#fatline' SCOPE="$(SCOPE)"

# Sync source, advance one explicitly named component pin, then run the
# flake's build, baseline and integration qualification gates. Keep the
# integration gate's exit status; never reinterpret a nonzero result as green.
qualify-workspace:
	@test -n "$(REPO)" && test -n "$(FLAKE)" && test "$(FLAKE)" != "." && test -n "$(COMPONENT)" || { echo "Usage: make qualify-workspace REPO=owner/repo BRANCH=branch FLAKE=path COMPONENT=logma"; exit 2; }
	@$(MAKE) sync REPO="$(REPO)" BRANCH="$(BRANCH)" WORKSPACES="$(WORKSPACES)"
	@$(MAKE) run FLAKE="$(FLAKE)" TARGET='#advance-pin' ARGS="$(COMPONENT)" SCOPE="$(SCOPE)"
	@$(MAKE) run FLAKE="$(FLAKE)" TARGET='#build' SCOPE="$(SCOPE)"
	@$(MAKE) run FLAKE="$(FLAKE)" TARGET='#qualify' SCOPE="$(SCOPE)"
	@$(MAKE) run FLAKE="$(FLAKE)" TARGET='#qualify-integration' SCOPE="$(SCOPE)"
# Diagnose the actual environment before changing toolbox execution.
diagnose-toolbox:
	@podman exec "$(CONTAINER)" nix --version
	@podman exec "$(CONTAINER)" nix develop "/workspaces/$(TOOLCHAIN_FLAKE)#$(TOOLCHAIN_SHELL)" -c go version

# Run repository Go tests inside Nix-Alpine, never using host Go.
# The repository is synchronized first; no qualification pins are advanced.
test-workspace:
	@test -n "$(REPO)" && test -n "$(PACKAGE)" || { echo "Usage: make test-workspace REPO=owner/repo BRANCH=branch PACKAGE=./httpapi"; exit 2; }
	@$(MAKE) sync REPO="$(REPO)" BRANCH="$(BRANCH)" WORKSPACES="$(WORKSPACES)"
	@podman exec -w "/workspaces/$(notdir $(REPO))" "$(CONTAINER)" nix develop "/workspaces/$(TOOLCHAIN_FLAKE)#$(TOOLCHAIN_SHELL)" -c env GOWORK=off go test -count=1 "$(PACKAGE)"
# Re-enter Make after fast-forward so updated recipes take effect.
test-workspace-race-latest:
	@$(MAKE) self-update FORCE="$(FORCE)"
	@$(MAKE) $(patsubst %-latest,%,$@) REPO="$(REPO)" BRANCH="$(BRANCH)" PACKAGE="$(PACKAGE)" SCOPE="$(SCOPE)" WORKSPACES="$(WORKSPACES)"

test-workspace-race:
	@test -n "$(REPO)" || { echo "REPO is required"; exit 2; }
	@$(MAKE) sync REPO="$(REPO)" BRANCH="$(BRANCH)" WORKSPACES="$(WORKSPACES)"
	@podman exec -w "/workspaces/$(notdir $(REPO))" "$(CONTAINER)" nix develop "/workspaces/$(TOOLCHAIN_FLAKE)#$(TOOLCHAIN_SHELL)" -c env GOWORK=off CGO_ENABLED=1 go test -race -count=1 "$(PACKAGE)"

bootstrap:
	SCOPE="$(SCOPE)" WORKSPACES="$(WORKSPACES)" bash ./bootstrap.sh
uninstall:
	SCOPE="$(SCOPE)" bash ./uninstall.sh
start:
	systemctl --user start "$(SERVICE)"
stop:
	systemctl --user stop "$(SERVICE)"
restart:
	systemctl --user restart "$(SERVICE)"
status:
	systemctl --user --no-pager status "$(SERVICE)"
logs:
	journalctl --user -u "$(SERVICE)" -f
shell:
	podman exec -it "$(CONTAINER)" bash
exec:
	podman exec -it "$(CONTAINER)" $(CMD)
ps:
	podman ps -a --filter "name=^$(CONTAINER)$$"
inspect:
	podman inspect "$(CONTAINER)"
show:
	podman exec "$(CONTAINER)" nix flake show "$(FLAKE_REF)"
check:
	podman exec "$(CONTAINER)" nix flake check "$(FLAKE_REF)"
build:
	podman exec "$(CONTAINER)" nix build --no-link "$(FLAKE_REF)"
path-info:
	podman exec "$(CONTAINER)" nix path-info "$(FLAKE_REF)"
image-load:
	@bash ./image-store.sh "$(CONTAINER)" "$(VOLUME)" "$(FLAKE_REF)"
image-inspect:
	@podman images --no-trunc
run:
	podman exec -it -w "$(FLAKE_PATH)" "$(CONTAINER)" nix run "$(FLAKE_REF)" -- $(ARGS)
develop:
	podman exec -it -w "$(FLAKE_PATH)" "$(CONTAINER)" nix develop "$(FLAKE_REF)" -c bash
store:
	podman volume inspect "$(VOLUME)"
store-info:
	podman exec "$(CONTAINER)" nix store info
parallel-build:
	@test -n "$(PROJECTS)" || { echo "Specify PROJECTS='api worker frontend'"; exit 2; }
	@set -e; pids=(); failed=0; for project in $(PROJECTS); do \
	  podman exec "$(CONTAINER)" nix build --no-link "/workspaces/$$project" & pids+=("$$!"); \
	done; for pid in "$${pids[@]}"; do wait "$$pid" || failed=1; done; exit "$$failed"

# All release state is per-user, per-component and guarded by an exclusive
# file lock. These targets do not activate services or move mutable channels.
version:
	@RELEASE_STATE="$(RELEASE_STATE)" bash ./release-ledger.sh version "$(COMPONENT)"

release-candidate:
	@test -n "$(RELEASE_VERSION)" && test -n "$(REPO)" || { echo "RELEASE_VERSION and REPO are required" >&2; exit 2; }
	@set -euo pipefail; \
	  dir="$(RELEASE_STATE)/$(COMPONENT)"; mkdir -p "$$dir"; \
	  metadata="$$(mktemp "$$dir/.metadata.XXXXXXXX")"; \
	  imported="$$(mktemp "$$dir/.import.XXXXXXXX")"; \
	  trap 'rm -f "$$metadata" "$$imported"' EXIT; \
	  $(MAKE) build FLAKE="$(RELEASE_FLAKE)" TARGET="$(RELEASE_TARGET)" SCOPE="$(SCOPE)"; \
	  podman exec "$(CONTAINER)" nix run "$(RELEASE_METADATA_FLAKE)#release-metadata" -- capture "$(COMPONENT)" "$(RELEASE_VERSION)" "$(RELEASE_SOURCE_CONTAINER)" "$(RELEASE_FLAKE)$(RELEASE_TARGET)" >"$$metadata"; \
	  output="$$(jq -er .nix_output "$$metadata")"; \
	  bash ./release-import.sh "$(CONTAINER)" "$(VOLUME)" "$$output" "$$imported" >/dev/null; \
	  RELEASE_STATE="$(RELEASE_STATE)" bash ./release-ledger.sh candidate "$(COMPONENT)" "$(RELEASE_VERSION)" "$$metadata" "$$imported"

release-qualify:
	@test -n "$(RELEASE_VERSION)" || { echo "RELEASE_VERSION is required" >&2; exit 2; }
	@bash ./release-qualify.sh "$(COMPONENT)" "$(RELEASE_VERSION)" "$(CONTAINER)" "$(RELEASE_STATE)"

# Container-side Nix app. Never accesses the host Podman socket.
release-metadata:
	@test -n "$(REPO)" && test -n "$(RELEASE_VERSION)" || { echo "REPO and RELEASE_VERSION required" >&2; exit 2; }
	@$(MAKE) build FLAKE="$(RELEASE_FLAKE)" TARGET="$(RELEASE_TARGET)" SCOPE="$(SCOPE)"
	@podman exec "$(CONTAINER)" nix run "$(RELEASE_METADATA_FLAKE)#release-metadata" -- capture "$(COMPONENT)" "$(RELEASE_VERSION)" "$(RELEASE_SOURCE_CONTAINER)" "$(RELEASE_FLAKE)$(RELEASE_TARGET)"

# Import an already built, explicitly selected Nix store archive. Host Podman
# is the only image store touched; release-import.sh emits the image ID.
release-import:
	@test -n "$(RELEASE_VERSION)" && test -n "$(REPO)" || { echo "RELEASE_VERSION and REPO required" >&2; exit 2; }
	@output="$$(podman exec "$(CONTAINER)" nix path-info "$(RELEASE_FLAKE)$(RELEASE_TARGET)")"; \
	  bash ./release-import.sh "$(CONTAINER)" "$(VOLUME)" "$$output" "$(RELEASE_IMPORT_RECORD)"

# Contract tests with isolated host Podman facade; full runtime smoke requires the builder.
test-release:
	@bash ./test-release.sh

release-inspect:
	@test -n "$(RELEASE_VERSION)" || { echo "RELEASE_VERSION required" >&2; exit 2; }
	@RELEASE_STATE="$(RELEASE_STATE)" bash ./release-ledger.sh inspect "$(COMPONENT)" "$(RELEASE_VERSION)"

# Explicit local-only Nix release checks. The shared workspace mount ensures
# release/flake.lock is written into the host checkout and can be committed.
release-lock:
	@podman exec -w "$(RELEASE_METADATA_FLAKE)" "$(CONTAINER)" nix flake lock

release-check:
	@test -f "$(WORKSPACES)/nix-alpine/release/flake.lock" || { echo "Run make release-lock and commit release/flake.lock first" >&2; exit 2; }
	@podman exec -w "$(RELEASE_METADATA_FLAKE)" "$(CONTAINER)" nix flake check --no-update-lock-file .
	@podman exec -w "$(RELEASE_METADATA_FLAKE)" "$(CONTAINER)" nix run --no-update-lock-file .#release-metadata -- --help >/dev/null 2>&1; code=$$?; test "$$code" -eq 2

# Deliberately real local integration: no mocks, runner, registry or artifacts.
# Existing candidate/qualified tags are rejected by the ledger.
test-release-integration:
	@test -n "$(REPO)" && test -n "$(RELEASE_VERSION)" || { echo "REPO and RELEASE_VERSION required" >&2; exit 2; }
	@$(MAKE) release-check SCOPE="$(SCOPE)" WORKSPACES="$(WORKSPACES)"
	@$(MAKE) release-candidate REPO="$(REPO)" COMPONENT="$(COMPONENT)" RELEASE_VERSION="$(RELEASE_VERSION)" RELEASE_FLAKE="$(RELEASE_FLAKE)" RELEASE_TARGET="$(RELEASE_TARGET)" SCOPE="$(SCOPE)" RELEASE_STATE="$(RELEASE_STATE)"
	@$(MAKE) release-qualify COMPONENT="$(COMPONENT)" RELEASE_VERSION="$(RELEASE_VERSION)" SCOPE="$(SCOPE)" RELEASE_STATE="$(RELEASE_STATE)"
