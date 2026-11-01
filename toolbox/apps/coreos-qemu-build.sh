#!/usr/bin/env bash
set -Eeuo pipefail
export LC_ALL=C

workspace_root="$(realpath "${1:?workspace root required}")"
agni_checkout="${2:?Agni checkout required}"
agni_rev="${3:?Agni revision required}"
config_dir="$(realpath "${4:?Butane config directory required}")"
resources_dir="$(realpath "${5:?Butane resources directory required}")"
state="$(realpath -m "${6:?CoreOS state directory required}")"
reuse="${7:-1}"
config_name="${8:-fatline-bootstrap.bu}"
composition_name="${9:-fatline}"
agni_dir="$(realpath "$workspace_root/$agni_checkout")"
builder_id="$(realpath "$0")"

for path in "$agni_dir" "$config_dir" "$resources_dir"; do
  [[ "$path/" == "$workspace_root/"* ]] || {
    echo "Build input must remain under $workspace_root: $path" >&2
    exit 2
  }
done
[[ "$agni_rev" =~ ^[0-9a-f]{40}$ ]] || { echo "Invalid pinned Agni revision" >&2; exit 2; }
[[ "$config_name" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*\.bu$ ]] || { echo "Invalid Butane config name" >&2; exit 2; }
[[ "$composition_name" =~ ^[a-z_][a-z0-9_-]{0,18}$ ]] || { echo "Invalid composition account prefix" >&2; exit 2; }
[[ "$reuse" == 0 || "$reuse" == 1 ]] || { echo "COREOS_REUSE must be 0 or 1" >&2; exit 2; }
[[ "$(git -C "$agni_dir" rev-parse HEAD)" == "$agni_rev" ]] || { echo "Agni checkout does not match pinned revision $agni_rev" >&2; exit 1; }
test -f "$config_dir/$config_name" && test -d "$resources_dir" || { echo "Butane inputs are incomplete" >&2; exit 2; }
mkdir -p "$state"

hash_inputs() {
  {
    printf 'agni=%s\nconfig=%s\ncomposition=%s\nbuilder=%s\n' "$agni_rev" "$config_name" "$composition_name" "$builder_id"
    printf 'ssh-key=%s\n' "$(printf '%s' "${COREOS_TEST_SSH_PUBLIC_KEY:-}" | sha256sum | awk '{print $1}')"
    for path in "$config_dir" "$resources_dir"; do
      [[ -z "$(find "$path" -type l -print -quit)" ]] || { echo "Symlinks are not allowed in Butane inputs: $path" >&2; return 2; }
      (cd "$path"; find . -type f -print0 | sort -z | xargs -0 -r sha256sum)
    done
  } | sha256sum | awk '{print $1}'
}

build_key="$(hash_inputs)"
if [[ "$reuse" == 1 && -f "$state/build-key" && -f "$state/artifacts.sha256" ]] &&
  [[ "$(cat "$state/build-key")" == "$build_key" ]] &&
  (cd "$state" && sha256sum --check artifacts.sha256); then
  echo "PASS: reused checksum-verified CoreOS QEMU artifact bundle"
  exit 0
fi

build_log="$state/nix-build.log"
: > "$build_log"
build_env=(env "COREOS_CONFIG_DIR=$config_dir" "COREOS_CONFIG_NAME=$config_name" \
  "COREOS_RESOURCES_DIR=$resources_dir" "COREOS_COMPOSITION_NAME=$composition_name")
[[ -z "${COREOS_TEST_SSH_PUBLIC_KEY:-}" ]] || build_env+=("COREOS_TEST_SSH_PUBLIC_KEY=$COREOS_TEST_SSH_PUBLIC_KEY")
if ! output="$("${build_env[@]}" nix build -L --impure --no-write-lock-file --no-link --print-out-paths "$agni_dir/qemu/coreos-live/local#bootstrap" 2>"$build_log")"; then
  cat "$build_log" >&2
  printf '%s\n' "$output" >&2
  exit 1
fi
cat "$build_log"
[[ "$output" =~ ^/nix/store/[a-z0-9]{32}-fatline-coreos-qemu-bootstrap-[^[:space:]]+$ ]] || {
  echo "Unexpected Nix artifact path output: $output" >&2
  exit 1
}

staging="$(mktemp -d "$state/.build.XXXXXXXX")"
trap 'rm -rf -- "$staging"' EXIT
cp -a "$output/." "$staging/"
chmod u+w "$staging"
test -s "$staging/base.qcow2" && test -s "$staging/config.ign" || { echo "Nix artifact bundle is incomplete" >&2; exit 1; }
(cd "$staging" && sha256sum base.qcow2 config.ign > artifacts.sha256)
printf '%s\n' "$build_key" > "$staging/build-key"
for artifact in base.qcow2 config.ign artifacts.sha256 build-key; do
  mv -f -- "$staging/$artifact" "$state/$artifact"
done
echo "PASS: pinned FCOS disk and workspace-composed Ignition artifact built inside Nix-Alpine at $state"
