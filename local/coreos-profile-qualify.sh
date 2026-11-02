#!/usr/bin/env bash
set -Eeuo pipefail

toolbox="${1:?Nix-Alpine toolbox container required}"
workspaces="$(realpath "${2:?shared workspaces root required}")"
agni_checkout="${3:?Agni checkout name required}"
agni_rev="${4:?pinned Agni revision required}"
nix_checkout="${5:?Nix-Alpine checkout path required}"
nix_rev="${6:?pinned Nix-Alpine revision required}"
profile="${7:?Agni CoreOS profile name required}"
profile_output="$(realpath -m "${8:?profile output directory required}")"
state="${9:?QEMU state directory required}"
unit="${10:?systemd user unit name required}"
make_command="${11:-make}"
console_override="${12:-}"

[[ "$profile" =~ ^[a-z][a-z0-9_-]*$ ]] || { echo "Invalid CoreOS profile name: $profile" >&2; exit 2; }
agni_dir="$(realpath "$workspaces/$agni_checkout")"
nix_dir="$(realpath "$workspaces/$nix_checkout")"
profile_dir="$agni_dir/qemu/coreos-live/profiles/$profile"
plan="$profile_dir/qualification.json"
[[ -f "$plan" ]] || { echo "Agni profile plan does not exist: $plan" >&2; exit 2; }
[[ "$(git -C "$agni_dir" rev-parse HEAD)" == "$agni_rev" ]] || { echo "Agni checkout revision mismatch" >&2; exit 1; }
[[ "$(git -C "$nix_dir" rev-parse HEAD)" == "$nix_rev" ]] || { echo "Nix-Alpine checkout revision mismatch" >&2; exit 1; }
[[ -z "$(git -C "$agni_dir" status --porcelain)" && -z "$(git -C "$nix_dir" status --porcelain)" ]] || {
  echo "Pinned Agni and Nix-Alpine checkouts must be clean" >&2
  exit 2
}

composition="$(jq -er '.compositionName | strings | select(test("^[a-z_][a-z0-9_-]{0,18}$"))' "$plan")"
config_name="$(jq -er '.configName | strings | select(test("^[A-Za-z0-9][A-Za-z0-9._-]*\\.bu$"))' "$plan")"
prepare_app="$(jq -r '.prepareApp // empty' "$plan")"
if [[ -n "$prepare_app" ]]; then
  [[ "$prepare_app" =~ ^[a-z][a-z0-9-]*$ ]] || { echo "Invalid profile input app in $plan" >&2; exit 2; }
fi
image="$(jq -er '.runtimeImage | strings | select(test("^[A-Za-z0-9._:/-]+$"))' "$plan")"
marker="$(jq -er '.expectedMarker | strings | select(length > 0)' "$plan")"
plan_sha="$(sha256sum "$plan" | awk '{print $1}')"
console_login="$(jq -r '.consoleLogin // false | if . then "1" else "0" end' "$plan")"
if [[ -n "$console_override" ]]; then console_login="$console_override"; fi
transient_test="$(jq -r '.transientTester // false | if . then "1" else "0" end' "$plan")"
[[ "$console_login" == 0 || "$console_login" == 1 ]] || { echo "Console login override must be 0 or 1" >&2; exit 2; }
[[ "$transient_test" == 0 || "$transient_test" == 1 ]] || { echo "Transient tester override must be 0 or 1" >&2; exit 2; }
[[ "$profile_output/" == "$workspaces/"* && "$profile_output" != "$workspaces" ]] || {
  echo "Profile output must be beneath the shared workspaces root" >&2
  exit 2
}
printf 'Agni profile: %s\nAgni revision: %s\nNix-Alpine revision: %s\nProfile plan SHA-256: %s\n' \
  "$profile" "$agni_rev" "$nix_rev" "$plan_sha"
nix_relative="$(realpath --relative-to="$workspaces" "$nix_dir")"
if [[ -n "$prepare_app" ]]; then
  mkdir -p "$profile_output"
  podman exec "$toolbox" nix run --no-write-lock-file \
    "/workspaces/${agni_checkout}/qemu/coreos-live/local#${prepare_app}" -- \
    /workspaces "$agni_checkout" "$agni_rev" "$nix_relative" "$nix_rev" \
    "/workspaces/${profile_output#"$workspaces"/}" "${COREOS_PROFILE_WORKSPACE_FILES:-}" "$console_login"
  config_dir="$profile_output"
  resources_dir="$profile_output"
else
  config_relative="$(jq -er '.configDirectory | strings' "$plan")"
  resources_relative="$(jq -er '.resourcesDirectory | strings' "$plan")"
  config_dir="$(realpath "$profile_dir/$config_relative")"
  resources_dir="$(realpath "$profile_dir/$resources_relative")"
  [[ "$config_dir/" == "$profile_dir/"* && "$resources_dir/" == "$profile_dir/"* ]] || {
    echo "Profile config and resources must stay inside the Agni profile directory" >&2
    exit 2
  }
fi

args=(
  --no-print-directory qualify-coreos-qemu LOG=0
  "COMPOSITION_AGNI_BRANCH=${COMPOSITION_AGNI_BRANCH:?Agni branch required}"
  "COMPOSITION_AGNI_REV=$agni_rev"
  "COMPOSITION_AGNI_CHECKOUT=$agni_checkout"
  "COREOS_CONFIG_DIR=$config_dir"
  "COREOS_RESOURCES=$resources_dir"
  "COREOS_CONFIG_NAME=$config_name"
  "COREOS_STATE=$state"
  "COREOS_UNIT=$unit"
  "COREOS_COMPOSITION_NAME=$composition"
  "COREOS_QEMU_IMAGE=$image"
  "COREOS_QEMU_EXPECT_MARKER=$marker"
  "COREOS_QEMU_CONSOLE_LOGIN=$console_login"
  "COREOS_QEMU_TRANSIENT_TESTER=$transient_test"
  "COREOS_QEMU_HOLD=${COREOS_QEMU_HOLD:-0}"
)
"$make_command" "${args[@]}"
