#!/usr/bin/env python3
"""Check the built host actually embeds an arm64 packet-tunnel extension."""
import argparse
import plistlib
import struct
from pathlib import Path

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--app', type=Path, required=True)
args = parser.parse_args()
host = plistlib.loads((args.app / 'Info.plist').read_bytes())
extensions = list((args.app / 'PlugIns').glob('*.appex'))
assert len(extensions) == 1, 'Expected one embedded tunnel extension'
extension = extensions[0]
info = plistlib.loads((extension / 'Info.plist').read_bytes())
assert info['CFBundleIdentifier'] == host['CFBundleIdentifier'] + '.tunnel'
assert info['NSExtension']['NSExtensionPointIdentifier'] == 'com.apple.networkextension.packet-tunnel'
assert info['NSExtension']['NSExtensionPrincipalClass'] == 'CellUseTunnelExtension.PacketTunnelProvider'
for bundle, metadata in [(args.app, host), (extension, info)]:
    executable = (bundle / metadata['CFBundleExecutable']).read_bytes()
    assert struct.unpack_from('<II', executable) == (0xFEEDFACF, 0x0100000C), 'Expected arm64 Mach-O'
print('Verified arm64 host + embedded packet-tunnel extension, bundle IDs and principal class.')
