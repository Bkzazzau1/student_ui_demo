# Android Rust library (`libbrain_core.so`)

Android loads the Rust core from
`android/app/src/main/jniLibs/arm64-v8a/libbrain_core.so`, which is committed
prebuilt. The Gradle build does not compile Rust.

**Rebuild and commit it whenever `native/brain_core` or the generated
bindings change.** Flutter Rust Bridge compares a content hash at startup. A
library built from older Rust code does not start, and the app fails at launch.

## Build (Windows host)

These commands need:

- the Rust target `aarch64-linux-android` (`rustup target add aarch64-linux-android`);
- the Android NDK from the Android SDK (tested with 28.2.13676358).

```bash
NDK_BIN="$(cygpath -w "$LOCALAPPDATA/Android/Sdk/ndk/28.2.13676358/toolchains/llvm/prebuilt/windows-x86_64/bin")"
export CARGO_TARGET_AARCH64_LINUX_ANDROID_LINKER="$NDK_BIN\aarch64-linux-android21-clang.cmd"
export CC_aarch64_linux_android="$NDK_BIN\aarch64-linux-android21-clang.cmd"
export AR_aarch64_linux_android="$NDK_BIN\llvm-ar.exe"
cargo build --release --target aarch64-linux-android --manifest-path native/brain_core/Cargo.toml
cp native/brain_core/target/aarch64-linux-android/release/libbrain_core.so \
   android/app/src/main/jniLibs/arm64-v8a/libbrain_core.so
```

## Check the content hash

```bash
"$NDK_BIN/llvm-objdump.exe" -d --disassemble-symbols=frb_get_rust_content_hash \
  android/app/src/main/jniLibs/arm64-v8a/libbrain_core.so
grep rustContentHash lib/rust/frb_generated.dart
```

The two `mov`/`movk` immediates in the disassembly form a 32-bit value. It
must equal `rustContentHash` taken as an unsigned 32-bit number. For example,
`-1916176688` is `0x8dc976d0`.

Only `arm64-v8a` is shipped, which covers current Android tablets. An
`x86_64` emulator has no library.
