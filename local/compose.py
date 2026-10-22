#!/usr/bin/env python3
"""Resolve qualified local releases into a locked, reproducible composition selection.

This is intentionally host-side: Podman and the release ledger live on the host.
Nix evaluation/build remains inside nix-alpine-dev.
"""
import argparse
import datetime
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import tempfile

IDENT = re.compile(r"^[a-z][a-z0-9-]*$")
VERSION = re.compile(r"^[0-9]{4}\\.(?:0[1-9]|1[0-2])\\.(?:0[1-9]|[12][0-9]|3[01])(?:\\.(?:0|[1-9][0-9]*))?$")
IMAGE = re.compile(r"^sha256:[0-9a-f]{64}$")

def execute(*cmd):
    return subprocess.check_output(cmd, text=True).strip()

def image_id(ref):
    raw = execute("podman", "image", "inspect", ref, "--format", "{{.Id}}")
    return raw if raw.startswith("sha256:") else "sha256:" + raw

def atomic(path, obj):
    path.parent.mkdir(parents=True, exist_ok=True)
    fd, tmp = tempfile.mkstemp(dir=path.parent, prefix=".compose-")
    try:
        with os.fdopen(fd, "w") as out:
            json.dump(obj, out, sort_keys=True, indent=2)
            out.write("\\n")
            out.flush()
            os.fsync(out.fileno())
        os.replace(tmp, path)
    finally:
        if os.path.exists(tmp):
            os.unlink(tmp)

def qualified(state, component, selector):
    directory = state / component
    if not directory.is_dir():
        raise ValueError(f"no releases for {component}")
    if selector == "qualified":
        records = [json.loads(p.read_text()) for p in directory.glob("*.json")]
        records = [r for r in records if r.get("status") == "qualified" and VERSION.fullmatch(r.get("version", ""))]
        if not records:
            raise ValueError(f"no qualified release for {component}")
        records.sort(key=lambda r: tuple(map(int, r["version"].split("."))))
        record = records[-1]
    else:
        if not VERSION.fullmatch(selector):
            raise ValueError(f"invalid CalVer: {selector}")
        path = directory / (selector + ".json")
        record = json.loads(path.read_text())
    if record.get("component") != component or record.get("status") != "qualified":
        raise ValueError(f"{component}@{selector} is not qualified")
    ident = record.get("image_id", "")
    tag = record.get("qualified_tag", "")
    if not IMAGE.fullmatch(ident) or not tag:
        raise ValueError(f"{component} has invalid qualified image identity")
    if image_id(tag) != ident or image_id(ident) != ident:
        raise ValueError(f"{component} Podman image identity mismatch")
    for field in ("source_sha", "flake_lock_sha256", "nix_output"):
        if not record.get(field):
            raise ValueError(f"{component} release missing {field}")
    return {k: record[k] for k in ("component", "version", "image_id", "qualified_tag", "source_sha", "flake_lock_sha256", "nix_output")}

def identity(lock):
    payload = json.dumps({"name": lock["name"], "assembly": lock["assembly"], "components": lock["components"]}, sort_keys=True, separators=(",", ":"))
    return hashlib.sha256(payload.encode()).hexdigest()

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("action", choices=("resolve", "show", "verify"))
    parser.add_argument("--name", required=True)
    parser.add_argument("--with", dest="selection", default="")
    parser.add_argument("--state", required=True)
    parser.add_argument("--compositions", required=True)
    parser.add_argument("--assembly", default="agni/local/fatline")
    args = parser.parse_args()
    if not IDENT.fullmatch(args.name):
        parser.error("invalid composition name")
    state = Path(args.state).expanduser()
    root = Path(args.compositions).expanduser() / args.name
    path = root / "composition.lock.json"
    if args.action == "resolve" and args.selection:
        selected = {}
        for spec in args.selection.split():
            component, separator, selector = spec.partition("@")
            if not separator or not IDENT.fullmatch(component) or component in selected:
                raise ValueError(f"invalid or repeated component selector: {spec}")
            selected[component] = qualified(state, component, selector)
        if not selected:
            raise ValueError("no components selected")
        # Preserve the assembly contract and its exact Git revision.
        assembly_path = Path(args.compositions).expanduser().parent / args.assembly
        if not (assembly_path / "composition.nix").is_file():
            raise ValueError(f"assembly not present: {assembly_path}")
        sha = execute("git", "-C", str(assembly_path), "rev-parse", "HEAD")
        if execute("git", "-C", str(assembly_path), "status", "--porcelain"):
            raise ValueError("assembly checkout is dirty")
        lock = {"schema": 1, "name": args.name, "assembly": {"path": str(assembly_path), "git_sha": sha}, "components": selected}
        lock["identity"] = identity(lock)
        if path.exists():
            old = json.loads(path.read_text())
            if old.get("identity") != lock["identity"]:
                raise ValueError("composition already locked to different inputs; choose another NAME (locks are immutable)")
        else:
            atomic(path, lock)
    else:
        if args.selection:
            raise ValueError("WITH only valid for resolve")
        lock = json.loads(path.read_text())
    if lock.get("schema") != 1 or lock.get("name") != args.name or lock.get("identity") != identity(lock):
        raise ValueError("invalid composition lock")
    for component, record in lock["components"].items():
        actual = qualified(state, component, record["version"])
        if actual != record:
            raise ValueError(f"{component} ledger drift")
    assembly = lock["assembly"]
    if execute("git", "-C", assembly["path"], "rev-parse", "HEAD") != assembly["git_sha"]:
        raise ValueError("assembly revision drift")
    if execute("git", "-C", assembly["path"], "status", "--porcelain"):
        raise ValueError("assembly checkout dirty")
    print(json.dumps(lock, indent=2, sort_keys=True))

if __name__ == "__main__":
    try:
        main()
    except (ValueError, OSError, subprocess.CalledProcessError) as exc:
        print(f"compose: {exc}", file=sys.stderr)
        sys.exit(1)
