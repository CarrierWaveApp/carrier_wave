#!/usr/bin/env bash
#
# Build the cw-ffi Rust core for Android and (re)generate the UniFFI Kotlin
# bindings. Invoked automatically by Gradle (see app/build.gradle.kts), or run
# standalone. Produces, into the app module:
#   - app/src/main/jniLibs/<abi>/libcw_ffi.so   (one per ABI)
#   - app/src/main/java/uniffi/cw_ffi/cw_ffi.kt  (generated bindings)
# Both are gitignored — they are build output, not source.
#
# Env overrides:
#   ANDROID_HOME   Android SDK root (else read from android/local.properties,
#                  else the Homebrew default).
#   ABIS           Space-separated ABIs to build (default: "arm64-v8a").
#   ANDROID_API    Min API level for the native build (default: 24).
set -euo pipefail

ANDROID_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RUST_DIR="$(cd "$ANDROID_DIR/../rust/cw-core" && pwd)"
APP="$ANDROID_DIR/app"
JNILIBS="$APP/src/main/jniLibs"
GEN="$APP/src/main/java"

export PATH="$HOME/.cargo/bin:$PATH"

# --- Resolve the SDK + NDK -------------------------------------------------
if [[ -z "${ANDROID_HOME:-}" ]]; then
    if [[ -f "$ANDROID_DIR/local.properties" ]]; then
        ANDROID_HOME="$(grep -E '^sdk\.dir=' "$ANDROID_DIR/local.properties" | head -1 | cut -d= -f2-)"
    fi
fi
ANDROID_HOME="${ANDROID_HOME:-$(brew --prefix 2>/dev/null)/share/android-commandlinetools}"
[[ -d "$ANDROID_HOME" ]] || { echo "ERROR: Android SDK not found (set ANDROID_HOME)"; exit 1; }

# Pick the highest installed NDK.
NDK_DIR="$(ls -d "$ANDROID_HOME"/ndk/* 2>/dev/null | sort -V | tail -1 || true)"
[[ -n "$NDK_DIR" && -d "$NDK_DIR" ]] || { echo "ERROR: no NDK under $ANDROID_HOME/ndk"; exit 1; }
export ANDROID_NDK_HOME="$NDK_DIR"

# NDK prebuilt host toolchain dir (named darwin-x86_64 even on Apple Silicon).
NDK_LLVM="$(ls -d "$NDK_DIR"/toolchains/llvm/prebuilt/* 2>/dev/null | head -1)"
[[ -n "$NDK_LLVM" ]] || { echo "ERROR: NDK prebuilt toolchain not found"; exit 1; }

ANDROID_API="${ANDROID_API:-24}"
ABIS="${ABIS:-arm64-v8a}"

# openssl-sys / SQLCipher compile C from source; point them at the NDK clang.
# (cargo-ndk doesn't reliably forward CC/AR into the openssl-sys build script.)
export CC_aarch64_linux_android="$NDK_LLVM/bin/aarch64-linux-android${ANDROID_API}-clang"
export AR_aarch64_linux_android="$NDK_LLVM/bin/llvm-ar"
export CARGO_TARGET_AARCH64_LINUX_ANDROID_LINKER="$NDK_LLVM/bin/aarch64-linux-android${ANDROID_API}-clang"
export CC_x86_64_linux_android="$NDK_LLVM/bin/x86_64-linux-android${ANDROID_API}-clang"
export AR_x86_64_linux_android="$NDK_LLVM/bin/llvm-ar"
export CARGO_TARGET_X86_64_LINUX_ANDROID_LINKER="$NDK_LLVM/bin/x86_64-linux-android${ANDROID_API}-clang"

cd "$RUST_DIR"

# --- 1. Cross-compile the .so per ABI --------------------------------------
NDK_ARGS=()
for abi in $ABIS; do NDK_ARGS+=("-t" "$abi"); done
echo "[build-rust] cross-compiling cw-ffi for: $ABIS (API $ANDROID_API, NDK $(basename "$NDK_DIR"))"
cargo ndk "${NDK_ARGS[@]}" -P "$ANDROID_API" -o "$JNILIBS" build --release -p cw-ffi

# --- 2. Generate Kotlin bindings from a host build -------------------------
# Metadata is architecture-independent, so a host build drives uniffi-bindgen.
case "$(uname -s)" in
    Darwin) HOST_LIB="target/debug/libcw_ffi.dylib" ;;
    *)      HOST_LIB="target/debug/libcw_ffi.so" ;;
esac
echo "[build-rust] building host lib for bindgen"
cargo build -p cw-ffi
echo "[build-rust] generating Kotlin bindings -> $GEN/uniffi/cw_ffi/"
cargo run -q -p cw-ffi --bin uniffi-bindgen -- generate \
    --library "$HOST_LIB" --language kotlin --out-dir "$GEN" --no-format

echo "[build-rust] done."
