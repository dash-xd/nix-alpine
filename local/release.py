#!/usr/bin/env python3
"""Local Nix-Alpine release ledger. No registry or external authority required."""
import argparse
import datetime as dt
import fcntl
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import tempfile

VERSION = re.compile(r"^[0-9]{4}\.(?:0[1-9]|1[0-2])\.(?:0[1-9]|[12][0-9]|3[01])(?:\.(?:0|[1-9][0-9]*))?$")

def run(*args, capture=True, cwd=None):
    return subprocess.run(args, cwd=cwd, check=True, text=True,
                          stdout=subprocess.PIPE if capture else None,
                          stderr=subprocess.PIPE if capture else None).stdout.strip() if capture else None

def version_valid(v):
    if not VERSION.fullmatch(v):
        return False
    parts = v.split(".")
    try:
        dt.date(*map(int, parts[:3]))
    except ValueError:
        return False
    return len(parts) == 3 or int(parts[3]) <= 18446744073709551615

def image_id(ref):
    return run("podman", "image", "inspect", ref, "--format", "{{.Id}}")

def atomic_json(path, obj):
    fd, name = tempfile.mkstemp(prefix=".release-", dir=path.parent)
    try:
        with os.fdopen(fd, "w") as out:
            json.dump(obj, out, indent=2, sort_keys=True)
            out.write("\n")
            out.flush()
            os.fsync(out.fileno())
        os.replace(name, path)
    finally:
        if os.path.exists(name):
            os.unlink(name)

def main():
    p = argparse.ArgumentParser()
    p.add_argument("action", choices=("version", "candidate", "qualify"))
    p.add_argument("--component", required=True)
    p.add_argument("--version")
    p.add_argument("--source", help="host checkout directory")
    p.add_argument("--image", help="already imported local Podman image reference")
    p.add_argument("--flake", help="path to flake inside Nix-Alpine container")
    p.add_argument("--target", help="Nix archive output, e.g. #provider-image")
    p.add_argument("--container", default="nix-alpine-dev")
    p.add_argument("--state", default=str(Path.home()/".local/state/nix-alpine/releases"))
    p.add_argument("--gates", nargs="+", default=["#qualify", "#qualify-integration"])
    a = p.parse_args()
    if not re.fullmatch(r"[a-z][a-z0-9-]*", a.component):
        p.error("component must be lowercase alphanumeric/hyphen")
    root = Path(a.state).expanduser().resolve() / a.component
    root.mkdir(parents=True, exist_ok=True)
    with (root / ".lock").open("a+") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        if a.action == "version":
            today = dt.datetime.now(dt.timezone.utc).strftime("%Y.%m.%d")
            i = 0
            while (root / ((today if i == 0 else f"{today}.{i}") + ".json")).exists():
                i += 1
            print(today if i == 0 else f"{today}.{i}")
            return
        if not a.version or not version_valid(a.version):
            p.error("invalid canonical CalVer")
        record_path = root / (a.version + ".json")
        if a.action == "candidate":
            if not all((a.source, a.image, a.flake, a.target)):
                p.error("candidate requires --source, --image, --flake, --target")
            if record_path.exists():
                raise RuntimeError("version already reserved; cannot rebind")
            source = Path(a.source).resolve()
            sha = run("git", "-C", str(source), "rev-parse", "HEAD")
            if run("git", "-C", str(source), "status", "--porcelain", "--untracked-files=all"):
                raise RuntimeError("source checkout is dirty; commit or clean before releasing")
            flake_ref = a.flake + a.target
            # Build first; a successful path-info must identify a real store output.
            run("podman", "exec", a.container, "nix", "build", "--no-link", flake_ref, capture=False)
            store_path = run("podman", "exec", a.container, "nix", "path-info", flake_ref)
            if not store_path.startswith("/nix/store/") or "\n" in store_path:
                raise RuntimeError("expected exactly one Nix store output")
            digest = image_id(a.image)
            candidate_tag = f"localhost/nix-alpine/{a.component}:candidate-{a.version}"
            try:
                existing = image_id(candidate_tag)
            except subprocess.CalledProcessError:
                existing = None
            if existing and existing != digest:
                raise RuntimeError("candidate tag already bound to another image")
            if not existing:
                run("podman", "tag", a.image, candidate_tag)
            record = {
                "schema": 1, "component": a.component, "version": a.version,
                "status": "candidate", "source_sha": sha, "source_path": str(source),
                "flake_ref": flake_ref, "nix_output": store_path,
                "image_id": digest, "candidate_tag": candidate_tag,
                "created_utc": dt.datetime.now(dt.timezone.utc).isoformat()
            }
            atomic_json(record_path, record)
            print(record_path)
            return
        if not record_path.exists():
            raise RuntimeError("candidate record not found")
        record = json.loads(record_path.read_text())
        if record["status"] != "candidate":
            raise RuntimeError("only candidates can be qualified")
        if image_id(record["candidate_tag"]) != record["image_id"]:
            raise RuntimeError("candidate tag/image identity drift")
        if run("git", "-C", record["source_path"], "rev-parse", "HEAD") != record["source_sha"]:
            raise RuntimeError("source SHA changed since candidate creation")
        if run("git", "-C", record["source_path"], "status", "--porcelain", "--untracked-files=all"):
            raise RuntimeError("source checkout became dirty")
        if run("podman", "exec", a.container, "nix", "path-info", record["flake_ref"]) != record["nix_output"]:
            raise RuntimeError("Nix output changed since candidate creation")
        evidence_dir = root / "evidence" / a.version
        evidence_dir.mkdir(parents=True, exist_ok=True)
        evidence = []
        for i, gate in enumerate(a.gates):
            if not re.fullmatch(r"#[a-zA-Z][a-zA-Z0-9_-]*", gate):
                raise RuntimeError("gate must be a Nix flake app target, e.g. #qualify")
            command = ["podman", "exec", a.container, "nix", "run", record["flake_ref"].split("#")[0] + gate]
            result = subprocess.run(command, text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
            logfile = evidence_dir / f"{i:02d}-{gate[1:]}.log"
            logfile.write_text(result.stdout)
            evidence.append({"gate": gate, "exit_code": result.returncode,
                             "log_sha256": hashlib.sha256(result.stdout.encode()).hexdigest(),
                             "log_path": str(logfile)})
            if result.returncode != 0:
                atomic_json(evidence_dir / "failed.json", {"gates": evidence, "status": "failed"})
                raise RuntimeError(f"gate {gate} failed ({result.returncode}); no qualification tag created")
        qualified_tag = f"localhost/nix-alpine/{a.component}:qualified-{a.version}"
        try:
            old = image_id(qualified_tag)
        except subprocess.CalledProcessError:
            old = None
        if old and old != record["image_id"]:
            raise RuntimeError("qualified tag already bound to another image")
        if not old:
            run("podman", "tag", record["candidate_tag"], qualified_tag)
        record.update(status="qualified", qualified_tag=qualified_tag, gates=evidence,
                      qualified_utc=dt.datetime.now(dt.timezone.utc).isoformat())
        atomic_json(record_path, record)
        print(record_path)

if __name__ == "__main__":
    try:
        main()
    except (RuntimeError, subprocess.CalledProcessError) as exc:
        print(f"release: {exc}", file=sys.stderr)
        sys.exit(1)
