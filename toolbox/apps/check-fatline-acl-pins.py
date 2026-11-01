#!/usr/bin/env python3
"""Fail production ACL qualification when policy provenance drifts from source pins."""
import json
import re
import sys
from pathlib import Path


def main() -> int:
    if len(sys.argv) != 4:
        print("usage: check-fatline-acl-pins.py POLICY EXPECTED_LOGMA EXPECTED_SKYMILL", file=sys.stderr)
        return 2
    policy_path = Path(sys.argv[1])
    expected = {"logma": sys.argv[2], "skymill": sys.argv[3]}
    if any(re.fullmatch(r"[0-9a-f]{40}", value) is None for value in expected.values()):
        print("FAIL: expected component revisions must be full Git SHAs", file=sys.stderr)
        return 2
    try:
        policy = json.loads(policy_path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as exc:
        print(f"FAIL: cannot read Agni ACL policy: {exc}", file=sys.stderr)
        return 1
    actual = policy.get("componentRevisions", {})
    for component, revision in expected.items():
        if actual.get(component) != revision:
            print(
                f"FAIL: Agni ACL policy {component} revision {actual.get(component)!r} "
                f"does not match pinned source {revision}",
                file=sys.stderr,
            )
            return 1
    print(
        "PASS: Agni ACL policy provenance matches pinned Logma and Skymill "
        f"({expected['logma'][:7]}, {expected['skymill'][:7]})"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
