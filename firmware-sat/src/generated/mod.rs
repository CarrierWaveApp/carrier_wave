// Prost keeps the proto's SCREAMING_SNAKE variant prefixes (STATUS_*,
// SAT_ACK_*, ...) — silence clippy's shared-prefix lint for the whole
// generated module so regeneration stays a plain file copy.
#[allow(clippy::enum_variant_names)]
pub mod cwbp;
