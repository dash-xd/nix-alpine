#!/usr/bin/env bash
set -Eeuo pipefail

workspace_root=${1:-/workspaces}
[[ -d "$workspace_root" ]] || { echo "Workspace root is not mounted: $workspace_root" >&2; exit 2; }

shopt -s nullglob dotglob
for candidate in "$workspace_root" "$workspace_root"/* "$workspace_root"/.[!.]* "$workspace_root"/..?*; do
  [[ -d "$candidate/.git" || -f "$candidate/.git" ]] || continue
  git config --global --add safe.directory "$candidate"
done
