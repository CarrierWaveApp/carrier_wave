//! Raw FFI bindings for vendored `ft8_lib`, generated at build time by
//! `build.rs` (`bindgen` over the same headers `Sources/CFT8/include/module.modulemap`
//! exports to Swift). Kept in its own module so consumers of safe wrappers
//! (`decoder.rs`, `encoder.rs`) never see raw C types.
#![allow(
    non_upper_case_globals,
    non_camel_case_types,
    non_snake_case,
    dead_code,
    clippy::missing_safety_doc,
    clippy::too_many_arguments,
    clippy::useless_transmute,
    clippy::unnecessary_mut_passed
)]

include!(concat!(env!("OUT_DIR"), "/ft8_lib.rs"));
