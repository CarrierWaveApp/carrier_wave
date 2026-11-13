.PHONY: macro-codegen macro-codegen-check

# Regenerate the Swift + Rust verifier glue from macro-step-schema.json.
# Run this after editing the schema; commit the resulting changes.
macro-codegen:
	cd Tools/macro-codegen && cargo run --release -- \
	    --schema ../../swift/packages/CarrierWaveData/Sources/CarrierWaveData/Resources/macro-step-schema.json \
	    --swift-out ../../swift/packages/CarrierWaveData/Sources/CarrierWaveData/Macros/Generated/MacroVerifier+Generated.swift \
	    --rust-out ../../server/src/macros/verifier_generated.rs

# Verify the committed generated files match what the codegen produces.
# Fails the build if anyone edits the schema without regenerating, or hand-edits the generated files.
macro-codegen-check:
	cd Tools/macro-codegen && cargo run --release -- \
	    --schema ../../swift/packages/CarrierWaveData/Sources/CarrierWaveData/Resources/macro-step-schema.json \
	    --swift-out ../../swift/packages/CarrierWaveData/Sources/CarrierWaveData/Macros/Generated/MacroVerifier+Generated.swift \
	    --rust-out ../../server/src/macros/verifier_generated.rs \
	    --check
