#!/usr/bin/env bash
# Explicit Fatline composition gate registry. Fail closed on unknown gates.
set -Eeuo pipefail
composition=""
gate=""
scope="${SCOPE:-dev}"
container="${CONTAINER:-nix-alpine-$scope}"
workspaces="${WORKSPACES:-$HOME/workspace/nix}"
[[ $# -ge 4 && $1 == --composition && $3 == --gate ]] || {
  echo "Usage: $0 --composition fatline|logma-image|skymill-provider --gate GATE --scope SCOPE --container CONTAINER --workspaces PATH" >&2
  exit 2
}
composition=$2
gate=$4
shift 4
while (($#)); do
  case "$1" in
    --scope) (($# >= 2)) || { echo "--scope requires a value" >&2; exit 2; }; scope=$2; shift 2 ;;
    --container) (($# >= 2)) || { echo "--container requires a value" >&2; exit 2; }; container=$2; shift 2 ;;
    --workspaces) (($# >= 2)) || { echo "--workspaces requires a value" >&2; exit 2; }; workspaces=$2; shift 2 ;;
    *) echo "Unknown argument: $1" >&2; exit 2 ;;
  esac
done
[[ -n "$scope" && -n "$container" && -n "$workspaces" ]] || { echo "scope, container, and workspaces are required" >&2; exit 2; }
cd "$(dirname "$0")"
make_with_context() {
  printf 'INFO: dispatcher make context scope=%s container=%s workspaces=%s target=%s\n' "$scope" "$container" "$workspaces" "$1" >&2
  command make SCOPE="$scope" CONTAINER="$container" WORKSPACES="$workspaces" "$@"
}
# Component artifact workflows share the composition entrypoint but do not
# inherit Fatline runtime gates or claim release qualification.
case "$composition" in
  logma-image)
    [[ "$gate" == all ]] || { echo "logma-image does not support GATE=$gate" >&2; exit 2; }
    make_with_context qualify-composition-logma-image; exit $? ;;
  skymill-provider)
    [[ "$gate" == all ]] || { echo "skymill-provider does not support GATE=$gate" >&2; exit 2; }
    make_with_context qualify-composition-skymill-provider; exit $? ;;
  fatline) ;;
  *) echo "Unsupported composition: $composition" >&2; exit 2 ;;
esac
# Every Fatline runtime gate uses the provider image built from the pinned source.
make_with_context qualify-composition-logma-image
run_gate() {
  case "$1" in
    baseline) make_with_context qualify-composition-baseline ;;
    lifecycle-dispatch) make_with_context qualify-composition-lifecycle-dispatch ;;
    timer-recovery) make_with_context qualify-composition-lifecycle-timer-recovery ;;
    acl-isolation) make_with_context qualify-composition-acl-isolation ;;
    skymill-acl) make_with_context qualify-composition-skymill-acl ;;
    skymill-provider) make_with_context qualify-composition-skymill-provider ;;
    bootstrap-unit) make_with_context qualify-composition-bootstrap-unit ;;
    coordinated-restart) make_with_context qualify-composition-coordinated-restart ;;
    live-redis-recovery) make_with_context qualify-composition-live-redis-recovery ;;
    function-reconciliation) make_with_context qualify-composition-function-reconciliation ;;
    lifecycle-crash) make_with_context qualify-composition-lifecycle-crash ;;
    crash-window) make_with_context qualify-composition-crash-window ;;
    strict-readiness) make_with_context qualify-composition-strict-readiness ;;
    production-acl) make_with_context qualify-composition-production-acl ;;
    cold-start) make_with_context qualify-composition-cold-start ;;
    *) echo "Unknown Fatline gate: $1" >&2; exit 2 ;;
  esac
}
if [[ $gate == all ]]; then
  echo "CHECK: all registered Fatline composition gates"
  for name in baseline production-acl cold-start timer-recovery lifecycle-dispatch skymill-provider strict-readiness; do
    echo "CHECK: Fatline composition gate $name"
    run_gate "$name"
    echo "PASS: Fatline composition gate $name"
  done
else
  run_gate "$gate"
fi
