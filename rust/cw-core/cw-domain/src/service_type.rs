//! Sync service type. Port of `ServiceType.swift`.

use serde::{Deserialize, Serialize};

/// A sync/lookup service. `rawValue` (Swift) maps to the serde rename below.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum ServiceType {
    Qrz,
    Pota,
    Lofi,
    Hamrs,
    Lotw,
    Clublog,
    Eqsl,
}

impl ServiceType {
    pub const ALL: [ServiceType; 7] = [
        ServiceType::Qrz,
        ServiceType::Pota,
        ServiceType::Lofi,
        ServiceType::Hamrs,
        ServiceType::Lotw,
        ServiceType::Clublog,
        ServiceType::Eqsl,
    ];

    /// The Swift `rawValue`.
    pub fn raw_value(self) -> &'static str {
        match self {
            ServiceType::Qrz => "qrz",
            ServiceType::Pota => "pota",
            ServiceType::Lofi => "lofi",
            ServiceType::Hamrs => "hamrs",
            ServiceType::Lotw => "lotw",
            ServiceType::Clublog => "clublog",
            ServiceType::Eqsl => "eqsl",
        }
    }

    /// Parse from a raw value (case-sensitive, matching Swift `init(rawValue:)`).
    pub fn from_raw_value(raw: &str) -> Option<ServiceType> {
        ServiceType::ALL.into_iter().find(|s| s.raw_value() == raw)
    }

    pub fn display_name(self) -> &'static str {
        match self {
            ServiceType::Qrz => "QRZ",
            ServiceType::Pota => "POTA",
            ServiceType::Lofi => "LoFi",
            ServiceType::Hamrs => "HAMRS",
            ServiceType::Lotw => "LoTW",
            ServiceType::Clublog => "Club Log",
            ServiceType::Eqsl => "eQSL",
        }
    }

    pub fn initial(self) -> &'static str {
        match self {
            ServiceType::Qrz => "Q",
            ServiceType::Pota => "P",
            ServiceType::Lofi => "L",
            ServiceType::Hamrs => "H",
            ServiceType::Lotw => "W",
            ServiceType::Clublog => "C",
            ServiceType::Eqsl => "E",
        }
    }

    pub fn supports_upload(self) -> bool {
        matches!(self, ServiceType::Qrz | ServiceType::Pota | ServiceType::Eqsl)
    }

    pub fn supports_download(self) -> bool {
        !matches!(self, ServiceType::Clublog)
    }

    pub fn supports_sync_mode_selection(self) -> bool {
        self.supports_upload() && self.supports_download()
    }
}

/// Per-service sync direction. Port of `SyncMode.swift`.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub enum SyncMode {
    Bidirectional,
    UploadOnly,
    DownloadOnly,
}

impl SyncMode {
    pub fn is_upload_enabled(self) -> bool {
        self != SyncMode::DownloadOnly
    }

    pub fn is_download_enabled(self) -> bool {
        self != SyncMode::UploadOnly
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn raw_value_round_trip() {
        for svc in ServiceType::ALL {
            assert_eq!(ServiceType::from_raw_value(svc.raw_value()), Some(svc));
        }
        assert_eq!(ServiceType::from_raw_value("nope"), None);
        // Case-sensitive, like Swift rawValue init.
        assert_eq!(ServiceType::from_raw_value("QRZ"), None);
    }

    #[test]
    fn upload_download_matrix() {
        assert!(ServiceType::Qrz.supports_upload());
        assert!(!ServiceType::Lofi.supports_upload());
        assert!(!ServiceType::Clublog.supports_download());
        assert!(ServiceType::Qrz.supports_sync_mode_selection());
        assert!(!ServiceType::Clublog.supports_sync_mode_selection());
    }
}
