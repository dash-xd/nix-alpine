#!/usr/bin/env bash
set -euo pipefail

repo="${1:?Usage: sync.sh owner/repo branch [workspaces]}"
branch="${2:?Missing branch}"
workspaces="${3:-$HOME/workspace/nix.xd}"
checkout_name="${4:-${repo#*/}}"
[[ "$checkout_name" != /* && "$checkout_name" != *//* ]] || { echo "Checkout path must be relative without empty components" >&2; exit 2; }
IFS=/ read -r -a checkout_parts <<< "$checkout_name"
for part in "${checkout_parts[@]}"; do
  [[ -n "$part" && "$part" != "." && "$part" != ".." && "$part" != ".git" && "$part" =~ ^[A-Za-z0-9_.-]+$ ]] || {
    echo "Invalid checkout path: $checkout_name" >&2
    exit 2
  }
done

[[ "$repo" =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$ ]] || { echo "Invalid repository: $repo" >&2; exit 2; }
[[ "$branch" != -* && "$branch" != *..* && "$branch" != *' '* ]] || { echo "Invalid branch: $branch" >&2; exit 2; }
git check-ref-format --branch "$branch" >/dev/null

name="$checkout_name"
mkdir -p "$workspaces"
workspaces="$(realpath "$workspaces")"
parent="$workspaces"
for ((i = 0; i < ${#checkout_parts[@]} - 1; i++)); do
  parent="$parent/${checkout_parts[i]}"
  if [[ -e "$parent" || -L "$parent" ]]; then
    resolved_parent="$(realpath "$parent")"
    [[ "$resolved_parent" == "$workspaces/"* ]] || { echo "Checkout parent escapes workspace root" >&2; exit 2; }
    [[ -d "$resolved_parent" ]] || { echo "Checkout parent is not a directory: $parent" >&2; exit 2; }
    parent="$resolved_parent"
  else
    mkdir -- "$parent"
  fi
done
last_index=$((${#checkout_parts[@]} - 1))
path="$parent/${checkout_parts[$last_index]}"
if [[ ! -e "$path" && ! -L "$path" ]]; then
  git clone --branch "$branch" --single-branch "https://github.com/$repo.git" "$path"
  echo "Cloned $repo ($branch) into $path"
  exit 0
fi

resolved_path="$(realpath "$path")"
[[ "$resolved_path" == "$workspaces/"* ]] || { echo "Checkout resolves outside workspace root: $path" >&2; exit 2; }
[[ -d "$resolved_path/.git" ]] || { echo "Not a Git checkout: $path" >&2; exit 1; }
path="$resolved_path"
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
  git -C "$path" switch -c "$branch" "refs/remotes/origin/$branch"
fi
git -C "$path" merge --ff-only "origin/$branch"
echo "Synchronized $repo ($branch): $(git -C "$path" rev-parse --short HEAD)"
