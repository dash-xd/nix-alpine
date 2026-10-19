#!/usr/bin/env bash
set -euo pipefail

force="${1:-0}"
repo="$(git rev-parse --show-toplevel)"
cd "$repo"

branch="$(git symbolic-ref --quiet --short HEAD)" || {
  echo "Refusing refresh on detached HEAD" >&2
  exit 1
}
remote_ref="refs/remotes/origin/$branch"

echo "Fetching origin/$branch"
git fetch origin "$branch"

if [[ "$force" == "1" ]]; then
  echo "FORCE=1: discarding tracked local changes in $repo"
  git reset --hard "$remote_ref"
else
  if [[ -n "$(git status --porcelain --untracked-files=no)" ]]; then
    echo "Tracked local changes detected; refusing to overwrite them." >&2
    echo "Inspect: git status --short" >&2
    echo "To discard tracked changes: make refresh FORCE=1" >&2
    exit 1
  fi
  git merge --ff-only "$remote_ref"
fi

echo "Source synchronized to $(git rev-parse --short HEAD)"
