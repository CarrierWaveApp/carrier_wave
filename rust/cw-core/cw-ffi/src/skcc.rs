//! UniFFI surface for SKCC roster parsing (`cw_domain::skcc`).
//!
//! The download / disk caching stays host-side; the parser, award resolution,
//! and by-callsign index live in Rust so spot enrichment matches everywhere.
//! `badge` and `summary` are precomputed into the record so the UI layer needs
//! no further string formatting.

use std::collections::HashMap;

use cw_domain::skcc::{self, SkccAward, SkccMember};

/// Highest SKCC award level achieved by a member.
#[derive(uniffi::Enum)]
pub enum FfiSkccAward {
    Member,
    Centurion,
    Tribune,
    Senator,
}

impl From<SkccAward> for FfiSkccAward {
    fn from(award: SkccAward) -> Self {
        match award {
            SkccAward::Member => FfiSkccAward::Member,
            SkccAward::Centurion => FfiSkccAward::Centurion,
            SkccAward::Tribune => FfiSkccAward::Tribune,
            SkccAward::Senator => FfiSkccAward::Senator,
        }
    }
}

impl From<FfiSkccAward> for SkccAward {
    fn from(award: FfiSkccAward) -> Self {
        match award {
            FfiSkccAward::Member => SkccAward::Member,
            FfiSkccAward::Centurion => SkccAward::Centurion,
            FfiSkccAward::Tribune => SkccAward::Tribune,
            FfiSkccAward::Senator => SkccAward::Senator,
        }
    }
}

/// A single SKCC roster entry (with precomputed `badge` + `summary`).
#[derive(uniffi::Record)]
pub struct FfiSkccMember {
    pub number: i64,
    pub callsign: String,
    pub name: Option<String>,
    pub spc: Option<String>,
    pub award: FfiSkccAward,
    pub tribune_multiplier: Option<i64>,
    pub other_callsigns: Vec<String>,
    pub badge: String,
    pub summary: String,
}

impl From<SkccMember> for FfiSkccMember {
    fn from(member: SkccMember) -> Self {
        let badge = member.badge();
        let summary = member.summary();
        FfiSkccMember {
            number: member.number,
            callsign: member.callsign,
            name: member.name,
            spc: member.spc,
            award: member.award.into(),
            tribune_multiplier: member.tribune_multiplier,
            other_callsigns: member.other_callsigns,
            badge,
            summary,
        }
    }
}

impl From<FfiSkccMember> for SkccMember {
    fn from(member: FfiSkccMember) -> Self {
        SkccMember {
            number: member.number,
            callsign: member.callsign,
            name: member.name,
            spc: member.spc,
            award: member.award.into(),
            tribune_multiplier: member.tribune_multiplier,
            other_callsigns: member.other_callsigns,
        }
    }
}

/// Parse a roster file body into members (header line skipped).
#[uniffi::export]
pub fn parse_skcc_roster(body: String) -> Vec<FfiSkccMember> {
    skcc::parse_roster(&body).into_iter().map(Into::into).collect()
}

/// Parse a single roster line, or `None` if it cannot be parsed.
#[uniffi::export]
pub fn parse_skcc_member_line(line: String) -> Option<FfiSkccMember> {
    skcc::parse_member_line(&line).map(Into::into)
}

/// Build the by-callsign lookup index (current calls + other calls).
#[uniffi::export]
pub fn build_skcc_index(members: Vec<FfiSkccMember>) -> HashMap<String, FfiSkccMember> {
    let domain: Vec<SkccMember> = members.into_iter().map(Into::into).collect();
    skcc::build_index(&domain).into_iter().map(|(key, value)| (key, value.into())).collect()
}
