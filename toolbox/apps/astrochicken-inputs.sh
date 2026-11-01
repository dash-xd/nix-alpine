#!/usr/bin/env bash
set -Eeuo pipefail

workspaces="$(realpath "${1:?WORKSPACES is required}")"
source_dir="$(realpath "${2:?Nix-Alpine source checkout is required}")"
source_rev="${3:?Nix-Alpine source revision is required}"
resource_output="$(realpath -m "${4:?Astrochicken resource output is required}")"
workspace_files="${5:-}"
console_login="${6:-0}"

[[ "$source_rev" =~ ^[0-9a-f]{40}$ && "$(git -C "$source_dir" rev-parse HEAD)" == "$source_rev" ]] || {
  echo "Nix-Alpine source checkout does not match its pinned revision" >&2
  exit 2
}
[[ -z "$(git -C "$source_dir" status --porcelain)" ]] || {
  echo "Astrochicken requires a clean, committed Nix-Alpine checkout" >&2
  exit 2
}
[[ "$source_dir/" == "$workspaces/"* ]] || {
  echo "Nix-Alpine source checkout must remain under WORKSPACES" >&2
  exit 2
}
[[ "$resource_output/" == "$workspaces/"* && "$resource_output" != "$workspaces" ]] || {
  echo "Astrochicken resource output must be a child of WORKSPACES" >&2
  exit 2
}
[[ "$console_login" == 0 || "$console_login" == 1 ]] || {
  echo "Astrochicken console profile must be 0 or 1" >&2
  exit 2
}
profile="$source_dir/local/coreos/astrochicken"
[[ -f "$profile/butane/astrochicken.bu" && -d "$profile/resources/astrochicken" ]] || {
  echo "Astrochicken Butane profile or resources are missing from Nix-Alpine" >&2
  exit 2
}

parent="$(dirname "$resource_output")"
mkdir -p "$parent"
staging="$(mktemp -d "$parent/.astrochicken-inputs.XXXXXX")"
cleanup() {
  [[ -z "${staging:-}" ]] || rm -rf -- "$staging"
}
trap cleanup EXIT
cp -a "$profile/resources/." "$staging/"
git -C "$source_dir" archive --format=tar "$source_rev" | gzip -n > "$staging/astrochicken/nix-alpine-source.tar.gz"
printf '%s\n' "$source_rev" > "$staging/astrochicken/nix-alpine-revision"

mkdir -p "$staging/astrochicken/workspace-imports"
entries="$staging/.extra-storage-files"
: > "$entries"
declare -A destinations=()
count=0
IFS=' ' read -r -a requested_files <<< "$workspace_files"
for relative_path in "${requested_files[@]}"; do
  [[ -n "$relative_path" ]] || continue
  [[ "$relative_path" != /* && "$relative_path" != *$'\n'* && "$relative_path" != *$'\t'* ]] || {
    echo "Workspace resource must be a relative path without whitespace: $relative_path" >&2
    exit 2
  }
  case "/$relative_path/" in
    */../*|*/./*) echo "Workspace resource path must be normalized: $relative_path" >&2; exit 2 ;;
  esac
  [[ "$relative_path" =~ ^[A-Za-z0-9._/-]+$ ]] || {
    echo "Workspace resource path contains unsupported characters: $relative_path" >&2
    exit 2
  }
  source_file="$(realpath "$workspaces/$relative_path")"
  [[ "$source_file/" == "$workspaces/"* && -f "$source_file" && ! -L "$workspaces/$relative_path" ]] || {
    echo "Workspace resource must be a regular file beneath WORKSPACES: $relative_path" >&2
    exit 2
  }
  case "$relative_path" in
    nix-alpine/*|astrochicken-flake/*) echo "Workspace resource path is reserved: $relative_path" >&2; exit 2 ;;
  esac
  [[ -z "${destinations[$relative_path]:-}" ]] || {
    echo "Duplicate workspace resource path: $relative_path" >&2
    exit 2
  }
  destinations[$relative_path]=1
  count=$((count + 1))
  resource_path="astrochicken/workspace-imports/$relative_path"
  mkdir -p "$staging/$(dirname "$resource_path")"
  cp -- "$source_file" "$staging/$resource_path"
  printf '    - path: /etc/astrochicken/workspace-imports/%s\n      mode: 0644\n      contents:\n        local: %s\n' \
    "$relative_path" "$resource_path" >> "$entries"
done

if [[ "$console_login" == 1 ]]; then
  cat >> "$entries" <<'EOF'
    - path: /etc/astrochicken/console-enabled
      mode: 0444
      contents:
        inline: enabled
EOF
fi

config="$staging/astrochicken-generated.bu"
awk -v extra="$entries" '
  $0 == "  # ASTROCHICKEN_EXTRA_STORAGE_FILES" {
    while ((getline line < extra) > 0) print line
    close(extra)
    next
  }
  { print }
' "$profile/butane/astrochicken.bu" > "$config"
grep -q '^  # ASTROCHICKEN_EXTRA_STORAGE_FILES$' "$profile/butane/astrochicken.bu" || {
  echo "Astrochicken Butane storage insertion point is missing" >&2
  exit 2
}
rm -f -- "$entries"

if [[ -e "$resource_output" ]]; then
  [[ -d "$resource_output" && ! -L "$resource_output" ]] || {
    echo "Refusing to replace non-directory Astrochicken resource output" >&2
    exit 2
  }
  rm -rf -- "$resource_output"
fi
mv -- "$staging" "$resource_output"
staging=""
echo "PASS: single Astrochicken Butane document staged from Nix-Alpine $source_rev"
echo "Astrochicken workspace files embedded: $count"
echo "Astrochicken console login enabled: $console_login"
