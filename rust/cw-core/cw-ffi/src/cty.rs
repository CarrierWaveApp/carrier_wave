//! UniFFI surface for the CTY.dat DXCC database (`cw_domain::cty`).
//!
//! Exposed as an Object (modeled on `scp.rs`) so the parsed CTY.dat lives once
//! in Rust and both the Apple apps and `android/` query it identically. The
//! longest-prefix / portable-indicator lookup logic stays in the core; this is
//! a thin pass-through plus value-DTO mapping.

use std::collections::HashMap;

use cw_domain::cty::{self, CtyDatabase as CoreCtyDatabase, DxccEntity as CoreDxccEntity};

/// A DXCC entity from CTY.dat with zone and location metadata.
#[derive(uniffi::Record)]
pub struct FfiDxccEntity {
    pub name: String,
    pub cq_zone: i32,
    pub itu_zone: i32,
    pub continent: String,
    pub latitude: f64,
    pub longitude: f64,
    pub time_offset: f64,
    pub primary_prefix: String,
}

impl From<&CoreDxccEntity> for FfiDxccEntity {
    fn from(entity: &CoreDxccEntity) -> Self {
        FfiDxccEntity {
            name: entity.name.clone(),
            cq_zone: entity.cq_zone,
            itu_zone: entity.itu_zone,
            continent: entity.continent.clone(),
            latitude: entity.latitude,
            longitude: entity.longitude,
            time_offset: entity.time_offset,
            primary_prefix: entity.primary_prefix.clone(),
        }
    }
}

/// In-memory CTY.dat DXCC lookup database, shared by Swift + Kotlin.
#[derive(uniffi::Object)]
pub struct CtyDatabase {
    inner: CoreCtyDatabase,
}

#[uniffi::export]
impl CtyDatabase {
    /// Parse CTY.dat content into a database.
    #[uniffi::constructor]
    pub fn parse(content: String) -> Self {
        Self { inner: cty::parse(&content) }
    }

    /// Look up the DXCC entity for a callsign using longest-prefix matching,
    /// handling portable indicators (e.g. `W1ABC/VP9` → VP9).
    pub fn lookup(&self, callsign: String) -> Option<FfiDxccEntity> {
        self.inner.lookup(&callsign).map(FfiDxccEntity::from)
    }

    /// All parsed entities, in source order.
    pub fn entities(&self) -> Vec<FfiDxccEntity> {
        self.inner.entities.iter().map(FfiDxccEntity::from).collect()
    }

    /// The full prefix → entity map (every alias prefix, uppercased keys).
    pub fn prefix_map(&self) -> HashMap<String, FfiDxccEntity> {
        self.inner
            .prefix_map
            .iter()
            .map(|(prefix, entity)| (prefix.clone(), FfiDxccEntity::from(entity)))
            .collect()
    }
}
