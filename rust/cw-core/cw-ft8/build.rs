// Build the vendored ft8_lib C sources and generate Rust bindings.
//
// The C sources live in `swift/packages/CarrierWaveCore/Sources/CFT8/` and are
// the same tree the Swift package compiles via its CFT8 SPM target. We mirror
// that target's build settings: `-DHAVE_STPCPY` (the BSD/Darwin libc has it,
// avoids ft8_lib's fallback) and the CFT8 root on the header search path so
// the cross-directory `#include "../common/common.h"` resolves.
//
// Per-target overrides are out of scope here — `cargo build --target …` for
// the four Apple slices works because `cc` and `bindgen` infer the right
// triple from the cargo env.

use std::path::PathBuf;

fn main() {
    let manifest_dir = PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    let cft8_dir = manifest_dir
        .join("..")
        .join("..")
        .join("..")
        .join("swift")
        .join("packages")
        .join("CarrierWaveCore")
        .join("Sources")
        .join("CFT8");

    let ft8_dir = cft8_dir.join("ft8");
    let common_dir = cft8_dir.join("common");
    let fft_dir = cft8_dir.join("fft");

    // Source files (mirror the SPM target's file list).
    let sources: &[(&str, &str)] = &[
        ("ft8", "constants.c"),
        ("ft8", "crc.c"),
        ("ft8", "decode.c"),
        ("ft8", "encode.c"),
        ("ft8", "ldpc.c"),
        ("ft8", "message.c"),
        ("ft8", "text.c"),
        ("common", "monitor.c"),
        ("fft", "kiss_fft.c"),
        ("fft", "kiss_fftr.c"),
    ];

    let mut build = cc::Build::new();
    build
        .include(&cft8_dir)
        .include(&ft8_dir)
        .include(&common_dir)
        .include(&fft_dir)
        .define("HAVE_STPCPY", None)
        // ft8_lib uses kiss_fft's float type by default; matches Swift build.
        .define("kiss_fft_scalar", "float")
        .warnings(false); // ft8_lib has -Wunused-but-set-variable in places; not our code

    for (subdir, file) in sources {
        let path = cft8_dir.join(subdir).join(file);
        println!("cargo:rerun-if-changed={}", path.display());
        build.file(&path);
    }
    build.compile("cft8");

    // Generate Rust bindings against the same headers the Swift modulemap
    // exports — covers the full ft8_lib surface we touch.
    let headers: [(&str, &str); 9] = [
        ("ft8", "constants.h"),
        ("ft8", "crc.h"),
        ("ft8", "decode.h"),
        ("ft8", "encode.h"),
        ("ft8", "ldpc.h"),
        ("ft8", "message.h"),
        ("ft8", "text.h"),
        ("common", "monitor.h"),
        ("common", "common.h"),
    ];

    let mut builder = bindgen::Builder::default()
        .clang_arg(format!("-I{}", cft8_dir.display()))
        .clang_arg(format!("-I{}", ft8_dir.display()))
        .clang_arg(format!("-I{}", common_dir.display()))
        .clang_arg(format!("-I{}", fft_dir.display()))
        .clang_arg("-DHAVE_STPCPY")
        // Keep the binding surface tight and predictable.
        .allowlist_function("ftx_.*")
        .allowlist_function("ft8_.*")
        .allowlist_function("monitor_.*")
        .allowlist_type("ftx_.*")
        .allowlist_type("ft8_.*")
        .allowlist_type("monitor_.*")
        .allowlist_var("FT8_.*")
        .allowlist_var("FTX_.*")
        .derive_default(true)
        .parse_callbacks(Box::new(bindgen::CargoCallbacks::new()));

    for (subdir, file) in headers {
        let path = cft8_dir.join(subdir).join(file);
        println!("cargo:rerun-if-changed={}", path.display());
        builder = builder.header(path.to_string_lossy().into_owned());
    }

    let bindings = builder.generate().expect("ft8_lib bindgen failed");
    let out_path = PathBuf::from(std::env::var("OUT_DIR").unwrap()).join("ft8_lib.rs");
    bindings
        .write_to_file(&out_path)
        .expect("failed to write ft8_lib.rs");
}
