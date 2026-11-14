#!/usr/bin/env bash
# Builds the K-SLAS Rust core (native/brain_core) for iOS and packages it as
# ios/BrainCore/brain_core.xcframework, which the BrainCore pod vendors and
# Flutter Rust Bridge opens at run time as "brain_core.framework/brain_core".
#
# Needs macOS with Xcode and rustup. Builds the device slice (arm64) and a
# universal simulator slice (arm64 + x86_64). Set BRAIN_CORE_DEVICE_ONLY=1 to
# skip the simulator (release builds for TestFlight only need the device).
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
CRATE="$ROOT/native/brain_core"
OUT="$ROOT/ios/BrainCore/brain_core.xcframework"
MIN_IOS="${BRAIN_CORE_MIN_IOS:-15.1}"
export IPHONEOS_DEPLOYMENT_TARGET="$MIN_IOS"

DEVICE_TARGET=aarch64-apple-ios
# The simulator slice is universal (Apple silicon and Intel): Xcode builds
# both architectures when it targets a generic simulator.
SIM_TARGETS=(aarch64-apple-ios-sim x86_64-apple-ios)
if [[ "${BRAIN_CORE_DEVICE_ONLY:-0}" == "1" ]]; then
  SIM_TARGETS=()
fi

# ${arr[@]+...} keeps an empty array safe under `set -u` in macOS bash 3.2.
rustup target add "$DEVICE_TARGET" ${SIM_TARGETS[@]+"${SIM_TARGETS[@]}"}

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
FRAMEWORK_ARGS=()

build_dylib() {
  local target="$1"
  echo "Building brain_core for $target (iOS $MIN_IOS)" >&2
  cargo build --release --lib --manifest-path "$CRATE/Cargo.toml" --target "$target" >&2
  echo "$CRATE/target/$target/release/libbrain_core.dylib"
}

# make_framework <platform> <slice name> <dylib>...
make_framework() {
  local platform="$1"
  local slice="$2"
  shift 2
  local framework="$WORK/$slice/brain_core.framework"
  mkdir -p "$framework"
  if [[ $# -gt 1 ]]; then
    lipo -create "$@" -output "$framework/brain_core"
  else
    cp "$1" "$framework/brain_core"
  fi
  install_name_tool -id "@rpath/brain_core.framework/brain_core" "$framework/brain_core"
  # install_name_tool invalidates the linker's ad-hoc signature; Xcode signs
  # the framework again with the app's identity when it embeds it.
  codesign --force --sign - "$framework/brain_core"
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
  lipo -info "$framework/brain_core"
  FRAMEWORK_ARGS+=(-framework "$framework")
}

make_framework iPhoneOS device "$(build_dylib "$DEVICE_TARGET")"
if [[ ${#SIM_TARGETS[@]} -gt 0 ]]; then
  SIM_DYLIBS=()
  for target in "${SIM_TARGETS[@]}"; do
    SIM_DYLIBS+=("$(build_dylib "$target")")
  done
  make_framework iPhoneSimulator simulator "${SIM_DYLIBS[@]}"
fi

rm -rf "$OUT"
mkdir -p "$(dirname "$OUT")"
xcodebuild -create-xcframework "${FRAMEWORK_ARGS[@]}" -output "$OUT"
echo "Created $OUT"
