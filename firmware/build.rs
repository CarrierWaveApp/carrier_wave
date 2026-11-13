//! Firmware build script.
//!
//! 1. Wires up the ESP-IDF environment (embuild).
//! 2. Compiles the shared CFT8 C library (the same sources used by CarrierWaveCore
//!    on iOS/macOS) into `libcft8.a` for linking into the firmware. Keeping a
//!    single C implementation avoids protocol drift between firmware and app.

use std::path::PathBuf;

fn main() {
    embuild::espidf::sysenv::output();
    build_cft8();
}

/// Find `xtensa-esp32s3-elf-gcc` (or `xtensa-esp-elf-gcc`) on PATH.
fn which_xtensa_gcc() -> Result<PathBuf, ()> {
    for name in ["xtensa-esp32s3-elf-gcc", "xtensa-esp-elf-gcc"] {
        if let Ok(path) = std::process::Command::new("which").arg(name).output() {
            if path.status.success() {
                let p = String::from_utf8_lossy(&path.stdout).trim().to_string();
                if !p.is_empty() {
                    return Ok(PathBuf::from(p));
                }
            }
        }
    }
    Err(())
}

fn build_cft8() {
    let cft8_root: PathBuf = [
        "..",
        "swift",
        "packages",
        "CarrierWaveCore",
        "Sources",
        "CFT8",
    ]
    .iter()
    .collect();

    let sources = [
        cft8_root.join("ft8/constants.c"),
        cft8_root.join("ft8/crc.c"),
        cft8_root.join("ft8/decode.c"),
        cft8_root.join("ft8/encode.c"),
        cft8_root.join("ft8/ldpc.c"),
        cft8_root.join("ft8/message.c"),
        cft8_root.join("ft8/text.c"),
        cft8_root.join("common/monitor.c"),
        cft8_root.join("fft/kiss_fft.c"),
        cft8_root.join("fft/kiss_fftr.c"),
        PathBuf::from("src/ft8_shim.c"),
    ];

    for src in &sources {
        println!("cargo:rerun-if-changed={}", src.display());
    }

    let mut build = cc::Build::new();

    // For Xtensa cross-compilation, `cc` won't auto-detect the right compiler.
    // Use the compiler path from the ESP-IDF toolchain if set by embuild, or
    // fall back to discovering it on PATH.
    if let Ok(compiler) = std::env::var("CC_xtensa_esp32s3_espidf")
        .or_else(|_| std::env::var("CC_xtensa-esp32s3-espidf"))
    {
        build.compiler(compiler);
    } else if let Ok(path) = which_xtensa_gcc() {
        build.compiler(path);
    }

    build
        .include(cft8_root.join("ft8"))
        .include(cft8_root.join("common"))
        .include(cft8_root.join("fft"))
        .files(sources.iter())
        .flag_if_supported("-std=c11")
        .flag_if_supported("-ffunction-sections")
        .flag_if_supported("-fdata-sections")
        .flag_if_supported("-Wno-unused-parameter")
        .flag_if_supported("-Wno-sign-compare")
        .flag_if_supported("-mlongcalls")
        .warnings(false);

    // Reduce flash footprint: kiss_fft uses `-Os` well; encode/decode benefit from
    // `-O2`. We leave optimisation to the profile-level settings Cargo passes
    // through to avoid mismatching -Os/-O2 between the two halves of the firmware.
    build.compile("cft8");
}
