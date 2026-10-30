#!/usr/bin/env bash
set -Eeuo pipefail
export LC_ALL=C

agni_dir="${1:?Agni source directory required}"
config_dir="${2:?Butane config directory required}"
resources_dir="${3:?Butane resources directory required}"
agni_rev="${4:?Agni revision required}"

[[ "$agni_rev" =~ ^[0-9a-f]{40}$ ]] || { echo "Invalid Agni revision" >&2; exit 2; }
for path in "$agni_dir" "$config_dir" "$resources_dir"; do
  test -d "$path" || { echo "Not a directory: $path" >&2; exit 2; }
done

{
  printf 'agni=%s\n' "$agni_rev"
  for path in "$config_dir" "$resources_dir"; do
    if find "$path" -type l -print -quit | grep -q .; then
      echo "Symlinks are not allowed in Butane inputs: $path" >&2
      exit 2
    fi
    (
      cd "$path"
      while IFS= read -r -d '' file; do
        sha256sum "$file"
      done < <(find . -type f -print0 | sort -z)
    )
  done
} | sha256sum | awk '{print $1}'
