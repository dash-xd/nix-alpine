#!/usr/bin/env bash
set -Eeuo pipefail

[[ $# -ge 4 && $3 == -- ]] || {
  echo "usage: $0 LOG_DIR LOG_NAME -- COMMAND [ARG...]" >&2
  exit 2
}
log_dir=$1
log_name=$2
shift 3
[[ "$log_name" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]] || {
  echo "invalid log name: $log_name" >&2
  exit 2
}
mkdir -p "$log_dir"
timestamp=$(date -u +%Y%m%dT%H%M%SZ)
log_file="$log_dir/$log_name-$timestamp-$$.log"
( set -o noclobber; : > "$log_file" ) || {
  echo "cannot create log file: $log_file" >&2
  exit 1
}
{
  printf 'qualification command:'
  printf ' %q' "$@"
  printf '\nqualification started at: %s\n' "$(date -u --iso-8601=seconds)"
} | tee "$log_file"
set +e
"$@" 2>&1 | tee -a "$log_file"
pipeline_status=( "${PIPESTATUS[@]}" )
set -e
command_status=${pipeline_status[0]:-1}
tee_status=${pipeline_status[1]:-1}
if (( command_status == 0 && tee_status != 0 )); then
  command_status=$tee_status
fi
printf 'qualification exit code: %s\n' "$command_status" | tee -a "$log_file"
printf 'qualification log: %s\n' "$log_file" | tee -a "$log_file"
exit "$command_status"
