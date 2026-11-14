#!/usr/bin/env bash
# Builds the K-SLAS Rust core (native/brain_core) for iOS and packages it as
# ios/BrainCore/brain_core.xcframework, which the BrainCore pod vendors and
# Flutter Rust Bridge opens at run time as "brain_core.framework/brain_core".
#
# Needs macOS with Xcode and rustup. Builds the device slice (arm64) and the
# Apple-silicon simulator slice. Set BRAIN_CORE_DEVICE_ONLY=1 to skip the
# simulator (release builds for TestFlight only need the device slice).
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
CRATE="$ROOT/native/brain_core"
OUT="$ROOT/ios/BrainCore/brain_core.xcframework"
MIN_IOS="${BRAIN_CORE_MIN_IOS:-15.1}"
export IPHONEOS_DEPLOYMENT_TARGET="$MIN_IOS"

TARGETS=(aarch64-apple-ios aarch64-apple-ios-sim)
if [[ "${BRAIN_CORE_DEVICE_ONLY:-0}" == "1" ]]; then
  TARGETS=(aarch64-apple-ios)
fi

rustup target add "${TARGETS[@]}"

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
FRAMEWORK_ARGS=()

for target in "${TARGETS[@]}"; do
  echo "Building brain_core for $target (iOS $MIN_IOS)"
  cargo build --release --lib --manifest-path "$CRATE/Cargo.toml" --target "$target"

  platform="iPhoneOS"
  if [[ "$target" == *-sim ]]; then
    platform="iPhoneSimulator"
  fi

  framework="$WORK/$target/brain_core.framework"
  mkdir -p "$framework"
  cp "$CRATE/target/$target/release/libbrain_core.dylib" "$framework/brain_core"
  install_name_tool -id "@rpath/brain_core.framework/brain_core" "$framework/brain_core"
  cat > "$framework/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key>
  <string>en</string>
  <key>CFBundleExecutable</key>
  <string>brain_core</string>
  <key>CFBundleIdentifier</key>
  <string>org.kslas.brain-core</string>
  <key>CFBundleInfoDictionaryVersion</key>
  <string>6.0</string>
  <key>CFBundleName</key>
  <string>brain_core</string>
  <key>CFBundlePackageType</key>
  <string>FMWK</string>
  <key>CFBundleShortVersionString</key>
  <string>0.1.0</string>
  <key>CFBundleVersion</key>
  <string>1</string>
  <key>CFBundleSupportedPlatforms</key>
  <array>
    <string>$platform</string>
  </array>
  <key>MinimumOSVersion</key>
  <string>$MIN_IOS</string>
</dict>
</plist>
PLIST
  FRAMEWORK_ARGS+=(-framework "$framework")
done

rm -rf "$OUT"
mkdir -p "$(dirname "$OUT")"
xcodebuild -create-xcframework "${FRAMEWORK_ARGS[@]}" -output "$OUT"
echo "Created $OUT"
