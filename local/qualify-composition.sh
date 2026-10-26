#!/usr/bin/env bash
# Explicit Fatline composition gate registry. Fail closed on unknown gates.
set -Eeuo pipefail
[[ $# == 4 && $1 == --composition && $3 == --gate ]] || {
  echo "Usage: $0 --composition fatline --gate GATE" >&2; exit 2;
}
composition=$2 gate=$4
[[ $composition == fatline ]] || { echo "Unsupported composition: $composition" >&2; exit 2; }
cd "$(dirname "$0")"
run_gate() {
  case "$1" in
    baseline) make qualify-composition-baseline ;;
    lifecycle-dispatch) make qualify-composition-lifecycle-dispatch ;;
    timer-recovery) make qualify-composition-lifecycle-timer-recovery ;;
    acl-isolation) make qualify-composition-acl-isolation ;;
    skymill-acl) make qualify-composition-skymill-acl ;;
    cold-start) make qualify-composition-cold-start ;;
    *) echo "Unknown Fatline gate: $1" >&2; exit 2 ;;
  esac
}
if [[ $gate == all ]]; then
  echo "CHECK: all registered Fatline composition gates"
  for name in baseline acl-isolation skymill-acl cold-start timer-recovery lifecycle-dispatch; do
    echo "CHECK: Fatline composition gate $name"
    run_gate "$name"
    echo "PASS: Fatline composition gate $name"
  done
else
  run_gate "$gate"
fi
