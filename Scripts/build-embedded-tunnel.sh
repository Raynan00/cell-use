#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
if [[ "$(uname -s)" != Darwin ]]; then
  echo 'Building the embedded iOS tunnel requires macOS and Xcode.' >&2
  exit 1
fi
xcodegen generate --spec Examples/EmbeddedTunnelHost/project.yml
xcodebuild -project Examples/EmbeddedTunnelHost/EmbeddedTunnelHost.xcodeproj \
  -scheme EmbeddedTunnelHost -configuration Debug -destination 'generic/platform=iOS' \
  -derivedDataPath .build/TunnelDerivedData CODE_SIGNING_ALLOWED=NO build
python3 Scripts/verify-embedded-tunnel.py \
  --app .build/TunnelDerivedData/Build/Products/Debug-iphoneos/EmbeddedTunnelHost.app
