#!/usr/bin/env bash
set -Eeuo pipefail

[[ $# == 4 ]] || {
  echo "usage: $0 RUN_PREFIX DRY_RUN WORKSPACES STOP_TIMEOUT" >&2
  exit 2
}

run_prefix=$1
dry_run=$2
workspaces=$3
stop_timeout=$4

[[ "$run_prefix" =~ ^[A-Za-z0-9][A-Za-z0-9_.-]*$ ]] || {
  echo "RUN_PREFIX must be a literal resource prefix" >&2
  exit 2
}
(( ${#run_prefix} >= 16 )) || {
  echo "RUN_PREFIX must identify one run (at least 16 characters)" >&2
  exit 2
}
[[ "$dry_run" == 0 || "$dry_run" == 1 ]] || {
  echo "DRY_RUN must be 0 or 1" >&2
  exit 2
}
[[ "$stop_timeout" =~ ^[0-9]+$ ]] && (( stop_timeout >= 1 && stop_timeout <= 300 )) || {
  echo "STOP_TIMEOUT must be between 1 and 300 seconds" >&2
  exit 2
}

for cmd in podman systemctl realpath find; do
  command -v "$cmd" >/dev/null || { echo "Missing host command: $cmd" >&2; exit 2; }
done
systemctl --user show-environment >/dev/null || {
  echo "The user systemd manager is unavailable" >&2
  exit 1
}

workspaces=$(realpath -m -- "$workspaces")
quadlet_dir="${XDG_CONFIG_HOME:-$HOME/.config}/containers/systemd"
systemd_dir="${XDG_CONFIG_HOME:-$HOME/.config}/systemd/user"
runtime_dir="$workspaces/.nix-alpine-runtime"
if [[ -L "$runtime_dir" ]]; then
  echo "Refusing cleanup: workspace runtime root is a symlink: $runtime_dir" >&2
  exit 1
elif [[ -e "$runtime_dir" ]]; then
  [[ -d "$runtime_dir" ]] || {
    echo "Refusing cleanup: workspace runtime root is not a directory: $runtime_dir" >&2
    exit 1
  }
  resolved_runtime_dir=$(realpath -- "$runtime_dir")
  [[ "$resolved_runtime_dir" == "$runtime_dir" ]] || {
    echo "Refusing cleanup: workspace runtime root resolves elsewhere: $resolved_runtime_dir" >&2
    exit 1
  }
fi

units=()
quadlets=()
unit_files=()
containers=()
networks=()
runtime_dirs=()

matches_prefix() {
  case "$1" in "$run_prefix"*) return 0 ;; *) return 1 ;; esac
}

units_output=$(systemctl --user list-units --all --no-legend --no-pager)
while IFS= read -r unit; do
  [[ -n "$unit" ]] && matches_prefix "$unit" && units+=("$unit")
done < <(awk '{print $1}' <<< "$units_output")

for root in "$quadlet_dir" "$systemd_dir"; do
  [[ -d "$root" ]] || continue
  for path in "$root/$run_prefix"*; do
    [[ -f "$path" ]] || continue
    if [[ "$root" == "$quadlet_dir" ]]; then
      case "$path" in
        *.container|*.volume|*.network|*.pod|*.kube|*.image|*.build) quadlets+=("$path") ;;
      esac
    else
      case "$path" in
        *.service|*.timer|*.socket|*.path|*.target) unit_files+=("$path") ;;
      esac
    fi
  done
done

containers_output=$(podman ps -a --format '{{.Names}}')
while IFS= read -r name; do
  [[ -n "$name" ]] && matches_prefix "$name" && containers+=("$name")
done <<< "$containers_output"

networks_output=$(podman network ls --format '{{.Name}}')
while IFS= read -r name; do
  [[ -n "$name" ]] && matches_prefix "$name" && networks+=("$name")
done <<< "$networks_output"

if [[ -d "$runtime_dir" ]]; then
  for path in "$runtime_dir/$run_prefix".*; do
    [[ -d "$path" && ! -L "$path" ]] || continue
    resolved_path=$(realpath -- "$path")
    [[ "$resolved_path" == "$runtime_dir/"* ]] || {
      echo "Refusing cleanup: runtime path escaped workspace root: $resolved_path" >&2
      exit 1
    }
    runtime_dirs+=("$resolved_path")
  done
fi

print_items() {
  local label=$1
  shift
  printf '%s (%d):\n' "$label" "$#"
  if (($# == 0)); then
    echo "  none"
    return
  fi
  printf '  %s\n' "$@"
}

echo "Scoped cleanup for literal prefix: $run_prefix"
print_items "user units to stop" "${units[@]}"
print_items "Quadlet definitions to remove" "${quadlets[@]}"
print_items "user unit files to remove" "${unit_files[@]}"
print_items "Podman containers to remove" "${containers[@]}"
print_items "Podman networks to remove" "${networks[@]}"
print_items "workspace runtime directories to remove" "${runtime_dirs[@]}"
if [[ "$dry_run" == 1 ]]; then
  echo "DRY_RUN=1: no changes. Review the exact matches, then rerun with DRY_RUN=0."
  echo "Images, Podman volumes, Nix stores, logs, source checkouts, and other workspace files are preserved."
  exit 0
fi

for unit in "${units[@]}"; do
  if systemctl --user is-active --quiet "$unit"; then
    echo "Stopping user unit: $unit"
    systemctl --user stop "$unit"
  fi
  systemctl --user reset-failed "$unit" >/dev/null 2>&1 || true
done

for path in "${quadlets[@]}" "${unit_files[@]}"; do
  echo "Removing unit definition: $path"
  rm -- "$path"
done
systemctl --user daemon-reload

for name in "${containers[@]}"; do
  state=$(podman inspect "$name" --format '{{.State.Status}}')
  if [[ "$state" == running || "$state" == paused ]]; then
    echo "Stopping container: $name"
    podman stop --time "$stop_timeout" "$name"
  fi
  echo "Removing container: $name"
  podman rm --force "$name"
done

for name in "${networks[@]}"; do
  echo "Removing network: $name"
  podman network rm "$name"
done

for path in "${runtime_dirs[@]}"; do
  [[ -d "$path" && ! -L "$path" ]] || {
    echo "Refusing to remove changed runtime path: $path" >&2
    exit 1
  }
  resolved_path=$(realpath -- "$path")
  [[ "$resolved_path" == "$runtime_dir/"* ]] || {
    echo "Refusing to remove changed runtime path outside workspace: $resolved_path" >&2
    exit 1
  }
  echo "Removing workspace runtime directory: $path"
  rm -rf -- "$path"
done

if [[ -d "$runtime_dir" ]]; then
  find "$runtime_dir" -mindepth 1 -depth -type d -empty -delete
fi
echo "Scoped cleanup complete. Shared images, volumes, stores, logs, and checkouts were preserved."
