#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
if [[ "$(uname -s)" != Darwin ]]; then
  echo "The iOS app build requires macOS and Xcode 27. Use WSL for protocol tests." >&2
  exit 1
fi
for tool in python3 git rustup cargo rg xcodegen xcodebuild; do
  command -v "$tool" >/dev/null || { echo "Missing build tool: $tool" >&2; exit 1; }
done
# Drain all output: grep -q can close the pipe before xcodebuild writes its
# build-number line, which makes xcodebuild crash under pipefail.
xcodebuild -version | grep -E '^Xcode 27(\.|$)' >/dev/null || { echo 'Select Xcode 27 with xcode-select.' >&2; exit 1; }
python3 Scripts/test-bootstrap.py
python3 Scripts/bootstrap.py
export RUSTUP_TOOLCHAIN=1.95.0
rustup toolchain install "$RUSTUP_TOOLCHAIN" --profile minimal
rustup target add --toolchain "$RUSTUP_TOOLCHAIN" aarch64-apple-ios aarch64-apple-ios-sim
bash .build/devicehub/Scripts/build-protocol-xcframework.sh
xcodegen generate --spec project.yml
xcodebuild -resolvePackageDependencies -project CellUseDemo.xcodeproj -scheme CellUseDemo
# This compiles the actual device target without importing any signing credentials.
xcodebuild -project CellUseDemo.xcodeproj -scheme CellUseDemo \
  -skipMacroValidation \
  -configuration Debug -destination 'generic/platform=iOS' \
  -derivedDataPath .build/DerivedData CODE_SIGNING_ALLOWED=NO build
echo 'Unsigned device app: .build/DerivedData/Build/Products/Debug-iphoneos/CellUseDemo.app'
python3 Scripts/package-unsigned.py
echo 'For installation, open CellUseDemo.xcodeproj and select your signing team and connected iPhone.'
# Run integration tests after packaging so a failed host-only diagnostic can be
# investigated on the phone. Failure still fails this script and the CI job.
swift test
swift test --package-path Runtime
