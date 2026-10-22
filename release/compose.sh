#!/usr/bin/env bash
set -euo pipefail

# Container-side release selection; the host only invokes this Nix app.
name= with= ledger= workspace=/workspaces assembly=/workspaces/agni/local/fatline
while (($#)); do
  case "$1" in
    --name) name="${2:?}"; shift 2 ;;
    --with) with="${2:?}"; shift 2 ;;
    --ledger) ledger="${2:?}"; shift 2 ;;
    --workspace) workspace="${2:?}"; shift 2 ;;
    --assembly) assembly="${2:?}"; shift 2 ;;
    *) echo "Unknown compose argument: $1" >&2; exit 2 ;;
  esac
done
[[ "$name" =~ ^[a-z][a-z0-9-]*$ ]] || { echo "Invalid composition name" >&2; exit 2; }
[[ -n "$ledger" && -d "$ledger" ]] || { echo "Release ledger must be mounted into nix.xd; no host fallback" >&2; exit 1; }
root="$workspace/.compositions/$name"
mkdir -p "$root"
lock="$root/composition.lock.json"
if [[ -n "$with" ]]; then
  [[ ! -e "$lock" ]] || { echo "Composition lock already exists; reuse with WITH omitted" >&2; exit 1; }
  components='{}'
  for spec in $with; do
    [[ "$spec" == *@* ]] || { echo "Expected component@version: $spec" >&2; exit 2; }
    component="${spec%%@*}"; selector="${spec#*@}"
    [[ "$component" =~ ^[a-z][a-z0-9-]*$ ]] || exit 2
    if [[ "$selector" == qualified ]]; then
      # Choose latest qualified CalVer using numeric date/micro sorting.
      selector="$(find "$ledger/$component" -maxdepth 1 -name '*.json' -type f -print0 2>/dev/null |
        xargs -0 -r jq -r 'select(.status == "qualified") | .version' |
        sort -V | tail -1)"
    fi
    [[ "$selector" =~ ^[0-9]{4}\.[0-9]{2}\.[0-9]{2}(\.[0-9]+)?$ ]] || { echo "No qualified CalVer for $component" >&2; exit 1; }
    record="$ledger/$component/$selector.json"
    [[ -f "$record" ]] || { echo "Missing release $component@$selector" >&2; exit 1; }
    jq -e --arg component "$component" --arg version "$selector" '
      .status == "qualified" and .component == $component and .version == $version and
      (.qualified_tag | type == "string") and (.image_id | test("^sha256:[a-f0-9]{64}$")) and
      (.source_sha | type == "string") and (.nix_output | type == "string")
    ' "$record" >/dev/null
    components="$(jq -cn --argjson previous "$components" --arg key "$component" --slurpfile record "$record" '
      if $previous[$key] then error("duplicate component") else $previous + {($key): $record[0]} end')"
  done
  [[ "$(jq 'keys | sort == ["logma","nginx","redis","skymill"]' <<< "$components")" == true ]] || {
    echo "Fatline requires logma nginx redis skymill" >&2; exit 1;
  }
  git -C "$assembly" diff --quiet && git -C "$assembly" diff --cached --quiet || {
    echo "Assembly source is dirty" >&2; exit 1;
  }
  revision="$(git -C "$assembly" rev-parse HEAD)"
  jq -cn --arg name "$name" --arg rev "$revision" --argjson components "$components"     '{schema:1,name:$name,assembly_sha:$rev,components:$components}' > "$lock.tmp"
  mv "$lock.tmp" "$lock"
fi
[[ -f "$lock" ]] || { echo "Missing lock: supply WITH" >&2; exit 1; }
[[ "$(git -C "$assembly" rev-parse HEAD)" == "$(jq -r .assembly_sha "$lock")" ]] || {
  echo "Assembly revision drift" >&2; exit 1;
}
for component in logma nginx redis skymill; do
  version="$(jq -r --arg c "$component" '.components[$c].version' "$lock")"
  record="$ledger/$component/$version.json"
  jq -e --slurpfile current "$record" --arg c "$component" '.components[$c] == $current[0] and $current[0].status == "qualified"' "$lock" >/dev/null
done
# Nix consumes an explicit, frozen manifest; never float qualified selectors.
jq '{redis:.components.redis.qualified_tag,nginx:.components.nginx.qualified_tag,logma:.components.logma.qualified_tag,skymill:.components.skymill.qualified_tag}' "$lock" > "$root/images.json"
cp "$assembly/composition.nix" "$root/composition.nix"
cp "$assembly/composition-config.nix" "$root/composition-config.nix"
cp "$assembly/flake.lock" "$root/upstream.lock"
rev="$(jq -r '.nodes.nixpkgs.locked.rev' "$root/upstream.lock")"
cat > "$root/flake.nix" <<EOF
{
  description = "Fatline pinned release composition";
  inputs.nixpkgs.url = "github:NixOS/nixpkgs/$rev";
  outputs = { self, nixpkgs }:
    let
      system = "x86_64-linux";
      pkgs = import nixpkgs { inherit system; };
      config = import ./composition-config.nix;
      components = builtins.fromJSON (builtins.readFile ./images.json);
    in {
      packages.${system}.default = import ./composition.nix {
        inherit pkgs config components;
        lib = pkgs.lib;
      };
    };
}
EOF
# Nix owns the composition derivation and its content-addressed output.
cd "$root"
nix flake lock
nix build .#default --no-link
out="$(nix path-info .#default)"
jq -n --arg path "$out" --arg name "$name" '{name:$name,nix_output:$path}' > "$root/output.json"
printf 'Composition built: %s\n' "$out"
printf 'Runtime qualification and activation are separate gates.\n'
