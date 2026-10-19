#!/usr/bin/env python3
"""Read-only Podman image/layer association report."""
import json
import subprocess
import sys

def podman(*args):
    p = subprocess.run(["podman", *args], text=True, capture_output=True)
    if p.returncode:
        raise RuntimeError(f"podman {' '.join(args)}: {p.stderr.strip()}")
    return p.stdout

def inspect_image(image_id):
    return json.loads(podman("image", "inspect", image_id))[0]

def layers(record):
    return (record.get("RootFS") or {}).get("Layers") or []

def short(value):
    return value.removeprefix("sha256:")[:12]

def main():
    container, tag = sys.argv[1:3]
    all_images = json.loads(podman("images", "--all", "--format", "json"))
    containers = json.loads(podman("ps", "--all", "--format", "json"))
    records = {}
    for item in all_images:
        image_id = item.get("Id") or item.get("ID")
        if image_id and image_id not in records:
            records[image_id] = inspect_image(image_id)
    tagged = inspect_image(tag)
    target_id = tagged["Id"]
    target_layers = layers(tagged)
    print(f"Target tag: {tag}")
    print(f"Tagged image: {short(target_id)}  layers={len(target_layers)}")
    print(f"Container: {container}")
    try:
        active = json.loads(podman("container", "inspect", container))[0]
        active_id = active.get("Image", "")
        print(f"  status={active.get('State', {}).get('Status', '?')}  image={short(active_id)}  matches-tag={active_id == target_id}")
    except RuntimeError:
        print("  not found")
    print()
    print("Layer association with tagged image")
    print("  PREFIX = image's ordered layers match the beginning of target layers")
    print("  SHARED = number of matching layer digests (not proof of ancestry)")
    print("  USED BY = containers referencing the exact image ID")
    print("  Size is virtual and can include shared storage; rows are not additive.")
    print()
    print(f"{'IMAGE':12} {'PREFIX':>7} {'SHARED':>7} {'LAYERS':>7}  {'USED BY / TAGS'}")
    for image_id, record in sorted(records.items(), key=lambda pair: pair[1].get("Created", ""), reverse=True):
        own = layers(record)
        prefix = len(own) <= len(target_layers) and own == target_layers[:len(own)]
        shared = len(set(own) & set(target_layers))
        users = []
        for c in containers:
            cid = c.get("Id") or c.get("ID") or ""
            # ps output image IDs vary by Podman version; inspect each container for accuracy.
            if not cid:
                continue
            detail = json.loads(podman("container", "inspect", cid))[0]
            if detail.get("Image") == image_id:
                users.append(detail.get("Name", cid[:12]).lstrip("/"))
        tags = record.get("RepoTags") or []
        if image_id == target_id or shared or users:
            labels = []
            if image_id == target_id:
                labels.append("TARGET")
            labels.extend(users)
            labels.extend(t for t in tags if t not in ("<none>:<none>",))
            print(f"{short(image_id):12} {str(prefix):>7} {shared:>7} {len(own):>7}  {', '.join(labels) or '(untagged / unreferenced)'}")
    print()
    print("Dockerfile layer history for tagged image:")
    print(podman("history", "--no-trunc", tag))
    print("No images were removed.")

if __name__ == "__main__":
    try:
        main()
    except (RuntimeError, ValueError, KeyError, IndexError) as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        sys.exit(1)
