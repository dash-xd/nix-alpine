#!/usr/bin/env bash
# Cache only OCI/Docker transport archives, never a live Nix store or Podman storage.
set -Eeuo pipefail
[[ $# -ge 3 ]] || { echo "usage: $0 export|import DIRECTORY IMAGE..." >&2; exit 2; }
mode=$1 directory=$2; shift 2
[[ "$mode" == export || "$mode" == import ]] || exit 2
mkdir -p "$directory"
manifest="$directory/manifest.tsv"
if [[ "$mode" == export ]]; then
  [[ ! -e "$manifest" ]] || { echo "Refusing to overwrite archive manifest" >&2; exit 2; }
  tmp=$(mktemp "$directory/.manifest.XXXXXXXX")
  trap 'rm -f "$tmp"' EXIT
  for image in "$@"; do
    [[ "$image" =~ ^[a-zA-Z0-9_./:-]+$ ]] || { echo "Invalid image ref: $image" >&2; exit 2; }
    id=$(podman image inspect "$image" --format '{{.Id}}')
    id="sha256:${id#sha256:}"
    filename=$(printf '%s' "$image" | sha256sum | cut -d' ' -f1).tar.gz
    podman save --format docker-archive "$image" | gzip -n > "$directory/$filename"
    digest=$(sha256sum "$directory/$filename" | cut -d' ' -f1)
    printf '%s\t%s\t%s\t%s\n' "$image" "$id" "$filename" "$digest" >> "$tmp"
  done
  mv "$tmp" "$manifest"
  echo "PASS: exported $# immutable image archives"
else
  [[ -s "$manifest" ]] || { echo "Missing archive manifest" >&2; exit 2; }
  for image in "$@"; do
    row=$(awk -F '\t' -v image="$image" '$1==image {print; n++} END {if(n!=1) exit 1}' "$manifest") || { echo "Missing/duplicate image: $image" >&2; exit 1; }
    IFS=$'\t' read -r ref expected_id filename digest <<< "$row"
    [[ "$filename" =~ ^[a-f0-9]{64}\.tar\.gz$ && "$digest" =~ ^[a-f0-9]{64}$ && "$expected_id" =~ ^sha256:[a-f0-9]{64}$ ]] || { echo "Invalid manifest entry" >&2; exit 1; }
    [[ "$(sha256sum "$directory/$filename" | cut -d' ' -f1)" == "$digest" ]] || { echo "Archive checksum mismatch: $filename" >&2; exit 1; }
    gzip -dc "$directory/$filename" | podman load >/dev/null
    actual=$(podman image inspect "$ref" --format '{{.Id}}')
    actual="sha256:${actual#sha256:}"
    [[ "$actual" == "$expected_id" ]] || { echo "Image ID mismatch for $ref" >&2; exit 1; }
    echo "PASS: $ref archive checksum and loaded image ID verified"
  done
fi
