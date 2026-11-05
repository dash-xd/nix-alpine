#!/usr/bin/env bash
set -Eeuo pipefail
export LC_ALL=C

workspace_root="$(realpath "$1")"
input_checkout="$2"
input_rev="$3"
build_flake="$4"
build_target="$5"
config_dir="$(realpath "$6")"
resources_dir="$(realpath "$7")"
state="$(realpath -m "$8")"
reuse="$9"
config_name="${10}"
composition_name="${11}"
input_root="$(realpath "$workspace_root/$input_checkout")"
flake_dir="$(realpath "$input_root/$build_flake")"
builder_id="$(realpath "$0")"

valid_relative() {
  local value="$1"
  [[ "$value" =~ ^[A-Za-z0-9_.-]+(/[A-Za-z0-9_.-]+)*$ ]] &&
    [[ "$value" != . && "/$value/" != *"/../"* && "/$value/" != *"/.git/"* ]]
}
valid_relative "$input_checkout" || { echo "Invalid input checkout path" >&2; exit 2; }
valid_relative "$build_flake" || { echo "Invalid build flake path" >&2; exit 2; }
[[ "$build_target" =~ ^#[A-Za-z0-9_.-]+$ ]] || { echo "Invalid CoreOS build target" >&2; exit 2; }
for path in "$input_root" "$flake_dir" "$config_dir" "$resources_dir"; do
  [[ "$path/" == "$workspace_root/"* ]] || { echo "Build input escapes $workspace_root: $path" >&2; exit 2; }
done
[[ "$(git -C "$input_root" rev-parse HEAD)" == "$input_rev" ]] || { echo "Input checkout does not match pinned revision $input_rev" >&2; exit 1; }
[[ -f "$flake_dir/flake.nix" ]] || { echo "Build flake is missing: $flake_dir" >&2; exit 2; }
[[ "$input_rev" =~ ^[0-9a-f]{40}$ ]] || { echo "Invalid pinned input revision" >&2; exit 2; }
[[ "$config_name" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*\.bu$ ]] || { echo "Invalid Butane config name" >&2; exit 2; }
[[ "$composition_name" =~ ^[a-z_][a-z0-9_-]{0,18}$ ]] || { echo "Invalid composition account prefix" >&2; exit 2; }
[[ "$reuse" == 0 || "$reuse" == 1 ]] || { echo "COREOS_REUSE must be 0 or 1" >&2; exit 2; }
test -f "$config_dir/$config_name" && test -d "$resources_dir" || { echo "Butane inputs are incomplete" >&2; exit 2; }
mkdir -p "$state"

hash_inputs() {
  {
    printf 'source=%s\nflake=%s/%s\ntarget=%s\nconfig=%s\ncomposition=%s\nbuilder=%s\n' "$input_rev" "$input_checkout" "$build_flake" "$build_target" "$config_name" "$composition_name" "$builder_id"
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
if [[ -n "${COREOS_TEST_SSH_PUBLIC_KEY:-}" ]]; then build_env+=("COREOS_TEST_SSH_PUBLIC_KEY=$COREOS_TEST_SSH_PUBLIC_KEY"); fi
flake_ref="$flake_dir$build_target"
if ! output="$("${build_env[@]}" nix build -L --impure --no-write-lock-file --no-link --print-out-paths "$flake_ref" 2>"$build_log")"; then
  cat "$build_log" >&2
  printf '%s\n' "$output" >&2
  exit 1
fi
cat "$build_log"
[[ "$output" =~ ^/nix/store/[a-z0-9]{32}-[^[:space:]]+$ && -d "$output" ]] || {
  echo "Unexpected Nix artifact path output: $output" >&2
  exit 1
}

staging="$(mktemp -d "$state/.build.XXXXXXXX")"
cleanup_staging() {
  [[ -n "$staging" && -d "$staging" ]] || return 0
  chmod u+w "$staging" 2>/dev/null || true
  rm -rf -- "$staging"
}
trap cleanup_staging EXIT
cp -a "$output/." "$staging/"
chmod u+w "$staging"
test -s "$staging/base.qcow2" && test -s "$staging/config.ign" || { echo "Nix artifact bundle must provide base.qcow2 and config.ign" >&2; exit 1; }
(cd "$staging" && sha256sum base.qcow2 config.ign > artifacts.sha256)
printf '%s\n' "$build_key" > "$staging/build-key"
for artifact in base.qcow2 config.ign artifacts.sha256 build-key; do
  mv -f -- "$staging/$artifact" "$state/$artifact"
done
cleanup_staging
staging=""
echo "PASS: pinned CoreOS disk and workspace-composed Ignition artifact built inside Nix-Alpine at $state"
