SHELL := /bin/bash
.DEFAULT_GOAL := help
SCOPE ?= dev
CONTAINER := nix-alpine-$(SCOPE)
SERVICE := $(CONTAINER).service
VOLUME := $(CONTAINER)-store
IMAGE ?= localhost/nix-toolbox:latest
WORKSPACES ?= $(HOME)/workspace/nix
FLAKE ?= .
TARGET ?=
ARGS ?=
CMD ?= bash
PROJECTS ?=
REPO ?=
BRANCH ?= main
# Set FORCE=1 to discard tracked local changes before refreshing.
FORCE ?= 0
FLAKE_PATH := $(if $(filter .,$(FLAKE)),/workspaces,$(if $(filter /workspaces%,$(FLAKE)),$(FLAKE),/workspaces/$(FLAKE)))
FLAKE_REF := $(FLAKE_PATH)$(TARGET)

.PHONY: uninstall help bootstrap refresh update sync show-images show-image-layers images image-prune start stop restart status logs shell exec run build develop show check ps inspect store store-info parallel-build
help:
	@echo "make show-image-layers (compare build layers, image IDs, and container references)"
	@echo "make show-images (show active image, tagged image, and normal image inventory)"
	@echo "make image-prune  (remove only dangling unused images)"
	@echo "make sync REPO=dash-xd/agni BRANCH=branch (clone or fast-forward a workspace repository)"
	@echo "make refresh   (fetch origin, fast-forward branch, rebuild and restart; FORCE=1 discards tracked edits)"
	@echo "make update    (alias for refresh)"
	@echo "make uninstall (remove scope resources)"
	@echo "make bootstrap; make run FLAKE=agni TARGET='#app'; make build FLAKE=agni TARGET='#package'"
	@echo "make start|stop|restart|status|logs|shell|show|check|develop|store-info"
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
