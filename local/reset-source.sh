#!/usr/bin/env bash
set -Eeuo pipefail

discard_tracked=${1:-0}
discard_untracked=${2:-0}
discard_ignored=${3:-0}
dry_run=${4:-1}

for value_name in discard_tracked discard_untracked discard_ignored dry_run; do
  value=${!value_name}
  [[ "$value" == 0 || "$value" == 1 ]] || {
    echo "$value_name must be 0 or 1" >&2
    exit 2
  }
done

if [[ "$discard_ignored" == 1 && "$discard_untracked" != 1 ]]; then
  echo "DISCARD_IGNORED=1 requires DISCARD_UNTRACKED=1" >&2
  exit 2
fi

repo="$(git rev-parse --show-toplevel)"
cd "$repo"

branch="$(git symbolic-ref --quiet --short HEAD)" || {
  echo "Refusing source reset on detached HEAD" >&2
  exit 1
}
remote_ref="refs/remotes/origin/$branch"

echo "Fetching origin/$branch"
git fetch --no-tags origin "refs/heads/$branch:$remote_ref"

tracked_changes="$(git status --porcelain --untracked-files=no)"
untracked="$(git ls-files --others --exclude-standard)"
ignored="$(git ls-files --others --ignored --exclude-standard)"

if [[ "$dry_run" == 1 ]]; then
  echo "DRY RUN: no checkout files will be changed."
  echo "Checkout: $repo"
  echo "Branch: $branch"
  echo "Upstream: $(git rev-parse --short "$remote_ref")"
  git status --short --branch
  if [[ "$discard_tracked" == 1 ]]; then
    echo "Tracked changes and local commits will be discarded by reset to origin/$branch:"
    git diff --stat HEAD
    git log --oneline "$remote_ref..HEAD" || true
  else
    echo "Tracked changes and local commits are preserved; apply will only fast-forward."
  fi
  if [[ "$discard_untracked" == 1 ]]; then
    echo "Untracked files selected for removal:"
    git clean -nd
  else
    echo "Untracked files are preserved."
  fi
  if [[ "$discard_ignored" == 1 ]]; then
    echo "Ignored files selected for removal:"
    git clean -ndx
  else
    echo "Ignored files are preserved."
  fi
  echo "To apply this exact plan, rerun with RESET_DRY_RUN=0."
  exit 0
fi

if [[ "$discard_tracked" != 1 && -n "$tracked_changes" ]]; then
  echo "Tracked local changes found; set DISCARD_TRACKED=1 only after reviewing the preview." >&2
  exit 1
fi
if [[ "$discard_tracked" == 1 && -n "$untracked" && "$discard_untracked" != 1 ]]; then
  echo "Tracked reset could overwrite conflicting untracked files; preview and set DISCARD_UNTRACKED=1 to remove them explicitly." >&2
  exit 1
fi
if [[ "$discard_tracked" == 1 && -n "$ignored" && "$discard_ignored" != 1 ]]; then
  echo "Tracked reset could overwrite conflicting ignored files; preview and set DISCARD_IGNORED=1 to remove them explicitly." >&2
  exit 1
fi

if [[ "$discard_tracked" == 1 ]]; then
  echo "Resetting tracked files and branch to origin/$branch"
  git reset --hard "$remote_ref"
else
  echo "Fast-forwarding clean tracked files to origin/$branch"
  git merge --ff-only "$remote_ref"
fi

if [[ "$discard_ignored" == 1 ]]; then
  echo "Removing untracked and ignored files from this checkout"
  git clean -fdx
elif [[ "$discard_untracked" == 1 ]]; then
  echo "Removing untracked files from this checkout; ignored files remain"
  git clean -fd
fi

echo "Source reset complete: $(git rev-parse --short HEAD)"
