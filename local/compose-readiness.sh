#!/usr/bin/env bash
set -Eeuo pipefail
state="${1:?release state required}"
missing=0
for component in redis nginx logma skymill; do
  found=''
  if [[ -d "$state/$component" ]]; then
    for record in "$state/$component/"*.json; do
      [[ -f "$record" ]] || continue
      if jq -e --arg c "$component" '.schema == 1 and .component == $c and .status == "qualified" and (.qualified_tag | type == "string") and (.image_id | test("^sha256:[a-f0-9]{64}$"))' "$record" >/dev/null 2>&1; then
        version="$(jq -r .version "$record")"
        if [[ "$version" =~ ^[0-9]{4}[.][0-9]{2}[.][0-9]{2}([.][0-9]+)?$ ]]; then
          if [[ -z "$found" || "$(printf '%s\n%s\n' "$found" "$version" | sort -V | tail -1)" == "$version" ]]; then found="$version"; fi
        fi
      fi
    done
  fi
  if [[ -n "$found" ]]; then echo "$component: qualified $found"; else echo "$component: no qualified release"; missing=1; fi
done
if (( missing )); then echo "Composition blocked: all four qualified releases required" >&2; exit 1; fi
echo "All release records qualified; runtime composition is a separate gate"
