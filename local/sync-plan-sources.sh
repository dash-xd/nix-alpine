#!/usr/bin/env bash
set -Eeuo pipefail

manifest=${1:?Usage: sync-plan-sources.sh MANIFEST WORKSPACES NIX_XD_ROOT}
workspaces=${2:?Missing WORKSPACES}
expected_root=${3:?Missing NIX_XD_ROOT}

[[ -d "$workspaces" && -d "$expected_root" ]] || {
  echo "Workspace root and expected nix.xd root must already exist" >&2
  exit 2
}
workspaces=$(realpath "$workspaces")
expected_root=$(realpath "$expected_root")
[[ "$workspaces" == "$expected_root" ]] || {
  echo "Workspace root mismatch: $workspaces (expected $expected_root)" >&2
  exit 2
}
[[ -r "$manifest" ]] || { echo "Source manifest is not readable: $manifest" >&2; exit 2; }

# Validate all rows before making a directory, initializing Git, fetching, or
# checking out any source. This avoids partial workspaces from malformed locks.
awk -F '\t' '
  /^[[:space:]]*$/ || /^[[:space:]]*#/ { next }
  NF != 4 { printf "Invalid source manifest row %d: expected 4 tab-separated fields\n", NR > "/dev/stderr"; bad=1; next }
  $1 == "" || $2 == "" || $3 == "" || $4 == "" { printf "Invalid source manifest row %d: empty field\n", NR > "/dev/stderr"; bad=1 }
  END { if (bad) exit 1 }
' "$manifest" || exit 2

declare -a components=() repos=() revisions=() checkouts=() paths=() fetch_refs=()
declare -A seen_component=() seen_checkout=()
while IFS=$'\t' read -r component repo revision checkout extra || [[ -n "${component:-}" ]]; do
  [[ -z "${component:-}" || "$component" == \#* ]] && continue
  [[ "$component" =~ ^[a-z][a-z0-9-]*$ ]] || { echo "Invalid component key: $component" >&2; exit 2; }
  [[ -z "${seen_component[$component]:-}" ]] || { echo "Duplicate component key: $component" >&2; exit 2; }
  seen_component[$component]=1
  [[ -z "${extra:-}" ]] || { echo "Source row has more than four fields" >&2; exit 2; }
  [[ "$repo" =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$ ]] || { echo "Invalid repository: $repo" >&2; exit 2; }
  [[ "$revision" =~ ^[0-9a-f]{40}$ ]] || { echo "Invalid pinned revision for $repo" >&2; exit 2; }
  [[ "$checkout" != /* && "$checkout" != *//* ]] || { echo "Invalid checkout path for $repo" >&2; exit 2; }
  IFS=/ read -r -a parts <<< "$checkout"
  for part in "${parts[@]}"; do
    [[ "$part" =~ ^[A-Za-z0-9_.-]+$ && "$part" != "." && "$part" != ".." && "$part" != ".git" ]] || {
      echo "Invalid checkout path for $repo: $checkout" >&2; exit 2;
    }
  done
  [[ -z "${seen_checkout[$checkout]:-}" ]] || { echo "Duplicate checkout: $checkout" >&2; exit 2; }
  seen_checkout[$checkout]=1
  for prior in "${checkouts[@]}"; do
    [[ "$checkout" != "$prior/"* && "$prior" != "$checkout/"* ]] || {
      echo "Nested checkouts are not allowed: $prior and $checkout" >&2; exit 2;
    }
  done

  path="$workspaces/$checkout"
  current="$workspaces"
  missing_parent=0
  for part in "${parts[@]}"; do
    current="$current/$part"
    if (( missing_parent )); then continue; fi
    if [[ -L "$current" ]]; then echo "Checkout path contains a symlink: $current" >&2; exit 2; fi
    if [[ -e "$current" ]]; then
      [[ -d "$current" ]] || { echo "Checkout path component is not a directory: $current" >&2; exit 2; }
      resolved=$(realpath "$current")
      [[ "$resolved" == "$workspaces" || "$resolved" == "$workspaces/"* ]] || {
        echo "Checkout path escapes workspace root: $checkout" >&2; exit 2;
      }
      current=$resolved
    else
      missing_parent=1
    fi
  done

  expected_origin="https://github.com/$repo.git"
  if [[ -e "$path" || -L "$path" ]]; then
    [[ ! -L "$path" && -d "$path" ]] || { echo "Checkout destination is not a real directory: $path" >&2; exit 2; }
    [[ -d "$path/.git" || -f "$path/.git" ]] || { echo "Refusing to initialize over a non-Git directory: $path" >&2; exit 2; }
    actual_origin=$(git -C "$path" remote get-url origin 2>/dev/null) || {
      echo "Checkout has no origin: $path" >&2; exit 2;
    }
    [[ "$actual_origin" == "$expected_origin" || "$actual_origin" == "git@github.com:$repo.git" ]] || {
      echo "Origin mismatch for $checkout: expected $repo, got $actual_origin" >&2; exit 2;
    }
    [[ -z "$(git -C "$path" status --porcelain --untracked-files=all)" ]] || {
      echo "Local modifications or untracked files in $path; refusing to change it" >&2; exit 2;
    }
  fi

  components+=("$component")
  repos+=("$repo")
  revisions+=("$revision")
  checkouts+=("$checkout")
  paths+=("$path")
  fetch_refs+=("refs/nix-alpine/plan-sources/$component")
done < "$manifest"

(( ${#components[@]} > 0 )) || { echo "Source manifest has no source rows" >&2; exit 2; }

# Fetch every pinned object before changing any checked-out worktree.
for i in "${!components[@]}"; do
  path=${paths[$i]}
  if [[ ! -e "$path" ]]; then
    mkdir -p "$(dirname "$path")"
    git init -q "$path"
    git -C "$path" remote add origin "https://github.com/${repos[$i]}.git"
  fi
  git -C "$path" fetch --depth=1 origin "+${revisions[$i]}:${fetch_refs[$i]}"
  fetched=$(git -C "$path" rev-parse "${fetch_refs[$i]}^{commit}")
  [[ "$fetched" == "${revisions[$i]}" ]] || {
    echo "Fetched revision mismatch for ${repos[$i]}: expected ${revisions[$i]}, got $fetched" >&2
    exit 1
  }
done

# Only after the full lock is fetched do we update worktrees.
for i in "${!components[@]}"; do
  path=${paths[$i]}
  [[ -z "$(git -C "$path" status --porcelain --untracked-files=all)" ]] || {
    echo "Checkout changed during synchronization: $path" >&2; exit 1;
  }
  git -C "$path" checkout --detach "${fetch_refs[$i]}"
  actual=$(git -C "$path" rev-parse HEAD)
  [[ "$actual" == "${revisions[$i]}" ]] || {
    echo "Source revision mismatch for ${repos[$i]}: expected ${revisions[$i]}, got $actual" >&2
    exit 1
  }
  echo "PASS: host source checkout ${repos[$i]} at $actual"
done
