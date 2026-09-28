#!/usr/bin/env python3
"""Validate a generic unsigned release IPA and write checksums/build metadata."""
import argparse
import hashlib
import json
from pathlib import Path
import plistlib
import struct
import subprocess
import zipfile

root = Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--artifact', type=Path, required=True)
parser.add_argument('--output', type=Path, required=True)
parser.add_argument('--version', default='0.1.0-alpha.1')
parser.add_argument('--ci-run', required=True, help='URL of the successful build workflow')
args = parser.parse_args()
prefix = 'Payload/CellUseDemo.app/'
with zipfile.ZipFile(args.artifact) as archive:
    if archive.testzip() is not None:
        raise SystemExit('Archive integrity check failed')
    names = archive.namelist()
    if any('_CodeSignature/' in n or n.endswith('embedded.mobileprovision') for n in names):
        raise SystemExit('Release requires the generic unsigned archive')
    info = plistlib.loads(archive.read(prefix + 'Info.plist'))
    assert info['CFBundleIdentifier'] == 'com.raynan.celluse'
    assert info['CFBundleDisplayName'] == 'cell-use'
    assert info['BGTaskSchedulerPermittedIdentifiers'] == ['com.raynan.celluse.probe.*']
    executable = archive.read(prefix + info['CFBundleExecutable'])
    assert struct.unpack_from('<II', executable) == (0xFEEDFACF, 0x0100000C), 'Expected arm64 Mach-O'
    for name in ['LICENSE', 'NOTICE', 'THIRD_PARTY_NOTICES.md', 'DeviceHub-MIT.txt']:
        assert archive.read(prefix + name), f'Missing attribution: {name}'
    assert any(n.startswith(prefix + 'Licenses/') for n in names), 'Missing transitive licenses'

args.output.mkdir(parents=True, exist_ok=True)
digest = hashlib.sha256(args.artifact.read_bytes()).hexdigest()
revision = subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=root, text=True).strip()
dependency = json.loads((root / 'dependencies.json').read_text())['deviceHub']
metadata = {
    'package': 'cell-use', 'version': args.version, 'sourceRevision': revision,
    'ciRun': args.ci_run, 'artifact': args.artifact.name, 'sha256': digest,
    'appBuild': info['CFBundleVersion'], 'appVersion': info['CFBundleShortVersionString'],
    'minimumOSVersion': info['MinimumOSVersion'], 'architecture': 'arm64',
    'signing': 'unsigned', 'agentAPIVersion': 1,
    'deviceHubRevision': dependency['revision'],
    'nativePatchSHA256': dependency['probePatch']['sha256'],
}
(args.output / 'build-info.json').write_text(json.dumps(metadata, indent=2) + '\n', encoding='utf-8')
metadata_digest = hashlib.sha256((args.output / 'build-info.json').read_bytes()).hexdigest()
(args.output / 'SHA256SUMS').write_text(
    f'{digest}  {args.artifact.name}\n{metadata_digest}  build-info.json\n', encoding='utf-8')
print(json.dumps(metadata, indent=2))
