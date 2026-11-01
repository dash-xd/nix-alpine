#!/usr/bin/bash
set -Eeuo pipefail

mode=run
if [[ "${1:-}" == --cleanup ]]; then
  mode=cleanup
  composition="${2:?composition prefix required}"
  run_id="${3:?run id required}"
else
  composition="${1:?composition prefix required}"
  run_id="${2:?run id required}"
  runtime="${3:-10m}"
  payload="${4:?tester payload required}"
fi

[[ "$composition" =~ ^[a-z_][a-z0-9_-]{0,18}$ ]] || { echo "invalid composition prefix" >&2; exit 2; }
[[ "$run_id" =~ ^[A-Za-z0-9_.-]{1,48}$ ]] || { echo "invalid run id" >&2; exit 2; }
if [[ "$mode" == run ]]; then
  [[ "$runtime" =~ ^[1-9][0-9]*(s|m|h)$ ]] || { echo "invalid runtime" >&2; exit 2; }
  [[ -f "$payload" ]] || { echo "missing tester payload: $payload" >&2; exit 2; }
fi

app_user="$(</run/fatline-console/app-user)"
[[ "$app_user" =~ ^${composition}-[a-f0-9]{12}$ ]] || {
  echo "guest app identity does not match composition prefix: $app_user" >&2
  exit 1
}
uid="$(/usr/bin/id -u "$app_user")"
home="$(/usr/bin/getent passwd "$app_user" | /usr/bin/cut -d: -f6)"
runtime_dir="/run/user/$uid"
unit="fatline-qualify-$run_id"
stage="$home/.local/share/fatline-qualification/$run_id"

if [[ "$mode" == cleanup ]]; then
  /usr/sbin/runuser -u "$app_user" -- /usr/bin/env \
    HOME="$home" USER="$app_user" LOGNAME="$app_user" \
    XDG_RUNTIME_DIR="$runtime_dir" DBUS_SESSION_BUS_ADDRESS="unix:path=$runtime_dir/bus" \
    /usr/bin/systemctl --user stop "$unit.service" >/dev/null 2>&1 || true
  /usr/bin/rm -rf -- "$stage"
  exit 0
fi

[[ -S "$runtime_dir/bus" ]] || { echo "composition user systemd bus is unavailable" >&2; exit 1; }
/usr/bin/systemctl is-active --quiet "user@$uid.service" || {
  echo "composition user systemd manager is not active" >&2
  exit 1
}

cleanup() {
  set +e
  /usr/sbin/runuser -u "$app_user" -- /usr/bin/env \
    HOME="$home" USER="$app_user" LOGNAME="$app_user" \
    XDG_RUNTIME_DIR="$runtime_dir" DBUS_SESSION_BUS_ADDRESS="unix:path=$runtime_dir/bus" \
    /usr/bin/systemctl --user stop "$unit.service" >/dev/null 2>&1
  /usr/bin/rm -rf -- "$stage"
}
trap cleanup EXIT

/usr/bin/install -d -o "$app_user" -g "$app_user" -m 0700 "$stage"
/usr/bin/install -o "$app_user" -g "$app_user" -m 0700 "$payload" "$stage/tester"

set +e
/usr/sbin/runuser -u "$app_user" -- /usr/bin/env \
  HOME="$home" USER="$app_user" LOGNAME="$app_user" \
  XDG_RUNTIME_DIR="$runtime_dir" DBUS_SESSION_BUS_ADDRESS="unix:path=$runtime_dir/bus" \
  /usr/bin/systemd-run --user --quiet --wait --pipe --collect \
    --unit="$unit" --property="RuntimeMaxSec=$runtime" \
    --setenv="COREOS_COMPOSITION_NAME=$composition" \
    --setenv="HOME=$home" --setenv="USER=$app_user" --setenv="LOGNAME=$app_user" \
    --setenv="XDG_RUNTIME_DIR=$runtime_dir" \
    --working-directory="$stage" "$stage/tester"
rc=$?
set -e

echo "TRANSIENT_UNIT=$unit.service"
echo "TRANSIENT_USER=$app_user"
echo "TRANSIENT_EXIT_CODE=$rc"
/usr/bin/journalctl "_UID=$uid" "_SYSTEMD_USER_UNIT=$unit.service" --no-pager -o cat -n 120 || true

cleanup
trap - EXIT
/usr/bin/test ! -e "$stage" || { echo "tester staging directory was not cleaned" >&2; exit 1; }
remaining="$(/usr/sbin/runuser -u "$app_user" -- /usr/bin/env \
  HOME="$home" USER="$app_user" LOGNAME="$app_user" \
  XDG_RUNTIME_DIR="$runtime_dir" DBUS_SESSION_BUS_ADDRESS="unix:path=$runtime_dir/bus" \
  /usr/bin/systemctl --user show -p LoadState --value "$unit.service" 2>/dev/null || true)"
if [[ "$remaining" == loaded ]]; then
  echo "transient unit remained loaded after collection" >&2
  exit 1
fi
(( rc == 0 )) || exit "$rc"
echo "PASS: transient qualification ran as $app_user and cleaned its staging files"
