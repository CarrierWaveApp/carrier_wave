use std::path::PathBuf;

fn workspace_root() -> PathBuf {
    PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("../..")
}

#[test]
fn swift_emit_matches_golden() {
    let schema_path = workspace_root().join("swift/packages/CarrierWaveData/Sources/CarrierWaveData/Resources/macro-step-schema.json");
    let schema = macro_codegen::schema::StepSchema::load(&schema_path).expect("schema loads");
    let out = macro_codegen::swift_emit::emit(&schema).expect("swift emit");
    let golden_path = PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("tests/golden_swift.txt");
    let golden = std::fs::read_to_string(&golden_path).expect("golden present");
    assert_eq!(out, golden, "swift emit drifted from golden");
}

#[test]
fn rust_emit_matches_golden() {
    let schema_path = workspace_root().join("swift/packages/CarrierWaveData/Sources/CarrierWaveData/Resources/macro-step-schema.json");
    let schema = macro_codegen::schema::StepSchema::load(&schema_path).expect("schema loads");
    let out = macro_codegen::rust_emit::emit(&schema).expect("rust emit");
    let golden_path = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("tests/golden_rust.txt");
    let golden = std::fs::read_to_string(&golden_path).expect("golden present");
    assert_eq!(out, golden, "rust emit drifted from golden");
}
