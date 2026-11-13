// Library-mode uniffi-bindgen launcher.
//
// Invoked as `cargo run --bin uniffi-bindgen -- generate ...` to produce
// Swift/Kotlin bindings from the crate-local `[[bin]]` target, without
// requiring a globally installed CLI.
fn main() {
    uniffi::uniffi_bindgen_main()
}
