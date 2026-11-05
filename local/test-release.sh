#!/usr/bin/env bash
set -Eeuo pipefail
cd "$(dirname "$0")"
for cmd in jq flock podman; do command -v "$cmd" >/dev/null || { echo "missing $cmd" >&2; exit 2; }; done
state="$(mktemp -d)"
trap 'rm -rf "$state"' EXIT
export RELEASE_STATE="$state"
component="sample-component"
version="2026.10.21.1"
image_id="sha256:$(printf '%064d' 1)"
tag="localhost/nix.xd/$component:candidate-$version"
qualified="localhost/nix.xd/$component:qualified-$version"
mkdir "$state/bin"
cat > "$state/bin/podman" <<'PODMAN'
#!/usr/bin/env bash
set -Eeuo pipefail
store="${RELEASE_STATE}/tags"
mkdir -p "$store"
case "$1 $2" in
  "image inspect")
    ref="$3"
    [[ "$ref" == sha256:* ]] && { [[ "$ref" =~ ^sha256:[0-9a-f]{64}$ ]] || exit 1; echo "$ref"; exit 0; }
    file="$store/${ref//\//_}"
    [[ -f "$file" ]] || exit 1
    cat "$file"
    ;;
  "tag "*)
    ref="$2"; dest="$3"
    [[ "$ref" =~ ^sha256:[0-9a-f]{64}$ ]] || exit 1
    printf '%s\n' "$ref" > "$store/${dest//\//_}"
    ;;
  *) echo "unexpected podman call: $*" >&2; exit 2 ;;
esac
PODMAN
chmod +x "$state/bin/podman"
export PATH="$state/bin:$PATH"
jq -n --arg component "$component" --arg version "$version" \
  --arg source_sha "$(printf '%040d' 1)" --arg flake_lock_sha256 "$(printf '%064d' 2)" \
  '{schema:1,component:$component,version:$version,source_sha:$source_sha,flake_lock_sha256:$flake_lock_sha256,flake_ref:"/workspaces/example#image",nix_output:"/nix/store/example.tar.gz"}' > "$state/metadata.json"
jq -n --arg image_id "$image_id" '{image_id:$image_id,nix_output:"/nix/store/example.tar.gz",archive_sha256:("a"*64)}' > "$state/import.json"
bash ./release-ledger.sh candidate "$component" "$version" "$state/metadata.json" "$state/import.json" > /dev/null
jq -e '.status == "candidate" and .candidate_tag == "localhost/nix.xd/sample-component:candidate-2026.10.21.1"' "$state/$component/$version.json" >/dev/null
if bash ./release-ledger.sh candidate "$component" "$version" "$state/metadata.json" "$state/import.json" >/dev/null 2>&1; then
  echo "FAIL: version rebinding accepted" >&2; exit 1
fi
jq -n --arg image_id "$image_id" --arg source_sha "$(printf '%040d' 1)" '{schema:1,image_id:$image_id,source_sha:$source_sha,nix_output:"/nix/store/example.tar.gz",gates:[{name:"runtime-check",sha256:("b"*64),exit_code:1}]}' > "$state/bad.json"
if bash ./release-ledger.sh qualify "$component" "$version" "$state/bad.json" >/dev/null 2>&1; then
  echo "FAIL: nonzero qualification accepted" >&2; exit 1
fi
[[ ! -f "$state/tags/${qualified//\//_}" ]] || { echo "FAIL: qualified tag was written" >&2; exit 1; }
jq -n --arg image_id "$image_id" --arg source_sha "$(printf '%040d' 1)" '{schema:1,image_id:$image_id,source_sha:$source_sha,nix_output:"/nix/store/example.tar.gz",gates:[{name:"runtime-check",sha256:("b"*64),exit_code:0},{name:"custom-integration",sha256:("c"*64),exit_code:0}]}' > "$state/good.json"
bash ./release-ledger.sh qualify "$component" "$version" "$state/good.json" > /dev/null
jq -e '.status == "qualified" and .qualified_tag == "localhost/nix.xd/sample-component:qualified-2026.10.21.1" and (.gates | length == 2)' "$state/$component/$version.json" >/dev/null
printf 'sha256:%064d\n' 3 > "$state/tags/${qualified//\//_}"
if bash ./release-ledger.sh qualify "$component" "$version" "$state/good.json" >/dev/null 2>&1; then
  echo "FAIL: qualified ledger replay accepted" >&2; exit 1
fi
jq -n --arg image_id "$image_id" --arg source_sha "$(printf '%040d' 1)" '{schema:1,image_id:$image_id,source_sha:$source_sha,nix_output:"/nix/store/example.tar.gz",gates:[{name:"duplicate",sha256:("b"*64),exit_code:0},{name:"duplicate",sha256:("c"*64),exit_code:0}]}' > "$state/duplicate.json"
if bash ./release-ledger.sh qualify "$component" "$version" "$state/duplicate.json" >/dev/null 2>&1; then
  echo "FAIL: duplicate caller gates accepted" >&2; exit 1
fi
echo "Generic release ledger contract tests passed"
