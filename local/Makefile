SHELL := /bin/bash
.DEFAULT_GOAL := help
SCOPE ?= dev
CONTAINER := nix-alpine-$(SCOPE)
SERVICE := $(CONTAINER).service
VOLUME := $(CONTAINER)-store
WORKSPACES ?= $(HOME)/workspace/nix
FLAKE ?= .
TARGET ?=
ARGS ?=
CMD ?= bash
PROJECTS ?=
FLAKE_PATH := $(if $(filter .,$(FLAKE)),/workspaces,$(if $(filter /workspaces%,$(FLAKE)),$(FLAKE),/workspaces/$(FLAKE)))
FLAKE_REF := $(FLAKE_PATH)$(TARGET)

.PHONY: help bootstrap start stop restart status logs shell exec run build develop show check ps inspect store store-info parallel-build
help:
	@echo "make bootstrap; make run FLAKE=agni TARGET='#app'; make build FLAKE=agni TARGET='#package'"
	@echo "make start|stop|restart|status|logs|shell|show|check|develop|store-info"
bootstrap:
	SCOPE="$(SCOPE)" WORKSPACES="$(WORKSPACES)" ./bootstrap.sh
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
	podman exec -it "$(CONTAINER)" nix run "$(FLAKE_REF)" -- $(ARGS)
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
