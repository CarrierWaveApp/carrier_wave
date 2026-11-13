//! Sync transport abstraction — the CloudKit→server swap point.
//!
//! In the Apple-only app this was `CKModifyRecordsOperation` against a private
//! CloudKit zone. The cross-platform core defines transport as a trait so the
//! production implementation is HTTPS-to-the-Rust-server (carrying an OAuth
//! access token), and tests use [`InMemoryTransport`]. The journal/conflict
//! logic above is identical regardless of which transport is plugged in.

use crate::error::SyncError;
use crate::journal::JournalPayload;

pub trait SyncTransport {
    /// Push locally-produced journal payloads to the backend.
    fn push(&mut self, payloads: &[JournalPayload]) -> Result<(), SyncError>;

    /// Pull payloads with `sequence_number > since_sequence`, oldest first.
    fn pull(&mut self, since_sequence: i64) -> Result<Vec<JournalPayload>, SyncError>;
}

/// A simple in-memory transport for tests and offline simulation. Serializes
/// payloads to JSON on push to mimic the wire boundary.
#[derive(Default)]
pub struct InMemoryTransport {
    wire: Vec<(i64, String)>,
}

impl SyncTransport for InMemoryTransport {
    fn push(&mut self, payloads: &[JournalPayload]) -> Result<(), SyncError> {
        for payload in payloads {
            let json = serde_json::to_string(payload)?;
            self.wire.push((payload.sequence_number, json));
        }
        self.wire.sort_by_key(|(seq, _)| *seq);
        Ok(())
    }

    fn pull(&mut self, since_sequence: i64) -> Result<Vec<JournalPayload>, SyncError> {
        let mut out = Vec::new();
        for (seq, json) in &self.wire {
            if *seq > since_sequence {
                out.push(serde_json::from_str::<JournalPayload>(json)?);
            }
        }
        Ok(out)
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::conflict::SyncQso;
    use crate::journal::JournalOperation;

    fn payload(seq: i64, id: &str) -> JournalPayload {
        let qso = SyncQso {
            id: id.into(),
            callsign: "K2ABC".into(),
            band: "40m".into(),
            mode: "CW".into(),
            frequency: None,
            timestamp: 1,
            my_grid: None,
            their_grid: None,
            park_reference: None,
            notes: None,
            imported_at: None,
            modified_at: Some(1),
            qrz_confirmed: false,
            lotw_confirmed: false,
            is_hidden: false,
            ..Default::default()
        };
        JournalPayload::new(
            format!("J-{seq}"),
            "dev",
            seq * 10,
            seq,
            vec![JournalOperation::upsert_qso(qso)],
        )
    }

    #[test]
    fn push_then_pull_since() {
        let mut transport = InMemoryTransport::default();
        transport.push(&[payload(1, "a"), payload(2, "b"), payload(3, "c")]).unwrap();

        let from_one = transport.pull(1).unwrap();
        assert_eq!(from_one.len(), 2);
        assert_eq!(from_one[0].sequence_number, 2);

        let all = transport.pull(0).unwrap();
        assert_eq!(all.len(), 3);
    }
}
