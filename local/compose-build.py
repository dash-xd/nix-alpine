#!/usr/bin/env python3
"""Build a locked Fatline composition using Agni's existing Nix topology."""
import argparse
import json
from pathlib import Path
import shutil
import subprocess

p = argparse.ArgumentParser()
p.add_argument("--name", required=True)
p.add_argument("--compositions", required=True)
p.add_argument("--workspaces", required=True)
p.add_argument("--container", required=True)
a = p.parse_args()
root = Path(a.compositions).expanduser().resolve() / a.name
workspace = Path(a.workspaces).expanduser().resolve()
lock = json.loads((root / "composition.lock.json").read_text())
components = lock["components"]
if set(components) != {"redis", "nginx", "logma", "skymill"}:
    p.error("Fatline needs qualified redis, nginx, logma, and skymill releases")
assembly = Path(lock["assembly"]["path"])
revision = subprocess.check_output(["git", "-C", str(assembly), "rev-parse", "HEAD"], text=True).strip()
if revision != lock["assembly"]["git_sha"]:
    p.error("assembly SHA drift")
for file in ("composition.nix", "composition-config.nix"):
    shutil.copyfile(assembly / file, root / file)
images = {}
for name, record in sorted(components.items()):
    alias = "localhost/fatline/" + name + ":" + record["version"]
    actual = subprocess.check_output(["podman", "image", "inspect", record["qualified_tag"], "--format", "{{.Id}}"], text=True).strip()
    if not actual.startswith("sha256:"):
        actual = "sha256:" + actual
    if actual != record["image_id"]:
        p.error("qualified image identity mismatch for " + name)
    subprocess.run(["podman", "tag", record["image_id"], alias], check=True)
    images[name] = alias
(root / "images.json").write_text(json.dumps(images, sort_keys=True, indent=2) + "\n")
upstream = json.loads((assembly / "flake.lock").read_text())
rev = upstream["nodes"]["nixpkgs"]["locked"]["rev"]
flake = '''{
  description = "Locked Fatline composition";
  inputs.nixpkgs.url = "github:NixOS/nixpkgs/%s";
  outputs = { self, nixpkgs }:
    let
      system = "x86_64-linux";
      pkgs = import nixpkgs { inherit system; };
      config = import ./composition-config.nix;
      components = builtins.fromJSON (builtins.readFile ./images.json);
    in {
      packages.${system}.default = import ./composition.nix {
        inherit pkgs config components;
        lib = pkgs.lib;
      };
    };
}
''' % rev
(root / "flake.nix").write_text(flake)
container_dir = "/workspaces/" + root.relative_to(workspace).as_posix()
for args in (["flake", "lock"], ["build", ".#default", "--no-link"]):
    subprocess.run(["podman", "exec", "-w", container_dir, a.container, "nix", *args], check=True)
output = subprocess.check_output(["podman", "exec", "-w", container_dir, a.container,
                                  "nix", "path-info", ".#default"], text=True).strip()
(root / "output.json").write_text(json.dumps({"composition_id": lock["identity"], "nix_output": output}, indent=2) + "\n")
print(output)
