#!/usr/bin/env bash
set -euo pipefail

repo="${1:?Usage: sync.sh owner/repo branch [workspaces]}"
branch="${2:?Missing branch}"
workspaces="${3:-$HOME/workspace/nix}"

[[ "$repo" =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$ ]] || { echo "Invalid repository: $repo" >&2; exit 2; }
[[ "$branch" != -* && "$branch" != *..* && "$branch" != *' '* ]] || { echo "Invalid branch: $branch" >&2; exit 2; }
git check-ref-format --branch "$branch" >/dev/null

name="${repo#*/}"
path="$workspaces/$name"
mkdir -p "$workspaces"
if [[ ! -e "$path" ]]; then
  git clone --branch "$branch" --single-branch "https://github.com/$repo.git" "$path"
  echo "Cloned $repo ($branch) into $path"
  exit 0
fi

[[ -d "$path/.git" ]] || { echo "Not a Git checkout: $path" >&2; exit 1; }
expected="https://github.com/$repo.git"
actual="$(git -C "$path" remote get-url origin)"
if [[ "$actual" != "$expected" && "$actual" != "git@github.com:$repo.git" ]]; then
  echo "Origin mismatch: $actual (expected $repo)" >&2
  exit 1
fi
if [[ -n "$(git -C "$path" status --porcelain --untracked-files=no)" ]]; then
  echo "Tracked local modifications in $path; refusing to overwrite" >&2
  exit 1
fi

git -C "$path" fetch origin "refs/heads/$branch:refs/remotes/origin/$branch"
if git -C "$path" show-ref --verify --quiet "refs/heads/$branch"; then
  git -C "$path" switch "$branch"
else
  git -C "$path" switch -c "$branch" --track "origin/$branch"
fi
git -C "$path" merge --ff-only "origin/$branch"
echo "Synchronized $repo ($branch): $(git -C "$path" rev-parse --short HEAD)"
