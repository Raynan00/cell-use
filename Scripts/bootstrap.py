#!/usr/bin/env python3
"""Fetch an immutable dependency. Never reset or overwrite an existing checkout."""
import json
import hashlib
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def run(*args, cwd=ROOT):
    return subprocess.run(args, cwd=cwd, check=True, text=True, capture_output=True).stdout.strip()


def prepare_probe_patch(destination, dependency):
    patch = dependency.get("probePatch")
    changed = set(run("git", "diff", "HEAD", "--name-only", cwd=destination).splitlines())
    if not patch:
        if changed:
            raise RuntimeError("Dependency contains edits. No automatic overwrite.")
        return
    patch_path = ROOT / patch["path"]
    if hashlib.sha256(patch_path.read_bytes()).hexdigest() != patch["sha256"]:
        raise RuntimeError("Probe patch checksum differs. No automatic overwrite.")
    expected = set(patch["files"])
    def matches(which):
        return all(hashlib.sha256((destination / name).read_bytes()).hexdigest() == hashes[which]
                   for name, hashes in patch["files"].items())
    if changed:
        if changed != expected or not matches("after"):
            raise RuntimeError("Dependency has edits outside the exact pinned probe patch.")
        return
    if not matches("before"):
        raise RuntimeError("Probe patch source hashes differ.")
    run("git", "apply", "--check", str(patch_path), cwd=destination)
    run("git", "apply", str(patch_path), cwd=destination)
    if not matches("after"):
        raise RuntimeError("Probe patch result hashes differ.")


def main():
    dependency = json.loads((ROOT / "dependencies.json").read_text())["deviceHub"]
    destination = ROOT / ".build" / "devicehub"
    destination.parent.mkdir(exist_ok=True)
    if not destination.exists():
        run("git", "clone", "--no-checkout", "--filter=blob:none", dependency["repository"], str(destination))
        run("git", "checkout", "--detach", dependency["revision"], cwd=destination)
    if run("git", "rev-parse", "HEAD", cwd=destination) != dependency["revision"]:
        raise RuntimeError("Dependency revision differs. Preserve your checkout and investigate; no automatic reset.")
    prepare_probe_patch(destination, dependency)
    # Upstream verifies both the patch checksum and the resulting source tree.
    # Run on macOS/Linux: that tree digest includes POSIX executable bits.
    if sys.platform == "win32":
        print("Source fetched. Run this script in WSL or macOS to prepare the patched Rust dependency.")
        return
    subprocess.run([sys.executable, str(destination / "BuildSupport/bootstrap_idevice.py")], check=True)
    print("Pinned native transport prepared.")


if __name__ == "__main__":
    try:
        main()
    except (RuntimeError, subprocess.CalledProcessError) as error:
        print(f"Bootstrap failed: {error}", file=sys.stderr)
        sys.exit(1)
