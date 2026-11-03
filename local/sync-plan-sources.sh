#!/usr/bin/env bash
set -Eeuo pipefail

manifest=${1:?Usage: sync-plan-sources.sh MANIFEST WORKSPACES}
workspaces=${2:?Usage: sync-plan-sources.sh MANIFEST WORKSPACES}
[[ -r "$manifest" ]] || { echo "Source manifest is not readable: $manifest" >&2; exit 2; }
mkdir -p "$workspaces"

declare -A seen=()
while IFS=$'\t' read -r repo branch revision checkout extra || [[ -n "${repo:-}" ]]; do
  [[ -z "${repo:-}" || "$repo" == \\#* ]] && continue
  [[ -z "${extra:-}" ]] || { echo "Source manifest row has more than four columns" >&2; exit 2; }
  [[ "$repo" =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$ ]] || { echo "Invalid repository in source manifest: $repo" >&2; exit 2; }
  [[ "$revision" =~ ^[0-9a-f]{40}$ ]] || { echo "Invalid pinned revision for $repo" >&2; exit 2; }
  [[ "$checkout" =~ ^[A-Za-z0-9][A-Za-z0-9_.-]*$ ]] || { echo "Invalid checkout name for $repo" >&2; exit 2; }
  [[ -z "${seen[$checkout]:-}" ]] || { echo "Duplicate checkout in source manifest: $checkout" >&2; exit 2; }
  seen[$checkout]=1

  bash "$(dirname "$0")/sync.sh" "$repo" "$branch" "$workspaces" "$checkout"
  actual=$(git -C "$workspaces/$checkout" rev-parse HEAD)
  [[ "$actual" == "$revision" ]] || {
    echo "Source revision mismatch for $repo: expected $revision, got $actual" >&2
    exit 1
  }
  echo "PASS: host source checkout $repo at $actual"
done < "$manifest"
