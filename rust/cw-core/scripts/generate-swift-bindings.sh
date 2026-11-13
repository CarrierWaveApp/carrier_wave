#!/usr/bin/env bash
# Generate Swift bindings from the cw-ffi cdylib using library-mode
# uniffi-bindgen. Used by build-xcframework.sh and as a standalone helper
# during development.
#
# Output: target/generated/swift/{cw_ffi.swift,cw_ffiFFI.h,cw_ffiFFI.modulemap}
set -euo pipefail
cd "$(dirname "$0")/.."

cargo build -p cw-ffi --bin uniffi-bindgen
cargo build -p cw-ffi

OUT_DIR="target/generated/swift"
rm -rf "$OUT_DIR"
mkdir -p "$OUT_DIR"

cargo run -p cw-ffi --bin uniffi-bindgen -- generate \
    --library target/debug/libcw_ffi.dylib \
    --language swift \
    --out-dir "$OUT_DIR"

echo "✓ Swift bindings generated in $OUT_DIR"
