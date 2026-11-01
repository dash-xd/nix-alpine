#!/usr/bin/env bash
set -Eeuo pipefail

host="${1:?guest host required}"
port="${2:?guest SSH port required}"
key="${3:?SSH private key required}"
composition="${4:?composition required}"
runtime="${5:-10m}"
payload="${6:-$(dirname "$0")/coreos-guest-transient-smoke.sh}"
remote_user="${COREOS_GUEST_SSH_USER:-core}"
payload_name="$(basename "$payload")"
run_id="fatline-$(date -u +%Y%m%dT%H%M%SZ)-$$"
runner="$(dirname "$0")/coreos-guest-transient-run.sh"
known_hosts="$(mktemp)"
private_key="$(mktemp)"
remote_dir="/var/tmp/$run_id"

[[ "$port" =~ ^[0-9]+$ ]] && (( port >= 1 && port <= 65535 )) || { echo "invalid SSH port" >&2; exit 2; }
[[ "$composition" =~ ^[a-z_][a-z0-9_-]{0,18}$ ]] || { echo "invalid composition prefix" >&2; exit 2; }
[[ "$runtime" =~ ^[1-9][0-9]*(s|m|h)$ ]] || { echo "invalid transient runtime" >&2; exit 2; }
[[ "$remote_user" =~ ^[a-z_][a-z0-9_-]{0,31}$ ]] || { echo "invalid SSH login user" >&2; exit 2; }
[[ "$host" =~ ^[A-Za-z0-9._:-]+$ ]] || { echo "invalid SSH host" >&2; exit 2; }
[[ "$payload_name" =~ ^[A-Za-z0-9_.-]+$ ]] || { echo "invalid tester filename" >&2; exit 2; }
[[ -x "$key" && -r "$payload" && -r "$runner" ]] || { echo "key or transient tester input is missing" >&2; exit 2; }
install -m 0600 "$key" "$private_key"

cleanup() {
  set +e
  ssh "${ssh_opts[@]}" "$remote_user@$host" \
    "sudo '$remote_dir/runner' --cleanup '$composition' '$run_id'" >/dev/null 2>&1
  ssh "${ssh_opts[@]}" "$remote_user@$host" "rm -rf -- '$remote_dir'" >/dev/null 2>&1
  rm -f "$known_hosts" "$private_key"
}
trap cleanup EXIT

common=( -i "$private_key" -p "$port" -o BatchMode=yes -o ConnectTimeout=8
  -o StrictHostKeyChecking=accept-new -o UserKnownHostsFile="$known_hosts"
  -o ServerAliveInterval=10 -o ServerAliveCountMax=3 )
ssh_opts=("${common[@]}")
scp_opts=( -i "$private_key" -P "$port" -o BatchMode=yes -o ConnectTimeout=8
  -o StrictHostKeyChecking=accept-new -o UserKnownHostsFile="$known_hosts" )

ready=false
for _ in $(seq 1 60); do
  if ssh "${ssh_opts[@]}" "$remote_user@$host" 'sudo test -x /usr/bin/podman && sudo test -r /run/fatline-console/app-user'; then
    ready=true
    break
  fi
  sleep 2
done
[[ "$ready" == true ]] || { echo "guest SSH or Fatline app identity did not become ready" >&2; exit 1; }

ssh "${ssh_opts[@]}" "$remote_user@$host" "install -d -m 0700 '$remote_dir'"
scp "${scp_opts[@]}" "$runner" "$payload" "$remote_user@$host:$remote_dir/"
ssh "${ssh_opts[@]}" "$remote_user@$host" \
  "sudo install -m 0700 '$remote_dir/coreos-guest-transient-run.sh' '$remote_dir/runner'; sudo install -m 0700 '$remote_dir/$payload_name' '$remote_dir/tester'"
ssh "${ssh_opts[@]}" "$remote_user@$host" \
  "sudo '$remote_dir/runner' '$composition' '$run_id' '$runtime' '$remote_dir/tester'"
