SHELL := /bin/bash
.DEFAULT_GOAL := help
SCOPE ?= dev
WORKSPACES ?= $(abspath $(dir $(realpath $(firstword $(MAKEFILE_LIST))))/../..)
NIX_ALPINE_ROOT := $(abspath $(dir $(realpath $(firstword $(MAKEFILE_LIST))))/..)
NIX_ALPINE_SOURCE_REV ?= $(shell git -C "$(NIX_ALPINE_ROOT)" rev-parse --short=12 HEAD 2>/dev/null || echo unknown)
NIX_ALPINE_SOURCE_DATE ?= $(shell git -C "$(NIX_ALPINE_ROOT)" log -1 --format=%cs 2>/dev/null | tr '-' '.')
NIX_ALPINE_VERSION ?= $(if $(NIX_ALPINE_SOURCE_DATE),$(NIX_ALPINE_SOURCE_DATE),unversioned)-$(NIX_ALPINE_SOURCE_REV)
WORKSPACE_KEY ?= $(shell basename "$(WORKSPACES)" | tr '[:upper:]' '[:lower:]' | sed -E 's/[^a-z0-9_-]+/-/g')
CONTAINER ?= nix-alpine-$(NIX_ALPINE_VERSION)-$(WORKSPACE_KEY)-$(NIX_ALPINE_CHECKOUT)-$(SCOPE)
SERVICE ?= $(CONTAINER).service
VOLUME ?= nix-alpine-$(SCOPE)-store
IMAGE ?= localhost/nix-alpine:$(NIX_ALPINE_VERSION)
NIX_ALPINE_HOME ?= $(HOME)/workspace/nix
NIX_ALPINE_STATE_ROOT ?= $(NIX_ALPINE_HOME)/.state/nix-alpine
COMPOSITION_AGNI_SOURCE ?= $(WORKSPACES)/$(COMPOSITION_AGNI_CHECKOUT)
export COMPOSITION_AGNI_SOURCE
FLAKE ?= .
TARGET ?=
# Image archive is resolved from the selected flake output, never a hard-coded store path.
ARGS ?=
CMD ?= bash
PROJECTS ?=
COMPONENT ?= logma
NAME ?=
WITH ?=
COMPOSITIONS ?= $(WORKSPACES)/.compositions
HASH := \#
RELEASE_VERSION ?=
RELEASE_IMAGE ?=
RELEASE_SOURCE ?= $(WORKSPACES)/$(notdir $(REPO))
RELEASE_FLAKE ?= $(FLAKE_PATH)
RELEASE_TARGET ?= $(HASH)provider-image
# Release qualification selects its mandatory gate pair by COMPONENT in release-qualify.sh.
RELEASE_STATE ?= $(NIX_ALPINE_STATE_ROOT)/releases
RELEASE_SOURCE_CONTAINER ?= /workspaces/$(notdir $(REPO))
RELEASE_METADATA_FLAKE ?= /workspaces/nix-alpine/release
RELEASE_IMPORT_RECORD ?= $(RELEASE_STATE)/$(COMPONENT)/$(RELEASE_VERSION).import.json
PACKAGE ?= ./...
CGO ?= 0
TOOLCHAIN_FLAKE ?= nix-alpine/toolbox
TOOLCHAIN_SHELL ?= go
NIX_ALPINE_CHECKOUT ?= $(shell basename "$(NIX_ALPINE_ROOT)" | tr '[:upper:]' '[:lower:]' | sed -E 's/[^a-z0-9_-]+/-/g')
NIX_ALPINE_TOOLBOX_FLAKE ?= /workspaces/$(NIX_ALPINE_CHECKOUT)/toolbox
QUALIFY_FLAKE ?= $(NIX_ALPINE_TOOLBOX_FLAKE)
REPO ?=
BRANCH ?= main
# Shared component pins for local and Actions qualification.
include $(dir $(realpath $(lastword $(MAKEFILE_LIST))))fatline-qualification.sources
COMPOSITION_AGNI_CHECKOUT ?= agni-qualification
SYNC_NAME ?=
FATLINE_AGNI ?= $(WORKSPACES)/agni
QUALIFY_COMPONENT ?= $(COMPONENT)
QUALIFY_IMAGE ?= $(if $(filter nginx,$(QUALIFY_COMPONENT)),localhost/fatline-nginx:candidate,localhost/fatline-redis:candidate)
QUALIFY_SMOKE ?= $(WORKSPACES)/smoke
COMPOSITION_REDIS_IMAGE ?= localhost/nix-alpine/redis:qualified-2026.10.23
COMPOSITION_NGINX_IMAGE ?= localhost/nix-alpine/nginx:qualified-2026.10.23.1
COMPOSITION_LOGMA_IMAGE ?= localhost/logma-provider:candidate
COMPOSITION_SKYMILL_IMAGE ?= localhost/skymill-provider:scoped-qualification

COMPOSITION_SKYMILL_CHECKOUT ?= .qualification-skymill-source

COMPOSITION_LOGMA_CHECKOUT ?= logma-qualification
COMPOSITION_TIMER_STATE_MODE ?= 0
COMPOSITION_STRICT_READINESS_MODE ?= 0
COMPOSITION_PRODUCTION_ACL_MODE ?= 0
COMPOSITION ?= fatline
GATE ?= all
LOG ?= 0
LOG_DIR ?= $(CURDIR)/qualification-logs
LOG_NAME ?= $(if $(filter qualify-plan,$(MAKECMDGOALS)),plan-$(PLAN_CHECKOUT)-$(PLAN_GATE),$(if $(filter qualify-composition,$(MAKECMDGOALS)),fatline-$(GATE),$(firstword $(MAKECMDGOALS))))
QUADLET ?= 0
QUADLET_PROVIDER_ENV = $(if $(filter 1,$(QUADLET)),COMPOSITION_NGINX_QUADLET_MODE=1 COMPOSITION_REDIS_QUADLET_MODE=1 COMPOSITION_QUADLET_MODE=1)
QUALIFY_AGNI ?= $(WORKSPACES)/agni
FATLINE_FLAKE ?= nix-alpine/release/components/nginx
# Set FORCE=1 to discard tracked local changes before refreshing.
FORCE ?= 0

# Composition gates dispatch through shell scripts that invoke nested make.
# Export qualification inputs so every child make uses the caller's scope,
# workspaces, source pins, and toolbox identity.
export SCOPE CONTAINER SERVICE VOLUME WORKSPACES WORKSPACE_KEY NIX_ALPINE_ROOT NIX_ALPINE_SOURCE_REV NIX_ALPINE_SOURCE_DATE NIX_ALPINE_VERSION IMAGE NIX_ALPINE_HOME NIX_ALPINE_STATE_ROOT
export COMPOSITION GATE LOG LOG_DIR LOG_NAME QUADLET
export COMPOSITION_AGNI_BRANCH COMPOSITION_AGNI_REV COMPOSITION_AGNI_CHECKOUT COMPOSITION_AGNI_SOURCE
export COMPOSITION_REDIS_IMAGE COMPOSITION_NGINX_IMAGE COMPOSITION_LOGMA_IMAGE
export COMPOSITION_LOGMA_BRANCH COMPOSITION_LOGMA_REV COMPOSITION_LOGMA_CHECKOUT
export COMPOSITION_SKYMILL_IMAGE COMPOSITION_SKYMILL_BRANCH COMPOSITION_SKYMILL_REV COMPOSITION_SKYMILL_CHECKOUT
export COMPOSITION_TIMER_STATE_MODE COMPOSITION_STRICT_READINESS_MODE COMPOSITION_PRODUCTION_ACL_MODE
FLAKE_PATH := $(if $(filter .,$(FLAKE)),/workspaces,$(if $(filter /workspaces%,$(FLAKE)),$(FLAKE),/workspaces/$(FLAKE)))
FLAKE_REF := $(FLAKE_PATH)$(TARGET)

.PHONY: qualify-plan qualify-composition-skymill-provider qualify-composition-skymill-acl qualify-composition-production-acl test-go test-go-sync qualify qualify-composition-logma-image qualify-composition-acl-isolation qualify-composition-lifecycle-dispatch qualify-composition-baseline qualify-composition-lifecycle-timer-recovery qualify-composition-live-redis-recovery qualify-composition-coordinated-restart qualify-composition-bootstrap-unit qualify-composition-cold-start qualify-composition-all-quadlets qualify-composition-redis-quadlet qualify-composition-quadlet qualify-composition qualify-composition-preflight compose-readiness qualify-process qualify-service compose-show compose-check compose-qualify qualify-component sync-component release-latest release-lock release-check test-release-integration release-inspect test-release release-import release-metadata version release-candidate release-qualify compose fatline-images test-workspace-race test-workspace-race-latest self-update test-workspace-latest diagnose-toolbox test-workspace qualify-workspace uninstall help bootstrap refresh update sync show-images show-image-layers images image-prune start stop restart status logs shell exec run build path-info image-load image-inspect develop show check ps inspect store store-info parallel-build qualify-toolbox qualify-composition-redis-crash-baseline qualify-composition-function-reconciliation qualify-composition-lifecycle-crash qualify-composition-strict-readiness
help:
	@echo "make qualify-coreos-qemu COREOS_QEMU_TRANSIENT_TESTER=0|1 COREOS_QEMU_DISPLAY=headless|web LOG=1 (FCOS/QEMU; Podman under transient systemd)"
	@echo "make qualify-coreos-profile COREOS_PROFILE=name COREOS_PROFILE_BRANCH=branch LOG=1 (caller-owned profile, generic QEMU adapter)"
	@echo "make coreos-qemu-clean COREOS_UNIT=... COREOS_STATE=... (stop a scoped QEMU unit and discard its overlay)"
	@echo "make qualify-coreos-guest-transient COREOS_GUEST_HOST=127.0.0.1 COREOS_GUEST_PORT=PORT COREOS_GUEST_KEY=FILE (GCP/IAP tunnel or another SSH endpoint)"
	@echo "make qualify-deployment (build and inspect generated Agni deployment; no activation)"
	@echo "make qualify-plan PLAN_REPO=owner/repo PLAN_BRANCH=branch PLAN_REV=sha PLAN_CHECKOUT=name PLAN_FILE=path PLAN_RUNNER=path GATE=all (generic plan dispatcher)"
	@echo "make inventory RESOURCE=units|quadlets|containers|networks|images|volumes|paths PREFIX=... PATHS=... PATH_DEPTH=... (read-only)"
	@echo "make cleanup RESOURCE=... PREFIX=... DRY_RUN=1|0 (literal prefix; dry-run by default)"

	@echo "make qualify-composition COMPOSITION=fatline GATE=all|lifecycle-dispatch|timer-recovery|production-acl|strict-readiness LOG=1 (timestamped log + exit code)"
	@echo "make qualify-composition-skymill-provider QUADLET=1 LOG=1 (Skymill against systemd Quadlets; timestamped log)"
	@echo "make qualify-composition COMPOSITION=logma-image (sync, build and import Logma provider image; not release qualification)"
	@echo "make qualify-composition COMPOSITION=skymill-provider (pinned Skymill provider integration)"
	@echo "make qualify-composition (disposable Redis -> Nginx -> Logma runtime integration)"
	@echo "make qualify-composition-preflight (verify Agni Nix topology and immutable local images; no activation)"
	@echo "make qualify-process FLAKE=nix-alpine/release/components/redis (component process gate)"
	@echo "make qualify-service QUALIFY_COMPONENT=redis|logma|skymill|nginx (Smoke-owned runtime gate)"
	@echo "make release-lock | release-check (Nix inside local builder only)"
	@echo "make test-release (lightweight host contract; no Nix)"
	@echo "make release-latest REPO=owner/repo COMPONENT=skymill RELEASE_FLAKE=/workspaces/skymill (auto CalVer + local qualification)"
	@echo "make test-release-integration REPO=owner/repo RELEASE_FLAKE=/workspaces/repo RELEASE_VERSION=... (explicit-version integration)"
	@echo "make version COMPONENT=logma (next available UTC CalVer in local ledger)"
	@echo "make release-candidate COMPONENT=logma RELEASE_VERSION=... REPO=owner/repo RELEASE_IMAGE=local/image:tag RELEASE_FLAKE=/workspaces/project RELEASE_TARGET='#provider-image'"
	@echo "make release-qualify COMPONENT=logma RELEASE_VERSION=... (runs mandatory component gates; refuses failed qualification)"
	@echo "make show-image-layers (compare build layers, image IDs, and container references)"
	@echo "make show-images (show active image, tagged image, and normal image inventory)"
	@echo "make image-prune  (remove only dangling unused images)"
	@echo "make sync REPO=dash-xd/agni BRANCH=branch (clone or fast-forward a workspace repository)"
	@echo "make sync-component REPO=xd-dash/skymill BRANCH=codex/httpapi-durable-delivery (refresh component source)"
	@echo "make qualify-component REPO=xd-dash/skymill BRANCH=codex/httpapi-durable-delivery (sync and run both flake gates)"
	@echo "make fatline-images (build/import Nix-Alpine Redis and Nginx images; no activation)"
	@echo "make compose NAME=fatline WITH=component@version... (Nix app; requires ledger mount; currently fails closed)"
	@echo "make qualify-workspace REPO=dash-xd/agni BRANCH=branch FLAKE=agni/local/fatline COMPONENT=logma"
	@echo "make test-workspace REPO=xd-dash/skymill BRANCH=branch PACKAGE=./httpapi (via pinned TOOLCHAIN_FLAKE#go devShell)"
	@echo "make test-go FLAKE=logma-qualification PACKAGE=./internal/lifecycle (Go via Nix, CGO=0 by default)"
	@echo "make test-go FLAKE=logma-qualification CGO=1 PACKAGE=./... (Nix Go and GCC)"
	@echo "make test-go-sync REPO=xd-dash/logma BRANCH=branch SYNC_NAME=logma-qualification PACKAGE=./..."
	@echo "make diagnose-toolbox (inspect Nix shell PATH and Go executable)"
	@echo "make qualify-toolbox LOG=1 (systemd, Nix flake, and shared rootless Nix store smoke)"
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
	@env -u CONTAINER -u SERVICE -u VOLUME -u IMAGE -u WORKSPACE_KEY -u NIX_ALPINE_ROOT -u NIX_ALPINE_SOURCE_REV -u NIX_ALPINE_SOURCE_DATE -u NIX_ALPINE_VERSION $(MAKE) --no-print-directory bootstrap SCOPE="$(SCOPE)" WORKSPACES="$(WORKSPACES)"
show-images images:
	@bash ./images.sh inspect "$(CONTAINER)" "$(IMAGE)"
show-image-layers:
	@python3 ./show-image-layers.py "$(CONTAINER)" "$(IMAGE)"
image-prune:
	@bash ./images.sh prune "$(CONTAINER)" "$(IMAGE)"
sync:
	@test -n "$(REPO)" || { echo "Usage: make sync REPO=owner/repo BRANCH=branch"; exit 2; }
	@bash ./sync.sh "$(REPO)" "$(BRANCH)" "$(WORKSPACES)" "$(SYNC_NAME)"
# Refresh a component without rebuilding images or modifying release records.
sync-component:
	@test -n "$(REPO)" || { echo "REPO required" >&2; exit 2; }
	@$(MAKE) sync REPO="$(REPO)" BRANCH="$(BRANCH)" WORKSPACES="$(WORKSPACES)"

# Run both component-owned Nix gates after fast-forwarding the workspace.
# Fail on the first unsuccessful gate; no ledger records or image tags touched.
# Runtime gate is disposable and does not install user services.
.PHONY: qualify-deployment-transport
qualify-deployment-transport:
	@$(MAKE) sync REPO=dash-xd/agni BRANCH="$(COMPOSITION_AGNI_BRANCH)" WORKSPACES="$(WORKSPACES)" SYNC_NAME="$(COMPOSITION_AGNI_CHECKOUT)"
	@bash ./qualify-deployment-transport.sh "$(CONTAINER)" "$(COMPOSITION_AGNI_CHECKOUT)" "$(COMPOSITION_REDIS_IMAGE)" "$(COMPOSITION_NGINX_IMAGE)" "$(SCOPE)"

qualify-component:
	@if [[ -n "$(REPO)" ]]; then \
	  $(MAKE) sync-component REPO="$(REPO)" BRANCH="$(BRANCH)" WORKSPACES="$(WORKSPACES)" && \
	  $(MAKE) run FLAKE="$(notdir $(REPO))" TARGET='#qualify' SCOPE="$(SCOPE)" && \
	  $(MAKE) run FLAKE="$(notdir $(REPO))" TARGET='#qualify-integration' SCOPE="$(SCOPE)"; \
	else \
	  case "$(COMPONENT):$(GATE)" in \
	    redis:socket) $(MAKE) qualify-deployment-socket SCOPE="$(SCOPE)" WORKSPACES="$(WORKSPACES)";; \
	    redis:all) $(MAKE) qualify-deployment-socket SCOPE="$(SCOPE)" WORKSPACES="$(WORKSPACES)";; \
	    fatline:deployment) $(MAKE) qualify-deployment SCOPE="$(SCOPE)" WORKSPACES="$(WORKSPACES)";; \
    fatline:transport) $(MAKE) qualify-deployment-transport SCOPE="$(SCOPE)" WORKSPACES="$(WORKSPACES)";; \
    fatline:mixed) $(MAKE) qualify-deployment DEPLOYMENT_OUTPUT=deployment-mixed SCOPE="$(SCOPE)" WORKSPACES="$(WORKSPACES)";; \
    logma:provider) $(MAKE) qualify-composition-baseline SCOPE="$(SCOPE)" WORKSPACES="$(WORKSPACES)";; \
    skymill:provider) $(MAKE) qualify-composition-skymill-provider SCOPE="$(SCOPE)" WORKSPACES="$(WORKSPACES)";; \
	    *) echo "Unsupported component gate: COMPONENT=$(COMPONENT) GATE=$(GATE)" >&2; exit 2;; \
	  esac; \
	fi

# Reuse source synchronization and Nix artifact loading for Fatline's
# infrastructure images. No registry, service installation, or activation.
fatline-images:
	@$(MAKE) build FLAKE=nix-alpine/release/components/redis TARGET='#image' SCOPE="$(SCOPE)"
	@$(MAKE) image-load FLAKE=nix-alpine/release/components/redis TARGET='#image' SCOPE="$(SCOPE)"
	@$(MAKE) build FLAKE="$(FATLINE_FLAKE)" TARGET='#image' SCOPE="$(SCOPE)"
	@$(MAKE) image-load FLAKE="$(FATLINE_FLAKE)" TARGET='#image' SCOPE="$(SCOPE)"
	@$(MAKE) image-inspect SCOPE="$(SCOPE)"

# Container-first composition: Nix app owns release selection and assembly.
# Requires an explicitly mounted read-only release ledger inside nix.xd.
COMPOSE_LEDGER ?= /run/nix-alpine/releases
compose:
	@test -n "$(NAME)" || { echo "NAME required" >&2; exit 2; }
	@podman exec -w /workspaces/nix-alpine/release "$(CONTAINER)" nix run .#compose -- --name "$(NAME)" --with "$(WITH)" --ledger "$(COMPOSE_LEDGER)" --workspace /workspaces

compose-show:
	@podman exec "$(CONTAINER)" cat /workspaces/.compositions/$(NAME)/composition.lock.json

compose-check:
	@$(MAKE) compose NAME="$(NAME)" WITH="" SCOPE="$(SCOPE)" COMPOSE_LEDGER="$(COMPOSE_LEDGER)"

compose-readiness:
	@bash ./compose-readiness.sh "$(RELEASE_STATE)"

compose-qualify:
	@echo "Runtime qualification is not implemented; refusing qualification" >&2
	@exit 1

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

qualify-toolbox:
	@if [[ "$(LOG)" != 0 && "$(LOG)" != 1 ]]; then echo "LOG must be 0 or 1" >&2; exit 2; fi
	@if [[ "$(LOG)" == 1 ]]; then \
	  bash ./logged-run.sh "$(LOG_DIR)" "toolbox-smoke" -- $(MAKE) --no-print-directory qualify-toolbox LOG=0; \
	else \
	  bash ./qualify-toolbox.sh "$(CONTAINER)" "$(SERVICE)" "$(IMAGE)" "$(VOLUME)" "$(WORKSPACES)" "$(QUALIFY_FLAKE)" "$(NIX_ALPINE_VERSION)" "$(NIX_ALPINE_SOURCE_REV)"; \
	fi

# Explicit component gate entrypoints; reuse the existing Nix-Alpine runner.
qualify-process:
	@$(MAKE) run FLAKE="$(FLAKE)" TARGET='#qualify-process' SCOPE="$(SCOPE)"
qualify-service:
	@test -d "$(QUALIFY_SMOKE)" && test -d "$(QUALIFY_AGNI)" || { echo "Smoke and Agni workspaces required" >&2; exit 2; }
	@case "$(QUALIFY_COMPONENT)" in redis|logma|skymill|nginx) ;; *) echo "Unsupported qualification component: $(QUALIFY_COMPONENT)" >&2; exit 2;; esac
	@test -f "$(QUALIFY_SMOKE)/qualification/components/run.sh" || { echo "Smoke's shared component runtime qualification is not implemented; refusing to qualify $(QUALIFY_COMPONENT)" >&2; exit 1; }
	@bash "$(QUALIFY_SMOKE)/qualification/components/run.sh" --component "$(QUALIFY_COMPONENT)" --agni "$(QUALIFY_AGNI)" --builder "$(CONTAINER)" --image "$(QUALIFY_IMAGE)"

# Explicit qualification registry; aliases below remain independently callable.
qualify:
	@case "$(LEVEL)" in composition) $(MAKE) qualify-composition COMPOSITION="$(COMPOSITION)" GATE="$(GATE)";; process) $(MAKE) qualify-process;; service) $(MAKE) qualify-service;; *) echo "LEVEL must be process, service or composition" >&2; exit 2;; esac

PLAN_REPO ?=
PLAN_BRANCH ?= main
PLAN_REV ?=
PLAN_CHECKOUT ?=
PLAN_FILE ?=
PLAN_RUNNER ?=
PLAN_GATE ?= $(GATE)
qualify-plan:
	@test -n "$(PLAN_REPO)" -a -n "$(PLAN_CHECKOUT)" -a -n "$(PLAN_FILE)" -a -n "$(PLAN_RUNNER)" || { echo "Set PLAN_REPO, PLAN_CHECKOUT, PLAN_FILE, and PLAN_RUNNER" >&2; exit 2; }
	@if [[ "$(LOG)" != 0 && "$(LOG)" != 1 ]]; then echo "LOG must be 0 or 1" >&2; exit 2; \
	elif [[ "$(LOG)" == 1 ]]; then \
	  bash ./logged-run.sh "$(LOG_DIR)" "$(LOG_NAME)" -- $(MAKE) --no-print-directory qualify-plan LOG=0 PLAN_REPO="$(PLAN_REPO)" PLAN_BRANCH="$(PLAN_BRANCH)" PLAN_REV="$(PLAN_REV)" PLAN_CHECKOUT="$(PLAN_CHECKOUT)" PLAN_FILE="$(PLAN_FILE)" PLAN_RUNNER="$(PLAN_RUNNER)" PLAN_GATE="$(PLAN_GATE)" SCOPE="$(SCOPE)" CONTAINER="$(CONTAINER)" WORKSPACES="$(WORKSPACES)"; \
	else \
	  $(MAKE) --no-print-directory sync REPO="$(PLAN_REPO)" BRANCH="$(PLAN_BRANCH)" SYNC_NAME="$(PLAN_CHECKOUT)" WORKSPACES="$(WORKSPACES)"; \
	  plan_root="$(WORKSPACES)/$(PLAN_CHECKOUT)"; \
	  if [[ -n "$(PLAN_REV)" ]]; then git -C "$plan_root" rev-parse HEAD | grep -Fx -- "$(PLAN_REV)" >/dev/null || { echo "Plan source revision mismatch" >&2; exit 1; }; fi; \
	  plan_file="$plan_root/$(PLAN_FILE)"; test -f "$plan_file" || { echo "Plan file not found: $plan_file" >&2; exit 2; }; \
		  [[ "$(PLAN_RUNNER)" != /* && "$(PLAN_RUNNER)" != *..* ]] || { echo "PLAN_RUNNER must be a relative path without traversal" >&2; exit 2; }; \
	  runner="$plan_root/$(PLAN_RUNNER)"; test -f "$runner" || { echo "Plan entrypoint is missing: $runner" >&2; exit 2; }; \
	  if ! podman container exists "$(CONTAINER)" || [[ "$(systemctl --user is-active "$(SERVICE)" 2>/dev/null || true)" != active ]]; then $(MAKE) --no-print-directory bootstrap SCOPE="$(SCOPE)" WORKSPACES="$(WORKSPACES)"; fi; \
	  bash "$runner" --plan "$plan_file" --gate "$(PLAN_GATE)" --workspaces "$(WORKSPACES)" --toolbox "$(CONTAINER)" --nix-alpine-local "$(NIX_ALPINE_ROOT)/local" --scope "$(SCOPE)"; \
	fi


# Composition registry dispatches Fatline runtime gates and component image workflows.\n# Component image preparation does not imply release qualification.
qualify-composition:
	@if [[ "$(LOG)" != "0" && "$(LOG)" != "1" ]]; then \
	  echo "LOG must be 0 or 1" >&2; exit 2; \
	elif [[ "$(LOG)" == "1" ]]; then \
	  bash ./logged-run.sh "$(LOG_DIR)" "$(LOG_NAME)" -- $(MAKE) --no-print-directory qualify-composition SCOPE="$(SCOPE)" CONTAINER="$(CONTAINER)" WORKSPACES="$(WORKSPACES)" LOG=0; \
	else \
	  bash ./qualify-composition.sh --composition "$(COMPOSITION)" --gate "$(GATE)" --scope "$(SCOPE)" --container "$(CONTAINER)" --workspaces "$(WORKSPACES)"; \
	fi
qualify-composition-baseline:
	@$(MAKE) sync REPO=dash-xd/agni BRANCH="$(COMPOSITION_AGNI_BRANCH)" WORKSPACES="$(WORKSPACES)" SYNC_NAME="$(COMPOSITION_AGNI_CHECKOUT)"
	@$(MAKE) qualify-composition-preflight SCOPE="$(SCOPE)" WORKSPACES="$(WORKSPACES)" COMPOSITION_AGNI_CHECKOUT="$(COMPOSITION_AGNI_CHECKOUT)"
	@COMPOSITION_AGNI_CHECKOUT="$(COMPOSITION_AGNI_CHECKOUT)" bash ./fatline-composition-runtime.sh "$(CONTAINER)" "$(COMPOSITION_REDIS_IMAGE)" "$(COMPOSITION_NGINX_IMAGE)" "$(COMPOSITION_LOGMA_IMAGE)"

qualify-composition-bootstrap-unit:
	@$(MAKE) sync REPO=dash-xd/agni BRANCH="$(COMPOSITION_AGNI_BRANCH)" WORKSPACES="$(WORKSPACES)" SYNC_NAME="$(COMPOSITION_AGNI_CHECKOUT)"
	@$(MAKE) qualify-composition-preflight SCOPE="$(SCOPE)" WORKSPACES="$(WORKSPACES)" COMPOSITION_AGNI_CHECKOUT="$(COMPOSITION_AGNI_CHECKOUT)"
	@COMPOSITION_BOOTSTRAP_UNIT_MODE=1 COMPOSITION_COLD_START_MODE=1 COMPOSITION_NGINX_QUADLET_MODE=1 COMPOSITION_REDIS_QUADLET_MODE=1 COMPOSITION_QUADLET_MODE=1 COMPOSITION_AGNI_CHECKOUT="$(COMPOSITION_AGNI_CHECKOUT)" bash ./fatline-composition-runtime.sh "$(CONTAINER)" "$(COMPOSITION_REDIS_IMAGE)" "$(COMPOSITION_NGINX_IMAGE)" "$(COMPOSITION_LOGMA_IMAGE)"

qualify-composition-coordinated-restart:
	@$(MAKE) sync REPO=dash-xd/agni BRANCH="$(COMPOSITION_AGNI_BRANCH)" WORKSPACES="$(WORKSPACES)" SYNC_NAME="$(COMPOSITION_AGNI_CHECKOUT)"
	@$(MAKE) qualify-composition-preflight SCOPE="$(SCOPE)" WORKSPACES="$(WORKSPACES)" COMPOSITION_AGNI_CHECKOUT="$(COMPOSITION_AGNI_CHECKOUT)"
	@COMPOSITION_COORDINATED_RESTART_MODE=1 COMPOSITION_BOOTSTRAP_UNIT_MODE=1 COMPOSITION_COLD_START_MODE=1 COMPOSITION_NGINX_QUADLET_MODE=1 COMPOSITION_REDIS_QUADLET_MODE=1 COMPOSITION_QUADLET_MODE=1 COMPOSITION_AGNI_CHECKOUT="$(COMPOSITION_AGNI_CHECKOUT)" bash ./fatline-composition-runtime.sh "$(CONTAINER)" "$(COMPOSITION_REDIS_IMAGE)" "$(COMPOSITION_NGINX_IMAGE)" "$(COMPOSITION_LOGMA_IMAGE)"

qualify-composition-live-redis-recovery:
	@$(MAKE) sync REPO=dash-xd/agni BRANCH="$(COMPOSITION_AGNI_BRANCH)" WORKSPACES="$(WORKSPACES)" SYNC_NAME="$(COMPOSITION_AGNI_CHECKOUT)"
	@$(MAKE) qualify-composition-preflight SCOPE="$(SCOPE)" WORKSPACES="$(WORKSPACES)" COMPOSITION_AGNI_CHECKOUT="$(COMPOSITION_AGNI_CHECKOUT)"
	@COMPOSITION_LIVE_REDIS_RECOVERY_MODE=1 COMPOSITION_COORDINATED_RESTART_MODE=1 COMPOSITION_BOOTSTRAP_UNIT_MODE=1 COMPOSITION_COLD_START_MODE=1 COMPOSITION_NGINX_QUADLET_MODE=1 COMPOSITION_REDIS_QUADLET_MODE=1 COMPOSITION_QUADLET_MODE=1 COMPOSITION_AGNI_CHECKOUT="$(COMPOSITION_AGNI_CHECKOUT)" bash ./fatline-composition-runtime.sh "$(CONTAINER)" "$(COMPOSITION_REDIS_IMAGE)" "$(COMPOSITION_NGINX_IMAGE)" "$(COMPOSITION_LOGMA_IMAGE)"

qualify-composition-redis-crash-baseline:
	@$(MAKE) sync REPO=dash-xd/agni BRANCH="$(COMPOSITION_AGNI_BRANCH)" WORKSPACES="$(WORKSPACES)" SYNC_NAME="$(COMPOSITION_AGNI_CHECKOUT)"
	@$(MAKE) qualify-composition-preflight SCOPE="$(SCOPE)" WORKSPACES="$(WORKSPACES)" COMPOSITION_AGNI_CHECKOUT="$(COMPOSITION_AGNI_CHECKOUT)"
	@COMPOSITION_REDIS_CRASH_BASELINE_MODE=1 COMPOSITION_COORDINATED_RESTART_MODE=1 COMPOSITION_BOOTSTRAP_UNIT_MODE=1 COMPOSITION_COLD_START_MODE=1 COMPOSITION_NGINX_QUADLET_MODE=1 COMPOSITION_REDIS_QUADLET_MODE=1 COMPOSITION_QUADLET_MODE=1 COMPOSITION_AGNI_CHECKOUT="$(COMPOSITION_AGNI_CHECKOUT)" bash ./fatline-composition-runtime.sh "$(CONTAINER)" "$(COMPOSITION_REDIS_IMAGE)" "$(COMPOSITION_NGINX_IMAGE)" "$(COMPOSITION_LOGMA_IMAGE)"

qualify-composition-function-reconciliation:
	@$(MAKE) sync REPO=dash-xd/agni BRANCH="$(COMPOSITION_AGNI_BRANCH)" WORKSPACES="$(WORKSPACES)" SYNC_NAME="$(COMPOSITION_AGNI_CHECKOUT)"
	@$(MAKE) qualify-composition-preflight SCOPE="$(SCOPE)" WORKSPACES="$(WORKSPACES)" COMPOSITION_AGNI_CHECKOUT="$(COMPOSITION_AGNI_CHECKOUT)"
	@COMPOSITION_FUNCTION_RECONCILE_MODE=1 COMPOSITION_REDIS_CRASH_BASELINE_MODE=1 COMPOSITION_COORDINATED_RESTART_MODE=1 COMPOSITION_BOOTSTRAP_UNIT_MODE=1 COMPOSITION_COLD_START_MODE=1 COMPOSITION_NGINX_QUADLET_MODE=1 COMPOSITION_REDIS_QUADLET_MODE=1 COMPOSITION_QUADLET_MODE=1 COMPOSITION_AGNI_CHECKOUT="$(COMPOSITION_AGNI_CHECKOUT)" bash ./fatline-composition-runtime.sh "$(CONTAINER)" "$(COMPOSITION_REDIS_IMAGE)" "$(COMPOSITION_NGINX_IMAGE)" "$(COMPOSITION_LOGMA_IMAGE)"

# Build the actual provider image from the selected Logma source branch.
# Never reuse a stale candidate tag as evidence of newly committed code.
qualify-composition-logma-image:
	@$(MAKE) sync REPO=xd-dash/logma BRANCH="$(COMPOSITION_LOGMA_BRANCH)" WORKSPACES="$(WORKSPACES)" SYNC_NAME="$(COMPOSITION_LOGMA_CHECKOUT)"
	@git -C "$(WORKSPACES)/$(COMPOSITION_LOGMA_CHECKOUT)" rev-parse HEAD | grep -Fx -- "$(COMPOSITION_LOGMA_REV)" >/dev/null || { echo "FAIL: Logma source does not match pinned revision $(COMPOSITION_LOGMA_REV)" >&2; exit 1; }
	@$(MAKE) build FLAKE="$(COMPOSITION_LOGMA_CHECKOUT)" TARGET='#provider-image' SCOPE="$(SCOPE)"
	@$(MAKE) image-load FLAKE="$(COMPOSITION_LOGMA_CHECKOUT)" TARGET='#provider-image' SCOPE="$(SCOPE)"
	@podman image inspect "$(COMPOSITION_LOGMA_IMAGE)" --format 'PASS: loaded Logma provider image {{.Id}}'

qualify-composition-skymill-provider:
	@if [[ "$(LOG)" != "0" && "$(LOG)" != "1" ]]; then \
	  echo "LOG must be 0 or 1" >&2; exit 2; \
	elif [[ "$(LOG)" == "1" ]]; then \
	  bash ./logged-run.sh "$(LOG_DIR)" "$(LOG_NAME)" -- $(MAKE) --no-print-directory qualify-composition-skymill-provider LOG=0; \
	else \
	  $(MAKE) --no-print-directory __qualify-composition-skymill-provider; \
	fi

.PHONY: __qualify-composition-skymill-provider
__qualify-composition-skymill-provider:
	@if [[ "$(QUADLET)" != "0" && "$(QUADLET)" != "1" ]]; then echo "QUADLET must be 0 or 1" >&2; exit 2; fi
	@$(MAKE) sync REPO=xd-dash/skymill BRANCH="$(COMPOSITION_SKYMILL_BRANCH)" WORKSPACES="$(WORKSPACES)" SYNC_NAME="$(COMPOSITION_SKYMILL_CHECKOUT)"
	@git -C "$(WORKSPACES)/$(COMPOSITION_SKYMILL_CHECKOUT)" rev-parse HEAD | grep -Fx -- "$(COMPOSITION_SKYMILL_REV)" >/dev/null || { echo "FAIL: Skymill source does not match pinned revision $(COMPOSITION_SKYMILL_REV)" >&2; exit 1; }
	@$(MAKE) build FLAKE="$(COMPOSITION_SKYMILL_CHECKOUT)" TARGET='#provider-image' SCOPE="$(SCOPE)"
	@$(MAKE) image-load FLAKE="$(COMPOSITION_SKYMILL_CHECKOUT)" TARGET='#provider-image' SCOPE="$(SCOPE)"
	@$(MAKE) sync REPO=dash-xd/agni BRANCH="$(COMPOSITION_AGNI_BRANCH)" WORKSPACES="$(WORKSPACES)" SYNC_NAME="$(COMPOSITION_AGNI_CHECKOUT)"
	@$(MAKE) qualify-composition-preflight SCOPE="$(SCOPE)" WORKSPACES="$(WORKSPACES)" COMPOSITION_AGNI_CHECKOUT="$(COMPOSITION_AGNI_CHECKOUT)"
	@COMPOSITION_SKYMILL_PROVIDER_MODE=1 $(QUADLET_PROVIDER_ENV) COMPOSITION_SKYMILL_IMAGE="$(COMPOSITION_SKYMILL_IMAGE)" COMPOSITION_AGNI_CHECKOUT="$(COMPOSITION_AGNI_CHECKOUT)" bash ./fatline-composition-runtime.sh "$(CONTAINER)" "$(COMPOSITION_REDIS_IMAGE)" "$(COMPOSITION_NGINX_IMAGE)" "$(COMPOSITION_LOGMA_IMAGE)"

qualify-composition-skymill-acl:
	@$(MAKE) sync REPO=dash-xd/agni BRANCH="$(COMPOSITION_AGNI_BRANCH)" WORKSPACES="$(WORKSPACES)" SYNC_NAME="$(COMPOSITION_AGNI_CHECKOUT)"
	@$(MAKE) qualify-composition-preflight SCOPE="$(SCOPE)" WORKSPACES="$(WORKSPACES)" COMPOSITION_AGNI_CHECKOUT="$(COMPOSITION_AGNI_CHECKOUT)"
	@COMPOSITION_AGNI_RECONCILE_MODE="$(COMPOSITION_PRODUCTION_ACL_MODE)" COMPOSITION_SKYMILL_ACL_MODE=1 $(QUADLET_PROVIDER_ENV) COMPOSITION_AGNI_CHECKOUT="$(COMPOSITION_AGNI_CHECKOUT)" bash ./fatline-composition-runtime.sh "$(CONTAINER)" "$(COMPOSITION_REDIS_IMAGE)" "$(COMPOSITION_NGINX_IMAGE)" "$(COMPOSITION_LOGMA_IMAGE)"

qualify-composition-production-acl:
	@$(MAKE) qualify-composition-acl-isolation COMPOSITION_PRODUCTION_ACL_MODE=1 QUADLET=1
	@$(MAKE) qualify-composition-skymill-acl COMPOSITION_PRODUCTION_ACL_MODE=1 QUADLET=1

qualify-composition-acl-isolation:
	@$(MAKE) sync REPO=dash-xd/agni BRANCH="$(COMPOSITION_AGNI_BRANCH)" WORKSPACES="$(WORKSPACES)" SYNC_NAME="$(COMPOSITION_AGNI_CHECKOUT)"
	@$(MAKE) qualify-composition-preflight SCOPE="$(SCOPE)" WORKSPACES="$(WORKSPACES)" COMPOSITION_AGNI_CHECKOUT="$(COMPOSITION_AGNI_CHECKOUT)"
	@if [[ "$(COMPOSITION_PRODUCTION_ACL_MODE)" == 1 ]]; then \
	  podman exec "$(CONTAINER)" nix run --no-write-lock-file "/workspaces/$(COMPOSITION_AGNI_CHECKOUT)/local/fatline#check-acl-pins" -- \
	    "/workspaces/$(COMPOSITION_AGNI_CHECKOUT)/local/fatline/acl-policy.json" "$(COMPOSITION_LOGMA_REV)" "$(COMPOSITION_SKYMILL_REV)"; \
	fi
	@COMPOSITION_AGNI_RECONCILE_MODE="$(COMPOSITION_PRODUCTION_ACL_MODE)" COMPOSITION_ACL_ISOLATION_MODE=1 $(QUADLET_PROVIDER_ENV) COMPOSITION_AGNI_CHECKOUT="$(COMPOSITION_AGNI_CHECKOUT)" bash ./fatline-composition-runtime.sh "$(CONTAINER)" "$(COMPOSITION_REDIS_IMAGE)" "$(COMPOSITION_NGINX_IMAGE)" "$(COMPOSITION_LOGMA_IMAGE)"

qualify-composition-lifecycle-dispatch:
	@$(MAKE) qualify-composition-logma-image
	@$(MAKE) sync REPO=dash-xd/agni BRANCH="$(COMPOSITION_AGNI_BRANCH)" WORKSPACES="$(WORKSPACES)" SYNC_NAME="$(COMPOSITION_AGNI_CHECKOUT)"
	@$(MAKE) qualify-composition-preflight SCOPE="$(SCOPE)" WORKSPACES="$(WORKSPACES)" COMPOSITION_AGNI_CHECKOUT="$(COMPOSITION_AGNI_CHECKOUT)"
	@COMPOSITION_DISPATCH_MODE=1 COMPOSITION_AGNI_CHECKOUT="$(COMPOSITION_AGNI_CHECKOUT)" bash ./fatline-composition-runtime.sh "$(CONTAINER)" "$(COMPOSITION_REDIS_IMAGE)" "$(COMPOSITION_NGINX_IMAGE)" "$(COMPOSITION_LOGMA_IMAGE)"

qualify-composition-lifecycle-timer-recovery:
	@$(MAKE) qualify-composition-logma-image
	@$(MAKE) qualify-composition-lifecycle-crash COMPOSITION_TIMER_STATE_MODE=1

qualify-composition-crash-window:
	@$(MAKE) qualify-composition-lifecycle-crash COMPOSITION_CRASH_WINDOW_MODE=1

qualify-composition-strict-readiness:
	@$(MAKE) qualify-composition-lifecycle-crash COMPOSITION_CRASH_WINDOW_MODE=1 COMPOSITION_STRICT_READINESS_MODE=1

qualify-composition-lifecycle-crash:
	@$(MAKE) sync REPO=dash-xd/agni BRANCH="$(COMPOSITION_AGNI_BRANCH)" WORKSPACES="$(WORKSPACES)" SYNC_NAME="$(COMPOSITION_AGNI_CHECKOUT)"
	@$(MAKE) qualify-composition-preflight SCOPE="$(SCOPE)" WORKSPACES="$(WORKSPACES)" COMPOSITION_AGNI_CHECKOUT="$(COMPOSITION_AGNI_CHECKOUT)"
	@COMPOSITION_CRASH_WINDOW_MODE="$(COMPOSITION_CRASH_WINDOW_MODE)" COMPOSITION_TIMER_STATE_MODE="$(COMPOSITION_TIMER_STATE_MODE)" COMPOSITION_STRICT_READINESS_MODE="$(COMPOSITION_STRICT_READINESS_MODE)" COMPOSITION_LIFECYCLE_CRASH_MODE=1 COMPOSITION_FUNCTION_RECONCILE_MODE=1 COMPOSITION_REDIS_CRASH_BASELINE_MODE=1 COMPOSITION_COORDINATED_RESTART_MODE=1 COMPOSITION_BOOTSTRAP_UNIT_MODE=1 COMPOSITION_COLD_START_MODE=1 COMPOSITION_NGINX_QUADLET_MODE=1 COMPOSITION_REDIS_QUADLET_MODE=1 COMPOSITION_QUADLET_MODE=1 COMPOSITION_AGNI_CHECKOUT="$(COMPOSITION_AGNI_CHECKOUT)" bash ./fatline-composition-runtime.sh "$(CONTAINER)" "$(COMPOSITION_REDIS_IMAGE)" "$(COMPOSITION_NGINX_IMAGE)" "$(COMPOSITION_LOGMA_IMAGE)"

qualify-composition-cold-start:
	@$(MAKE) sync REPO=dash-xd/agni BRANCH="$(COMPOSITION_AGNI_BRANCH)" WORKSPACES="$(WORKSPACES)" SYNC_NAME="$(COMPOSITION_AGNI_CHECKOUT)"
	@$(MAKE) qualify-composition-preflight SCOPE="$(SCOPE)" WORKSPACES="$(WORKSPACES)" COMPOSITION_AGNI_CHECKOUT="$(COMPOSITION_AGNI_CHECKOUT)"
	@COMPOSITION_COLD_START_MODE=1 COMPOSITION_NGINX_QUADLET_MODE=1 COMPOSITION_REDIS_QUADLET_MODE=1 COMPOSITION_QUADLET_MODE=1 COMPOSITION_AGNI_CHECKOUT="$(COMPOSITION_AGNI_CHECKOUT)" bash ./fatline-composition-runtime.sh "$(CONTAINER)" "$(COMPOSITION_REDIS_IMAGE)" "$(COMPOSITION_NGINX_IMAGE)" "$(COMPOSITION_LOGMA_IMAGE)"

qualify-composition-all-quadlets:
	@$(MAKE) sync REPO=dash-xd/agni BRANCH="$(COMPOSITION_AGNI_BRANCH)" WORKSPACES="$(WORKSPACES)" SYNC_NAME="$(COMPOSITION_AGNI_CHECKOUT)"
	@$(MAKE) qualify-composition-preflight SCOPE="$(SCOPE)" WORKSPACES="$(WORKSPACES)" COMPOSITION_AGNI_CHECKOUT="$(COMPOSITION_AGNI_CHECKOUT)"
	@COMPOSITION_NGINX_QUADLET_MODE=1 COMPOSITION_REDIS_QUADLET_MODE=1 COMPOSITION_QUADLET_MODE=1 COMPOSITION_AGNI_CHECKOUT="$(COMPOSITION_AGNI_CHECKOUT)" bash ./fatline-composition-runtime.sh "$(CONTAINER)" "$(COMPOSITION_REDIS_IMAGE)" "$(COMPOSITION_NGINX_IMAGE)" "$(COMPOSITION_LOGMA_IMAGE)"

qualify-composition-redis-quadlet:
	@$(MAKE) sync REPO=dash-xd/agni BRANCH="$(COMPOSITION_AGNI_BRANCH)" WORKSPACES="$(WORKSPACES)" SYNC_NAME="$(COMPOSITION_AGNI_CHECKOUT)"
	@$(MAKE) qualify-composition-preflight SCOPE="$(SCOPE)" WORKSPACES="$(WORKSPACES)" COMPOSITION_AGNI_CHECKOUT="$(COMPOSITION_AGNI_CHECKOUT)"
	@COMPOSITION_REDIS_QUADLET_MODE=1 COMPOSITION_QUADLET_MODE=1 COMPOSITION_AGNI_CHECKOUT="$(COMPOSITION_AGNI_CHECKOUT)" bash ./fatline-composition-runtime.sh "$(CONTAINER)" "$(COMPOSITION_REDIS_IMAGE)" "$(COMPOSITION_NGINX_IMAGE)" "$(COMPOSITION_LOGMA_IMAGE)"

qualify-composition-quadlet:
	@$(MAKE) sync REPO=dash-xd/agni BRANCH="$(COMPOSITION_AGNI_BRANCH)" WORKSPACES="$(WORKSPACES)" SYNC_NAME="$(COMPOSITION_AGNI_CHECKOUT)"
	@$(MAKE) qualify-composition-preflight SCOPE="$(SCOPE)" WORKSPACES="$(WORKSPACES)" COMPOSITION_AGNI_CHECKOUT="$(COMPOSITION_AGNI_CHECKOUT)"
	@COMPOSITION_QUADLET_MODE=1 COMPOSITION_AGNI_CHECKOUT="$(COMPOSITION_AGNI_CHECKOUT)" bash ./fatline-composition-runtime.sh "$(CONTAINER)" "$(COMPOSITION_REDIS_IMAGE)" "$(COMPOSITION_NGINX_IMAGE)" "$(COMPOSITION_LOGMA_IMAGE)"

# Preflight only: Nix-Alpine builds the Agni composition, host verifies its
# topology and local image identities. No containers or release tags changed.
qualify-composition-preflight:
	@git -C "$(WORKSPACES)/$(COMPOSITION_AGNI_CHECKOUT)" rev-parse HEAD | grep -Fx -- "$(COMPOSITION_AGNI_REV)" >/dev/null || { echo "FAIL: Agni source does not match pinned revision $(COMPOSITION_AGNI_REV)" >&2; exit 1; }
	@COMPOSITION_AGNI_CHECKOUT="$(COMPOSITION_AGNI_CHECKOUT)" bash ./fatline-composition-preflight.sh "$(CONTAINER)" "$(COMPOSITION_REDIS_IMAGE)" "$(COMPOSITION_NGINX_IMAGE)" "$(COMPOSITION_LOGMA_IMAGE)"

# Run Go tests in any mounted workspace, without host Go or a repository check output.
# CGO=0 is the lightweight default; CGO=1 requires a compiler in the selected devShell.
# The Nix shell installs tools into PATH only for this command.
test-go:
	@test -f "$(WORKSPACES)/$(FLAKE)/go.mod" || { echo "Go module not found: $(WORKSPACES)/$(FLAKE)/go.mod (set FLAKE=workspace/path)" >&2; exit 2; }
	@case "$(CGO)" in 0|1) ;; *) echo "CGO must be 0 or 1" >&2; exit 2;; esac
	@podman exec -w "$(FLAKE_PATH)" -e CGO_ENABLED="$(CGO)" -e GOWORK=off "$(CONTAINER)" \
		nix develop --no-write-lock-file "/workspaces/$(TOOLCHAIN_FLAKE)#$(TOOLCHAIN_SHELL)" -c \
		go test -count=1 $(PACKAGE) $(ARGS)

test-go-sync:
	@test -n "$(REPO)" || { echo "REPO required" >&2; exit 2; }
	@$(MAKE) sync REPO="$(REPO)" BRANCH="$(BRANCH)" SYNC_NAME="$(SYNC_NAME)" WORKSPACES="$(WORKSPACES)"
	@$(MAKE) test-go FLAKE="$(if $(SYNC_NAME),$(SYNC_NAME),$(notdir $(REPO)))" PACKAGE="$(PACKAGE)" CGO="$(CGO)" ARGS="$(ARGS)" SCOPE="$(SCOPE)" WORKSPACES="$(WORKSPACES)"

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
	SCOPE="$(SCOPE)" WORKSPACES="$(WORKSPACES)" WORKSPACE_KEY="$(WORKSPACE_KEY)" NIX_ALPINE_ROOT="$(NIX_ALPINE_ROOT)" NIX_ALPINE_CHECKOUT="$(NIX_ALPINE_CHECKOUT)" NIX_ALPINE_SOURCE_REV="$(NIX_ALPINE_SOURCE_REV)" NIX_ALPINE_SOURCE_DATE="$(NIX_ALPINE_SOURCE_DATE)" NIX_ALPINE_VERSION="$(NIX_ALPINE_VERSION)" CONTAINER="$(CONTAINER)" SERVICE="$(SERVICE)" VOLUME="$(VOLUME)" IMAGE="$(IMAGE)" RELEASE_STATE="$(RELEASE_STATE)" STATE_ROOT="$(COREOS_STATE_ROOT)" bash ./bootstrap.sh
uninstall:
	SCOPE="$(SCOPE)" CONTAINER="$(CONTAINER)" SERVICE="$(SERVICE)" VOLUME="$(VOLUME)" IMAGE="$(IMAGE)" bash ./uninstall.sh
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
	podman exec "$(CONTAINER)" nix flake show --no-write-lock-file "$(FLAKE_REF)"
check:
	podman exec "$(CONTAINER)" nix flake check --no-write-lock-file "$(FLAKE_REF)"
build:
	podman exec "$(CONTAINER)" nix build --no-write-lock-file --no-link "$(FLAKE_REF)"
path-info:
	podman exec "$(CONTAINER)" nix path-info --no-write-lock-file "$(FLAKE_REF)"
image-load:
	@bash ./image-store.sh "$(CONTAINER)" "$(VOLUME)" "$(FLAKE_REF)"
image-inspect:
	@podman images --no-trunc
run:
	podman exec -it -w "$(FLAKE_PATH)" "$(CONTAINER)" nix run --no-write-lock-file "$(FLAKE_REF)" -- $(ARGS)
develop:
	podman exec -it -w "$(FLAKE_PATH)" "$(CONTAINER)" nix develop --no-write-lock-file "$(FLAKE_REF)" -c bash
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
	@test -n "$(REPO)" && test -n "$(RELEASE_VERSION)" && test "$(RELEASE_FLAKE)" != "/workspaces" && test "$(RELEASE_FLAKE)" != "." || { echo "REPO, RELEASE_VERSION, and explicit RELEASE_FLAKE=/workspaces/repo required" >&2; exit 2; }
	@$(MAKE) release-check SCOPE="$(SCOPE)" WORKSPACES="$(WORKSPACES)"
	@$(MAKE) release-candidate REPO="$(REPO)" COMPONENT="$(COMPONENT)" RELEASE_VERSION="$(RELEASE_VERSION)" RELEASE_FLAKE="$(RELEASE_FLAKE)" RELEASE_TARGET="$(RELEASE_TARGET)" SCOPE="$(SCOPE)" RELEASE_STATE="$(RELEASE_STATE)"
	@$(MAKE) release-qualify COMPONENT="$(COMPONENT)" RELEASE_VERSION="$(RELEASE_VERSION)" SCOPE="$(SCOPE)" RELEASE_STATE="$(RELEASE_STATE)"

# Select one available UTC CalVer from the existing per-component ledger,
# then pass it to the explicit-version integration target. The ledger itself
# rejects collisions; never retry with a new version after a failed release.
release-latest:
	@test -n "$(REPO)" && test -n "$(COMPONENT)" && test "$(RELEASE_FLAKE)" != "/workspaces" && test "$(RELEASE_FLAKE)" != "." || { echo "REPO, COMPONENT and explicit RELEASE_FLAKE=/workspaces/repo required" >&2; exit 2; }
	@set -euo pipefail; \
	  version="$$(RELEASE_STATE="$(RELEASE_STATE)" bash ./release-ledger.sh version "$(COMPONENT)")"; \
	  echo "Releasing $(COMPONENT) as $$version"; \
	  $(MAKE) test-release-integration REPO="$(REPO)" COMPONENT="$(COMPONENT)" RELEASE_FLAKE="$(RELEASE_FLAKE)" RELEASE_TARGET="$(RELEASE_TARGET)" RELEASE_VERSION="$$version" SCOPE="$(SCOPE)" WORKSPACES="$(WORKSPACES)" RELEASE_STATE="$(RELEASE_STATE)"

# Non-activating validation of the generated Agni deployment artifact.
.PHONY: qualify-deployment
qualify-deployment:
	@$(MAKE) sync REPO=dash-xd/agni BRANCH="$(COMPOSITION_AGNI_BRANCH)" WORKSPACES="$(WORKSPACES)" SYNC_NAME="$(COMPOSITION_AGNI_CHECKOUT)"
	@$(MAKE) build FLAKE="$(COMPOSITION_AGNI_CHECKOUT)/local/fatline" TARGET='#deployment' SCOPE="$(SCOPE)"
	@bash ./qualify-deployment.sh "$(CONTAINER)" "$(COMPOSITION_AGNI_CHECKOUT)"

# Disposable rootless Redis UID/socket and ACL qualification; no host unit changes.
.PHONY: qualify-deployment-socket
qualify-deployment-socket:
	@$(MAKE) qualify-deployment SCOPE="$(SCOPE)" WORKSPACES="$(WORKSPACES)"
	@bash ./qualify-deployment-socket.sh "$(CONTAINER)" "$(COMPOSITION_AGNI_CHECKOUT)" "$(COMPOSITION_REDIS_IMAGE)"

# Generic host resource inspection and scoped cleanup. Prefix matching is literal;
# cleanup requires a prefix and defaults to a dry run.
RESOURCE ?= containers
PREFIX ?=
PATHS ?=
PATH_DEPTH ?= 2
DRY_RUN ?= 1
.PHONY: inventory cleanup
inventory:
	@bash ./resource-lifecycle.sh inspect "$(RESOURCE)" "$(PREFIX)" 1 "$(PATHS)" "$(PATH_DEPTH)"
cleanup:
	@bash ./resource-lifecycle.sh cleanup "$(RESOURCE)" "$(PREFIX)" "$(DRY_RUN)"

# Archive parity between local qualification and disposable CI runners.
# Archive paths contain only compressed image transports and a verified manifest.
CI_ARCHIVE_DIR ?= $(CURDIR)/.ci-image-archives
CI_IMAGES ?= $(COMPOSITION_REDIS_IMAGE) $(COMPOSITION_NGINX_IMAGE) $(COMPOSITION_LOGMA_IMAGE) $(COMPOSITION_SKYMILL_IMAGE)
.PHONY: ci-archive-export ci-archive-import
ci-archive-export:
	@bash ./ci-image-archives.sh export "$(CI_ARCHIVE_DIR)" $(CI_IMAGES)
ci-archive-import:
	@bash ./ci-image-archives.sh import "$(CI_ARCHIVE_DIR)" $(CI_IMAGES)


# Fedora CoreOS QEMU qualification is built in Nix-Alpine and supervised by
# a host systemd-user transient unit. Workspace Butane config/resources are
# explicit, hashed Nix inputs; guest checks root bootstrap and optional
# generated-user rootless Podman under systemd.
COREOS_MAKE ?= make
COREOS_CONFIG_DIR ?=
COREOS_RESOURCES ?=
COREOS_STATE ?= $(NIX_ALPINE_STATE_ROOT)/coreos-qemu/$(SCOPE)
COREOS_STATE_ROOT ?= $(NIX_ALPINE_STATE_ROOT)/coreos-qemu
COREOS_UNIT ?= coreos-qemu-$(SCOPE)
# Guest bootstrap permits up to 35 minutes; leave boot and result-reporting margin.
COREOS_QEMU_TIMEOUT ?= 2400
COREOS_QEMU_RAM_MB ?= 3072
COREOS_QEMU_CPUS ?= 2
COREOS_QEMU_ACCEL ?= auto
COREOS_QEMU_IMAGE ?= localhost/agni-coreos-qemu-runner:44.20261012.3.1
COREOS_QEMU_DISPLAY ?= headless
COREOS_QEMU_WEB_PORT ?= 8006
COREOS_QEMU_CONSOLE_LOGIN ?= 0
COREOS_QEMU_HOLD ?= 0
COREOS_QEMU_TRANSIENT_TESTER ?= 0
COREOS_QEMU_SSH_PORT ?= 2222
COREOS_COMPOSITION_NAME ?=
COREOS_QEMU_EXPECT_MARKER ?=
COREOS_CONFIG_NAME ?=
COREOS_REUSE ?= 1
export COREOS_CONFIG_DIR COREOS_RESOURCES COREOS_CONFIG_NAME COREOS_STATE COREOS_STATE_ROOT COREOS_UNIT COREOS_QEMU_TIMEOUT COREOS_QEMU_RAM_MB COREOS_QEMU_CPUS COREOS_QEMU_ACCEL COREOS_QEMU_IMAGE COREOS_QEMU_DISPLAY COREOS_QEMU_WEB_PORT COREOS_QEMU_CONSOLE_LOGIN COREOS_QEMU_HOLD COREOS_QEMU_TRANSIENT_TESTER COREOS_QEMU_SSH_PORT COREOS_COMPOSITION_NAME COREOS_QEMU_EXPECT_MARKER COREOS_REUSE COREOS_TEST_SSH_PUBLIC_KEY

# The same transient guest harness is used against QEMU's forwarded SSH port
# and a GCP/IAP local tunnel. SSH is test transport only; it is never in the
# guest's production activation dependencies.
COREOS_GUEST_HOST ?=
COREOS_GUEST_PORT ?= 22
COREOS_GUEST_KEY ?=
COREOS_GUEST_SSH_USER ?= core
COREOS_GUEST_COMPOSITION ?= $(COREOS_COMPOSITION_NAME)
COREOS_GUEST_RUNTIME ?= 10m
COREOS_GUEST_PAYLOAD ?= ./coreos-guest-transient-smoke.sh
export COREOS_GUEST_SSH_USER

# A qualification profile is owned by its caller (currently Agni). This Make
# target only stages the selected profile and supervises the generic QEMU host
# adapter.
COREOS_PROFILE ?=
COREOS_PROFILE_BRANCH ?=
COREOS_PROFILE_REV ?=
COREOS_PROFILE_CHECKOUT ?= agni-profile
COREOS_PROFILE_OUTPUT ?= $(WORKSPACES)/.coreos-profiles/$(COREOS_PROFILE)/$(SCOPE)
COREOS_PROFILE_STATE ?= $(NIX_ALPINE_STATE_ROOT)/coreos-qemu/$(COREOS_PROFILE)/$(SCOPE)
COREOS_PROFILE_UNIT ?= coreos-qemu-$(COREOS_PROFILE)-$(SCOPE)
COREOS_PROFILE_WORKSPACE_FILES ?=
COREOS_PROFILE_CONSOLE_LOGIN ?=
export COREOS_PROFILE_WORKSPACE_FILES COREOS_PROFILE_CONSOLE_LOGIN

.PHONY: qualify-coreos-qemu qualify-coreos-profile qualify-coreos-guest-transient coreos-qemu-build coreos-qemu-clean coreos-qemu-host-preflight ensure-coreos-state-mount
qualify-coreos-qemu:
	@if [[ "$(LOG)" != 0 && "$(LOG)" != 1 ]]; then echo "LOG must be 0 or 1" >&2; exit 2; fi
	@if [[ -z "$(COREOS_CONFIG_DIR)" || -z "$(COREOS_RESOURCES)" || -z "$(COREOS_CONFIG_NAME)" || -z "$(COREOS_COMPOSITION_NAME)" ]]; then echo "Set the profile inputs through qualify-coreos-profile or provide COREOS_CONFIG_DIR, COREOS_RESOURCES, COREOS_CONFIG_NAME, and COREOS_COMPOSITION_NAME" >&2; exit 2; fi
	@if [[ "$(COREOS_QEMU_DISPLAY)" != headless && "$(COREOS_QEMU_DISPLAY)" != web ]]; then echo "COREOS_QEMU_DISPLAY must be headless or web" >&2; exit 2; fi
	@if [[ "$(COREOS_QEMU_CONSOLE_LOGIN)" != 0 && "$(COREOS_QEMU_CONSOLE_LOGIN)" != 1 ]]; then echo "COREOS_QEMU_CONSOLE_LOGIN must be 0 or 1" >&2; exit 2; fi
	@if ! [[ "$(COREOS_COMPOSITION_NAME)" =~ ^[a-z_][a-z0-9_-]{0,18}$$ ]]; then echo "COREOS_COMPOSITION_NAME must be a lowercase system-account prefix of at most 19 characters" >&2; exit 2; fi
	@if [[ "$(COREOS_QEMU_CONSOLE_LOGIN)" == 1 && "$(COREOS_QEMU_DISPLAY)" != web ]]; then echo "COREOS_QEMU_CONSOLE_LOGIN=1 requires COREOS_QEMU_DISPLAY=web" >&2; exit 2; fi
	@if [[ "$(COREOS_QEMU_HOLD)" != 0 && "$(COREOS_QEMU_HOLD)" != 1 ]]; then echo "COREOS_QEMU_HOLD must be 0 or 1" >&2; exit 2; fi
	@if [[ "$(COREOS_QEMU_TRANSIENT_TESTER)" != 0 && "$(COREOS_QEMU_TRANSIENT_TESTER)" != 1 ]]; then echo "COREOS_QEMU_TRANSIENT_TESTER must be 0 or 1" >&2; exit 2; fi
	@if [[ "$(COREOS_QEMU_TRANSIENT_TESTER)" == 1 ]]; then \
	  case "$(COREOS_QEMU_SSH_PORT)" in ''|*[!0-9]*) echo "COREOS_QEMU_SSH_PORT must be numeric" >&2; exit 2;; esac; \
	  ssh_port_num=$$((10#$(COREOS_QEMU_SSH_PORT))); \
	  if (( ssh_port_num < 1024 || ssh_port_num > 65535 )); then echo "COREOS_QEMU_SSH_PORT must be between 1024 and 65535" >&2; exit 2; fi; \
	fi
	@if [[ "$(COREOS_QEMU_HOLD)" == 1 && "$(COREOS_QEMU_CONSOLE_LOGIN)" != 1 && "$(COREOS_QEMU_TRANSIENT_TESTER)" != 1 ]]; then echo "COREOS_QEMU_HOLD=1 requires a console login or transient tester profile" >&2; exit 2; fi
	@if [[ "$(COREOS_QEMU_DISPLAY)" == web ]]; then \
	  case "$(COREOS_QEMU_WEB_PORT)" in ''|*[!0-9]*) echo "COREOS_QEMU_WEB_PORT must be numeric" >&2; exit 2;; esac; \
	  web_port_num=$$((10#$(COREOS_QEMU_WEB_PORT))); \
	  if (( web_port_num < 1024 || web_port_num > 65535 )); then echo "COREOS_QEMU_WEB_PORT must be between 1024 and 65535" >&2; exit 2; fi; \
	fi
	@if [[ "$(LOG)" == 1 ]]; then \
	  bash ./logged-run.sh "$(LOG_DIR)" "coreos-qemu" -- $(COREOS_MAKE) --no-print-directory qualify-coreos-qemu LOG=0; \
	else \
	  set -Eeuo pipefail; \
	  $(COREOS_MAKE) ensure-coreos-state-mount; \
	  $(COREOS_MAKE) coreos-qemu-host-preflight; \
	  $(COREOS_MAKE) sync REPO=dash-xd/agni BRANCH="$(COMPOSITION_AGNI_BRANCH)" WORKSPACES="$(WORKSPACES)" SYNC_NAME="$(COMPOSITION_AGNI_CHECKOUT)"; \
	  git -C "$(WORKSPACES)/$(COMPOSITION_AGNI_CHECKOUT)" rev-parse HEAD | grep -Fx -- "$(COMPOSITION_AGNI_REV)" >/dev/null || { echo "Agni source does not match pinned QEMU revision $(COMPOSITION_AGNI_REV)" >&2; exit 1; }; \
	  if [[ "$(COREOS_QEMU_TRANSIENT_TESTER)" == 1 ]]; then \
	    bash ./coreos-qemu-transient-qualify.sh "$(COREOS_MAKE)" "$(CONTAINER)" "$(WORKSPACES)" "$(COMPOSITION_AGNI_CHECKOUT)" "$(COMPOSITION_AGNI_REV)" "$(COREOS_STATE)" "$(COREOS_UNIT)" "$(COREOS_QEMU_TIMEOUT)" "$(COREOS_QEMU_RAM_MB)" "$(COREOS_QEMU_CPUS)" "$(COREOS_QEMU_ACCEL)" "$(COREOS_QEMU_IMAGE)" "$(COREOS_QEMU_DISPLAY)" "$(COREOS_QEMU_WEB_PORT)" "$(COREOS_QEMU_HOLD)" "$(COREOS_QEMU_SSH_PORT)" "$(COREOS_COMPOSITION_NAME)"; \
	  else \
	    $(COREOS_MAKE) coreos-qemu-build; \
	    $(COREOS_MAKE) build FLAKE="$(COMPOSITION_AGNI_CHECKOUT)/qemu/coreos-live/local" TARGET='#qemuRunner'; \
	    $(COREOS_MAKE) image-load FLAKE="$(COMPOSITION_AGNI_CHECKOUT)/qemu/coreos-live/local" TARGET='#qemuRunner'; \
	    bash ./coreos-qemu-qualify.sh "$(COREOS_UNIT)" "$(COREOS_STATE)" "$(COREOS_QEMU_TIMEOUT)" "$(COREOS_QEMU_RAM_MB)" "$(COREOS_QEMU_CPUS)" "$(COREOS_QEMU_ACCEL)" "$(COREOS_QEMU_IMAGE)" "$(COREOS_QEMU_DISPLAY)" "$(COREOS_QEMU_WEB_PORT)" "$(COREOS_QEMU_HOLD)" "$(COREOS_QEMU_SSH_PORT)" "$(COREOS_TEST_SSH_PUBLIC_KEY)" "$(COREOS_COMPOSITION_NAME)" "$(COREOS_QEMU_TRANSIENT_TESTER)" "$(COREOS_QEMU_EXPECT_MARKER)"; \
	  fi; \
	fi

qualify-coreos-guest-transient:
	@if [[ -z "$(COREOS_GUEST_HOST)" || -z "$(COREOS_GUEST_KEY)" ]]; then echo "Set COREOS_GUEST_HOST and COREOS_GUEST_KEY (for GCP, point HOST/PORT at the local IAP tunnel)" >&2; exit 2; fi
	@for command in ssh scp; do command -v "$$command" >/dev/null || { echo "Missing host command: $$command" >&2; exit 2; }; done
	@if [[ "$(LOG)" == 1 ]]; then bash ./logged-run.sh "$(LOG_DIR)" "coreos-guest-transient" -- $(COREOS_MAKE) --no-print-directory qualify-coreos-guest-transient LOG=0; \
	else bash ./coreos-guest-transient-qualify.sh "$(COREOS_GUEST_HOST)" "$(COREOS_GUEST_PORT)" "$(COREOS_GUEST_KEY)" "$(COREOS_GUEST_COMPOSITION)" "$(COREOS_GUEST_RUNTIME)" "$(COREOS_GUEST_PAYLOAD)"; fi

qualify-coreos-profile:
	@test -n "$(COREOS_PROFILE)" || { echo "COREOS_PROFILE is required (the profile must exist in the selected Agni checkout)" >&2; exit 2; }
	@test -n "$(COREOS_PROFILE_BRANCH)" || { echo "COREOS_PROFILE_BRANCH is required" >&2; exit 2; }
	@if [[ "$(LOG)" != 0 && "$(LOG)" != 1 ]]; then echo "LOG must be 0 or 1" >&2; exit 2; fi
	@if [[ "$(LOG)" == 1 ]]; then \
	  bash ./logged-run.sh "$(LOG_DIR)" "coreos-profile-$(COREOS_PROFILE)" -- $(COREOS_MAKE) --no-print-directory qualify-coreos-profile COREOS_PROFILE="$(COREOS_PROFILE)" LOG=0; \
	else \
	  set -Eeuo pipefail; \
	  $(COREOS_MAKE) ensure-coreos-state-mount; \
	  $(COREOS_MAKE) coreos-qemu-host-preflight; \
	  $(COREOS_MAKE) sync REPO=dash-xd/agni BRANCH="$(COREOS_PROFILE_BRANCH)" WORKSPACES="$(WORKSPACES)" SYNC_NAME="$(COREOS_PROFILE_CHECKOUT)"; \
	  agni_rev="$$(git -C "$(WORKSPACES)/$(COREOS_PROFILE_CHECKOUT)" rev-parse HEAD)"; \
	  if [[ -n "$(COREOS_PROFILE_REV)" && "$$agni_rev" != "$(COREOS_PROFILE_REV)" ]]; then echo "Agni source does not match requested revision $(COREOS_PROFILE_REV)" >&2; exit 1; fi; \
	  nix_rev="$$(git -C "$(NIX_ALPINE_ROOT)" rev-parse HEAD)"; \
	  nix_checkout="$$(realpath --relative-to="$(WORKSPACES)" "$(NIX_ALPINE_ROOT)")"; \
	  COMPOSITION_AGNI_BRANCH="$(COREOS_PROFILE_BRANCH)" bash ./coreos-profile-qualify.sh "$(CONTAINER)" "$(WORKSPACES)" "$(COREOS_PROFILE_CHECKOUT)" "$$agni_rev" "$$nix_checkout" "$$nix_rev" "$(COREOS_PROFILE)" "$(COREOS_PROFILE_OUTPUT)" "$(COREOS_PROFILE_STATE)" "$(COREOS_PROFILE_UNIT)" "$(COREOS_MAKE)" "$(COREOS_PROFILE_CONSOLE_LOGIN)"; \
	fi
coreos-qemu-host-preflight:
	@bash ./coreos-qemu-host-preflight.sh "$(COREOS_QEMU_ACCEL)"
ensure-coreos-state-mount:
	@set -euo pipefail; \
	  expected="$$(realpath -m "$(COREOS_STATE_ROOT)")"; \
	  actual="$$(podman inspect "$(CONTAINER)" --format '{{range .Mounts}}{{if eq .Destination "/run/nix-alpine/coreos-qemu"}}{{.Source}}{{end}}{{end}}' 2>/dev/null || true)"; \
	  running="$$(podman inspect "$(CONTAINER)" --format '{{.State.Running}}' 2>/dev/null || true)"; \
	  if [[ "$$actual" != "$$expected" || "$$running" != true ]]; then \
	    echo "Refreshing toolbox to mount scoped CoreOS build state"; \
	    $(COREOS_MAKE) bootstrap SCOPE="$(SCOPE)" WORKSPACES="$(WORKSPACES)" STATE_ROOT="$(COREOS_STATE_ROOT)"; \
	  fi; \
	  actual="$$(podman inspect "$(CONTAINER)" --format '{{range .Mounts}}{{if eq .Destination "/run/nix-alpine/coreos-qemu"}}{{.Source}}{{end}}{{end}}')"; \
	  [[ "$$actual" == "$$expected" ]] || { echo "Toolbox is missing the expected CoreOS state mount" >&2; exit 1; }
coreos-qemu-build:
	@$(COREOS_MAKE) ensure-coreos-state-mount
	@bash ./coreos-qemu-build.sh "$(CONTAINER)" "$(WORKSPACES)" "$(COMPOSITION_AGNI_CHECKOUT)" "$(COMPOSITION_AGNI_REV)" "$(COREOS_CONFIG_DIR)" "$(COREOS_RESOURCES)" "$(COREOS_STATE)" "$(COREOS_REUSE)" "$(COREOS_CONFIG_NAME)" "$(COREOS_COMPOSITION_NAME)" "$(NIX_ALPINE_TOOLBOX_FLAKE)" "$(COREOS_STATE_ROOT)"
coreos-qemu-clean:
	@systemctl --user stop "$(COREOS_UNIT).service" >/dev/null 2>&1 || true
	@systemctl --user reset-failed "$(COREOS_UNIT).service" >/dev/null 2>&1 || true
	@rm -f "$(COREOS_STATE)/overlay.qcow2"

