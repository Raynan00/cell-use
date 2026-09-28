#!/usr/bin/env python3
"""Configure an unsigned IPA for its observed post-Sideloadly bundle ID.

Only BGTaskSchedulerPermittedIdentifiers changes; the executable and bundle ID
are preserved. Keep account-specific bundle IDs out of Git and command output.
"""
import argparse
import hashlib
import json
from pathlib import Path
import plistlib
import re
import zipfile

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("--input", type=Path, required=True)
parser.add_argument("--output", type=Path, required=True)
parser.add_argument("--bundle-id-file", type=Path, required=True)
args = parser.parse_args()
assert args.input.resolve() != args.output.resolve(), "Preserve the CI artifact"
assert not args.output.exists(), "Refusing to overwrite an existing artifact"
bundle = args.bundle_id_file.read_text().strip()
assert re.fullmatch(r"[A-Za-z0-9-]+(?:\.[A-Za-z0-9-]+)+", bundle), "Invalid bundle ID"
with zipfile.ZipFile(args.input) as source:
    assert source.testzip() is None
    assert not any("_CodeSignature/" in name or name.endswith("embedded.mobileprovision") for name in source.namelist()), "Use the unsigned CI artifact"
    entries = [name for name in source.namelist()
               if re.fullmatch(r"Payload/[^/]+\.app/Info\.plist", name)]
    assert len(entries) == 1, "Expected exactly one host app in the IPA"
    entry = entries[0]
    info = plistlib.loads(source.read(entry))
    original_bundle = info.get("CFBundleIdentifier", "")
    assert original_bundle, "Missing original bundle identifier"
    allowed = info.get("BGTaskSchedulerPermittedIdentifiers", [])
    assert isinstance(allowed, list) and allowed, "Missing background task identifiers"
    assert all(isinstance(value, str) and value.startswith(original_bundle + ".")
               for value in allowed), "Background task identifiers must use the original bundle prefix"
    expected = [bundle + value[len(original_bundle):] for value in allowed]
    info["BGTaskSchedulerPermittedIdentifiers"] = expected
    args.output.parent.mkdir(parents=True, exist_ok=True)
    with zipfile.ZipFile(args.output, "w") as target:
        for item in source.infolist():
            target.writestr(item, plistlib.dumps(info, fmt=plistlib.FMT_BINARY) if item.filename == entry else source.read(item.filename))
with zipfile.ZipFile(args.input) as source, zipfile.ZipFile(args.output) as target:
    assert target.testzip() is None
    changed = [name for name in source.namelist() if source.read(name) != target.read(name)]
    assert changed == [entry], "Unexpected artifact changes"
    configured = plistlib.loads(target.read(entry))
    assert configured["BGTaskSchedulerPermittedIdentifiers"] == expected
print(json.dumps({"file": str(args.output.resolve()), "changedEntries": changed,
                  "sha256": hashlib.sha256(args.output.read_bytes()).hexdigest(),
                  "configuredForObservedInstalledBundle": True}, indent=2))
