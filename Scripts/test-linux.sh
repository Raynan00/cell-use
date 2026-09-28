#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
ROOT="$PWD"
if [[ -f "$HOME/.cargo/env" ]]; then source "$HOME/.cargo/env"; fi
if [[ -f "$HOME/.local/share/swiftly/env.sh" ]]; then source "$HOME/.local/share/swiftly/env.sh"; fi
mkdir -p .build/validation
swift test --scratch-path "$HOME/.cache/cell-use-sdk-build" 2>&1 | tee .build/validation/swift-tests.log
swift test --package-path Runtime --scratch-path "$HOME/.cache/cell-use-native-core-build" 2>&1 | tee .build/validation/runtime-tests.log
swiftc -frontend -parse Examples/CellUseDemo/*.swift

# NTFS mounts may not preserve POSIX mode bits. Upstream's integrity check
# includes those bits, so materialize its dependency on the Linux filesystem.
CACHE="$HOME/.cache/phone-probe-native"
mkdir -p "$CACHE/Scripts" "$CACHE/Patches"
cp Scripts/bootstrap.py "$CACHE/Scripts/bootstrap.py"
cp dependencies.json "$CACHE/dependencies.json"
cp Patches/*.patch "$CACHE/Patches/"
python3 "$CACHE/Scripts/bootstrap.py"
cargo test --manifest-path "$CACHE/.build/devicehub/Rust/Cargo.toml" \
  --package device-hub-ffi --locked 2>&1 | tee "$ROOT/.build/validation/rust-tests.log"
printf '\nSwift core and native transport tests passed. iOS app linking and device execution require macOS/iPhone validation.\n'
