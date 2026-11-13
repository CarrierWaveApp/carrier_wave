use serde::Deserialize;

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct StepSchema {
    pub format: u32,
    pub step_kinds: Vec<StepKind>,
    pub capability_keys: Vec<String>,
    #[serde(default)]
    pub capability_sentinels: Vec<String>,
    pub opcode_tables: Vec<String>,
    #[serde(default)]
    pub reserved_word_policy: Option<String>,
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct StepKind {
    pub name: String,
    pub params: Vec<Param>,
    /// Heterogeneous per-step capability bag. Interpreted by emit logic (swift_emit, rust_emit),
    /// not by the schema layer — keeping it as serde_json::Value lets new sentinel/encoding
    /// shapes land without churning this struct.
    pub capabilities: serde_json::Value,
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct Param {
    pub name: String,
    #[serde(rename = "type")]
    pub ty: String,
    pub min: Option<i64>,
    pub max: Option<i64>,
    pub required: bool,
    #[serde(default)]
    pub ascii: bool,
    #[serde(default)]
    pub values: Vec<String>,
}

impl StepSchema {
    pub fn load(path: &std::path::Path) -> anyhow::Result<Self> {
        let bytes = std::fs::read(path)?;
        Ok(serde_json::from_slice(&bytes)?)
    }
}
