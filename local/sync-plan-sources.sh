#!/usr/bin/env bash
set -Eeuo pipefail

manifest=${1:?Usage: sync-plan-sources.sh MANIFEST WORKSPACES}
workspaces=${2:?Usage: sync-plan-sources.sh MANIFEST WORKSPACES}
[[ -r "$manifest" ]] || { echo "Source manifest is not readable: $manifest" >&2; exit 2; }
mkdir -p "$workspaces"

declare -A seen=()
while IFS=$'\t' read -r repo revision checkout extra || [[ -n "${repo:-}" ]]; do
  [[ -z "${repo:-}" || "$repo" == \\#* ]] && continue
  [[ -z "${extra:-}" ]] || { echo "Source manifest row has more than three columns" >&2; exit 2; }
  [[ "$repo" =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$ ]] || { echo "Invalid repository in source manifest: $repo" >&2; exit 2; }
  [[ "$revision" =~ ^[0-9a-f]{40}$ ]] || { echo "Invalid pinned revision for $repo" >&2; exit 2; }
  [[ "$checkout" =~ ^[A-Za-z0-9][A-Za-z0-9_.-]*$ ]] || { echo "Invalid checkout name for $repo" >&2; exit 2; }
  [[ -z "${seen[$checkout]:-}" ]] || { echo "Duplicate checkout in source manifest: $checkout" >&2; exit 2; }
  seen[$checkout]=1

  path="$workspaces/$checkout"
  expected="https://github.com/$repo.git"
  if [[ ! -e "$path" ]]; then
    git init -q "$path"
    git -C "$path" remote add origin "$expected"
  fi
  [[ -d "$path/.git" ]] || { echo "Not a Git checkout: $path" >&2; exit 1; }
  actual_origin=$(git -C "$path" remote get-url origin)
  [[ "$actual_origin" == "$expected" || "$actual_origin" == "git@github.com:$repo.git" ]] || {
    echo "Origin mismatch for $checkout: expected $repo, got $actual_origin" >&2
    exit 1
  }
  [[ -z "$(git -C "$path" status --porcelain --untracked-files=no)" ]] || {
    echo "Tracked local modifications in $path; refusing to change the checkout" >&2
    exit 1
  }

  git -C "$path" fetch --depth=1 origin "$revision"
  git -C "$path" checkout --detach FETCH_HEAD
  actual_revision=$(git -C "$path" rev-parse HEAD)
  [[ "$actual_revision" == "$revision" ]] || {
    echo "Source revision mismatch for $repo: expected $revision, got $actual_revision" >&2
    exit 1
  }
  echo "PASS: host source checkout $repo at $actual_revision"
done < "$manifest"
